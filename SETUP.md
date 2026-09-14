# TT Spot — developer setup

Solo-dev notes. Everything here is boring on purpose.

## 0. What's already done on this machine

- Flutter 3.47.2 stable cloned to `C:\Users\Admin\flutter` (not on PATH yet, see step 1)
- Supabase CLI 2.106.0 at `C:\Users\Admin\supabase-cli`
- Project scaffolded (`flutter create`, Android + iOS)

**Not installed:** Android Studio / Android SDK / Java. You need these to run an emulator (step 2).

## 1. Put Flutter on PATH (once)

PowerShell (as your user, no admin needed):

```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Users\Admin\flutter\bin", "User")
```

Close and reopen your terminal, then:

```powershell
flutter --version
flutter doctor
```

## 2. Android Studio (needed for the emulator)

```powershell
winget install --id Google.AndroidStudio -e
```

Open Android Studio once → **More Actions → SDK Manager** → install:
- Android SDK Platform (latest)
- Android SDK Build-Tools
- Android SDK Command-line Tools
- Android Emulator

Then **Device Manager → Create Device** → Pixel 8, latest Google Play image.

Confirm:

```powershell
flutter doctor
```

"Android toolchain" should show an SDK version. It may also say "Android license status unknown":
that is expected with 2026 Android command-line tools (the old `--android-licenses` flag is a no-op now).
The licence was accepted in the Android Studio wizard and lives at `AppData\Local\Android\sdk\licenses\`.
Gradle reads that file directly, so builds work. (iOS needs a Mac; ignore for now.)

### Avast + Gradle (already handled on this PC)

Avast Web Shield re-signs HTTPS traffic with its own root certificate. Java doesn't trust it, so the
Gradle wrapper download failed with `PKIX path building failed`. Android Studio's bundled Java
(JetBrains Runtime) lacks the Windows crypto provider, so `WINDOWS-ROOT` does not work either.

Fix applied (no admin): a private trust list at `C:\Users\Admin\.java-truststore\cacerts` = the
JBR default list + the Avast root (`avast-root-1.cer` in the same folder), and a user env var:

```
JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=C:\Users\Admin\.java-truststore\cacerts -Djavax.net.ssl.trustStorePassword=changeit
```

Every Java process (Gradle wrapper, Gradle daemon, Android Studio) now trusts Avast's certificate.
Open a new terminal after setting it. If Avast rotates its root, re-export it and re-import:

```powershell
$c = Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like '*Avast*'
Export-Certificate -Cert $c -FilePath C:\Users\Admin\.java-truststore\avast-root-1.cer -Type CERT
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -importcert -noprompt -alias avast-web-shield-root-2 -file C:\Users\Admin\.java-truststore\avast-root-1.cer -keystore C:\Users\Admin\.java-truststore\cacerts -storepass changeit
```

### Emulator quirks on this PC (both handled)

**DNS hangs inside the emulator.** Hostname lookups from the emulator stall (IP pings work).
Start the emulator with public DNS servers instead of the Android Studio play button:

```powershell
& "$env:LOCALAPPDATA\Android\sdk\emulator\emulator.exe" -avd Pixel_8 -dns-server 8.8.8.8,1.1.1.1
```

**Avast re-signs the emulator's HTTPS too**, so the app got `CERTIFICATE_VERIFY_FAILED` talking to
Supabase. Debug builds now trust one extra root certificate supplied through env.json:

```
"DEV_EXTRA_CA_PEM_B64": "<base64 of C:\Users\Admin\.java-truststore\avast-root-1.pem>"
```

Wired in `main.dart` (`_trustDevCertificateIfConfigured`), guarded by `kDebugMode`, so release
builds never see it. To regenerate the value:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Users\Admin\.java-truststore\avast-root-1.pem"))
```

Alternative if you'd rather not carry this: Avast → Menu → Settings → Protection → Core Shields →
Web Shield → untick "Enable HTTPS scanning". Then both this and the Java truststore become unnecessary.

### NDK (already installed on this PC)

The Android Gradle Plugin tries to auto-install NDK 28.2.13676358 through the retired `sdkmanager`,
which crashes (NTSTATUS 0xC0000409). Installed it directly instead:

```powershell
& "$env:LOCALAPPDATA\Android\sdk\cmdline-tools\latest\bin\android.exe" sdk install "ndk;28.2.13676358"
```

Verified 2026-09-09: `flutter build apk --debug` succeeds (Gradle ~4 min first time, ~30 s after).

## 3. Supabase project (done 2026-09-10)

Project **TTSpot**, ref `gsoaoabefjavdaiqhahu`, region Singapore. This folder is already linked.
Schema + seed were applied through the Management API with a personal access token stored at
`C:\Users\Admin\.supabase\car-meet-access-token.txt` (outside the repo; never commit it).

To run more SQL or future migrations from PowerShell:

```powershell
$env:SUPABASE_ACCESS_TOKEN = Get-Content C:\Users\Admin\.supabase\car-meet-access-token.txt
supabase db push                                          # applies any new files in supabase/migrations
supabase db query --linked -f supabase/seed.sql           # base demo data (safe to repeat)
supabase db query --linked -f supabase/seed_social.sql    # social demo data; run AFTER seed.sql
supabase db query --linked -f supabase/seed_location.sql  # friends, past meets, check-ins, live pins
supabase db query --linked -f supabase/seed_spots.sql     # recommended spots + check-ins; run LAST
```

Migrations applied to TTSpot so far (all three are also recorded in `supabase_migrations.schema_migrations`):

| File | What it adds |
|---|---|
| `20260909000001_init.sql` | profiles, cars, events, RSVPs, event comments, reports, blocks, RLS, buckets `avatars` / `event-covers` / `car-photos` |
| `20260910000002_social.sql` | the social layer: follows, places, clubs, posts (post / spotted / poll / guide), likes, saves, comments, poll votes, stories, notifications, badges + TT streak, car build log (`car_mods`), Car of the Week, DMs + meet chats, bucket `post-photos`, triggers, RPCs, cron jobs, realtime |
| `20260911000003_events_view_columns.sql` | recreates `events_with_counts` so `place_id` / `club_id` come through |
| `20260912000004_location_enums.sql` | new notification types (friend_request, friend_accepted, tt_now, checkin) |
| `20260912000005_location_layer.sql` | the location layer: friendships (mutual), `user_locations` live pins, `checkins`, moments (stories with lat/lng + event/place), `tt_now()` instant meets, `places_with_counts` + regulars/busy-days RPCs, `event_recap()`, `device_tokens` for push |
| `20260912000006_spots.sql` | Spots: `places.cover_url/description/tags/recommended`, `place_checkins` (one per person per place per day, 300 m proof via `checkin_place()`), ranked `places_with_counts` view (`score`), `place_recent_visitors()`, moments at a place count as a check-in, Explorer badge |
| `20260914000006_points_enum.sql` | notification types `referral`, `points` |
| `20260915000009_vendor_enums.sql` | Notification types `partner`, `voucher` |
| `20260915000011_club_enum.sql` | Notification type `club_invite` |
| `20260915000012_clubs_location.sql` | Car clubs + location rules: `partner_applications.kind` (vendor / club), `profiles.club_owner` (only owners/admins may insert into `clubs`), `club_invites` + `invite_to_club` / `respond_club_invite` / `my_club_invite`, `club_members.share_location` + `set_club_share` / `my_club_share`, `is_clubmate_sharing`, `user_locations` read policy now friends **or** sharing clubmates, `visible_pins()` (adds `via`, `club_name`), `checkin_radius_m` setting (300) and `checkin_by_qr` now requires GPS within it |
| `20260915000010_vendors.sql` | Partners: `platform_settings` (`commission_rate` 0.01), `partner_applications` → `vendors`, `vouchers`, `voucher_claims` (QR `ttspot://voucher/<claimId>/<code>`), `voucher_redemptions` (bill × rate), RPCs `apply_partner`, `admin_review_partner`, `save_voucher`, `claim_voucher`, `lookup_voucher_claim`, `redeem_voucher`, `shop_vouchers`, `my_vouchers`, `my_vendor*`, `vendor_monthly_report`, `admin_commission_report`, nightly claim-expiry cron |
| `20260914000008_spot_stickers.sql` | Spot stickers: `places.sticker_secret` (printed QR `ttspot://spot/<id>/<code>`), `profiles.is_admin`, `spot_verifications` (pending → approved / rejected / review), `submit_spot_verification`, `decide_spot_verification` (service role only), `review_spot_verification` (admins), `admin_review_queue`, stale-pending cron |
| `20260914000007_points_qr.sql` | Points + QR: append-only `point_ledger` + `award_points()` (idempotent via `idem_key`), `point_rules` (tunable values), `profiles.points`, referrals (`claim_referral`, paid on first check-in via `settle_referral`), earn triggers on meet/spot check-ins, badges and Car of the Week, friend QR (`profiles.qr_token`, `my_qr_payload`, `rotate_my_qr`, `add_friend_by_qr`), organiser check-in QR (`events.qr_secret`, HMAC over 30 s windows: `event_qr_payload`, `checkin_by_qr`, source `qr` skips the distance rule) |

### What the social migration turned on server-side

- **Realtime**: `messages` and `notifications` are in the `supabase_realtime` publication (chat + activity badge update live).
  Convoy live mode uses Realtime *Presence* on channel `convoy:<eventId>`, no table needed.
- **pg_cron** (already enabled on the project):
  - `ttspot-car-of-week` — Mondays 00:05 UTC, `pick_car_of_week()` picks last week's most-liked car post.
  - `ttspot-event-reminders` — daily 01:00 UTC, `send_event_reminders()` notifies attendees of tomorrow's meets.
  - `ttspot-expire-stories` — hourly, deletes stories more than a day past `expires_at`.
- **RPCs the app calls**: `get_or_create_dm`, `get_or_create_meet_chat`, `mark_conversation_read`, `claim_spotted`,
  `current_week_leader`, `tt_streak_weeks`. Notifications and badges are awarded by triggers, never from the client.
- **Storage path rule** for every bucket: `<userId>/...` — RLS only lets you write under your own id.

### The location layer (2026-09-12 pivot)

TT Spot is a map first. The Instagram-style feed is still in the code but switched off by
`kSocialFeed` in `lib/core/config/features.dart`. What is on:

- **Friends are mutual** (`friendships` + `send_friend_request` / `respond_friend_request` / `remove_friend` RPCs).
  Only friends see each other's pins.
- **Live pins, Snapchat model**: the app calls `update_my_location()` every ~12 s *while it is open* (no background
  tracking). The RPC snaps you to the nearest place, auto-checks-you-in to a meet you RSVP'd to when you are within
  500 m of it, and reports a nearby live meet you can check in to. Ghost mode = `set_ghost(true)`.
- **Check-ins** prove "went". The trigger rejects them outside the meet window (1 h before start until `ends_at`,
  default start + 6 h) or further than 500 m away.
- **Moments** are `stories` rows with `lat`/`lng`/`event_id`/`place_id`. On the map for 24 h; kept forever in the
  meet's / place's album (the expiry cron only deletes untagged ones).
- **TT now** = `tt_now(lat, lng, venue, title, hours)`: instant meet at your spot, you are checked in, friends get a
  `tt_now` notification.
- **Before layer**: `places_with_counts` view, `place_regulars()`, `place_busy_days()`, `event_recap()`.
- Realtime: `user_locations` is in the publication; RLS filters it to friends.

### Points + QR (2026-09-14)

- Every earn action goes through `award_points()`; the `point_rules` table is the only place values live (edit it in the
  dashboard, no deploy). `profiles.points` is a cached balance; the ledger is the truth.
- Friend QR = `https://ttspot.my/u/<username>?t=<token>`. The token rotates when the user taps refresh, so old
  screenshots stop working. Scanning it makes both people friends instantly (both are physically present) and, for a
  brand-new member, counts as a referral.
- Meet check-in QR = `ttspot://checkin/<eventId>/<code>`. The organiser's screen refetches every 30 s; the code is an
  HMAC of the time window and the event's secret, so a photo of it expires within a minute. Current and previous window
  are accepted for clock drift.
- Referral code = username, entered at sign-up or implied by scanning a friend's QR. Paid out only after the new
  member's first real check-in (fake accounts earn nothing).
- Scanner (`Me → scan icon`, or from Friends / the meet's check-in card) handles every code type; it can also read a QR
  from a saved photo. Packages: `qr_flutter` (draw), `mobile_scanner` (camera, adds the CAMERA permission).
- **Spot stickers (打卡点)**: each recommended spot has a printed QR (`ttspot://spot/<placeId>/<code>`; regenerate with
  `python tool/make_stickers.py` → `build/stickers/*.png` + `stickers.pdf`, A6 at 300 dpi). Scanning it opens the
  verified check-in screen: photo → upload → `submit_spot_verification` → the `verify-spot-photo` Edge Function asks
  OpenAI (`gpt-4o-mini`, Responses API, JSON schema) whether there is a real car in a real photo. Car + real + within
  300 m → approved on the spot (photo becomes a moment at the place, +20 check-in +50 verified). Clearly no car / a
  screenshot → rejected. Anything else (no GPS, too far, unsure, API down) → `review`, and an admin decides in the app
  (Me → menu → Review queue; admins = `profiles.is_admin`, `testing` is one). Pending rows older than 24 h fall into
  review automatically (cron). Secrets: `OPENAI_API_KEY` set via `supabase secrets set` from
  `C:\Users\Admin\.supabase\ttspot-openai-key.txt`; optional `OPENAI_VISION_MODEL`. Deploy with
  `supabase functions deploy verify-spot-photo --use-api`. If a sticker leaks, `admin_rotate_sticker(place_id)` and reprint.
- **Partners + Rewards (2026-09-15)**: any member applies from `Me → menu → Become a partner` (name, type, address,
  phone, optional SSM no. / logo). Admins see it under `Partner applications` (and get an Activity notification) and
  approve or reject with a reason; approval creates the `vendors` row and the same menu item turns into
  `Partner dashboard`. Vendors publish vouchers (% off / RM off / free item, min spend, optional points cost, stock,
  per-member limit, end date). Members see them in `Rewards` (also the button on the Points card), claim (points are
  deducted through the ledger, reason `redeem`), and get a QR in `My vouchers`. At the counter the vendor scans it with
  the normal scanner (non-partners get a friendly refusal), sees who/what, **types the bill**, optionally snaps the
  receipt, confirms. `redeem_voucher` books commission = bill × `commission_rate` (default 1 %, per-vendor override in
  `vendors.commission_rate`; change the default with `admin_set_setting('commission_rate', '0.02')`). Vendors see a
  monthly statement (`Statement` in the dashboard); admins see commission owed per partner per month
  (`Commission report`). Demo partner: `weiling_gr` owns "Typeone Bar" with a "10% off drinks" voucher.
- **Car clubs (2026-09-15)**: the same application flow (`Me → menu → Run a car club`, or the create hub) with
  `kind = 'club'`; admins see a CAR CLUB badge in the queue. Approval sets `profiles.club_owner`; only owners can
  create clubs (RLS). Owners invite friends from the club page (`Invite members`); invitees get an Activity notification
  and a banner on the club page. Members see each other on the map (`Friends & club on the map`, pins say which club)
  and can switch it off per club with "Show me on the club map". Vendor partners are meant for parts / accessories /
  workshop businesses; the type list reflects that.
- **Location rules (2026-09-15)**: after onboarding the app shows a location screen (`/location`) once per launch
  until permission is granted ("Not now" skips for that session). A meet's QR is only accepted within
  `checkin_radius_m` (300 m, `platform_settings`) of the meet: the scanner fetches a fresh fix, sends it with the
  code, and the server rejects "no location" or "too far" with the distance. Organiser QR still rotates every 30 s.
- **iPhone feel + address search (2026-09-14)**: tapping outside a text field closes the keyboard (app-level
  `GestureDetector` in `main.dart`); every pushed page uses Cupertino transitions on both platforms, so swiping from
  the left edge goes back; dropdowns are replaced by `PickerField` (bottom-sheet list, `lib/core/widgets/picker_field.dart`);
  profile tabs cross-fade/slide (`AnimatedSwitcher`). The meet form has "Search a place or address"
  (`PlaceSearchField`) backed by the `places` Edge Function, which calls the Google Places API (New) with the secret
  `GOOGLE_PLACES_KEY` (= the Maps key; the key never ships in the app; signed-in members only). Picking a result
  drops the pin and fills the venue name. Deploy with `supabase functions deploy places --use-api`.
- **Demo data trimmed (2026-09-14)**: 6 members (testing, mingshun, newbie_1708, weiling_gr, amir_hakim, kumar_evo),
  5 meets (4 upcoming + 1 past TTDI Thursday TT), 11 places (8 recommended), 1 poll post. Backup of what was removed:
  `C:\Users\Admin\.supabase\ttspot-seed-backup-2026-09-14.json`. `seed*.sql` files still hold the full original set for a
  fresh database.
- **Brand theme (2026-09-14)**: `AppColors.brand` = logo red `#E00008`, `ink` = `#101010`. `primary`, `accent` and the
  highlight surface (`warnColor`, kept for its many call sites) are all the brand red; text on those surfaces is white.
  Profile: tapping the **Me tab again** opens the menu (`showProfileMenu` in `profile/presentation/profile_menu.dart`,
  grouped Account / Rewards / Partners & clubs / Admin). `PickerField` opens from anywhere in the box (the arrow included).
- **Profile v3 (2026-09-15, user-approved "A top + B bottom")**: centered avatar in the brand ring, name, one row of
  tappable numbers (Meets / Friends / Cars / Points), Edit profile · Rewards · QR, bio, badge chips, then the cars as a
  row of circles (tap → car page, `+` adds). Tabs are a pinned `SliverPersistentHeader` (`ProfileTabBar`, icon + label,
  sliding underline). **Garage tab = showroom**: one 16:10 card per car (`ShowroomCard`: photo, dark fade, checkered
  corner, make in caps, model in the display face, year on a number-plate chip) + "Park another car". Moments = 4:5
  grid. **Rewards and vouchers are one page** (`/rewards`, tabs Shop / My vouchers; `/rewards?tab=vouchers` opens the
  wallet; `Routes.myVouchers` now points there).
- Planned: lucky draw (legal check first), weekly post leaderboard points.

### App structure (2026-09-12)

Tabs: **Posts** (For you / Following / Spots) · **Map** (Now / Upcoming / Spots layers, with a list toggle that shows
the Meets list inside the same tab) · **Chats** (Chats / Activity) · **Me**. Sign-up is two steps: profile, then a car
with at least one photo (`Profile.needsCar` drives the router). `kSocialFeed` in `lib/core/config/features.dart`
hides the feed if you ever want the map-only version back.

If you ever reset the database: `init.sql` → `social.sql` → `events_view_columns.sql` → `location_enums.sql` →
`location_layer.sql` → `spots.sql` → `seed.sql` → `seed_social.sql` → `seed_location.sql` → `seed_spots.sql`.

**Quick test login:** username `testing`, password `12341234` (email `testing@ttspot.my` also works).

**Login + password reset (2026-09-14):** the sign-in form takes an email **or a username** in every build. Usernames
are resolved by the `login` Edge Function (deployed with `--no-verify-jwt`, it runs before sign-in): it looks the
username up with the service role, signs in server-side, and returns the session; the phone installs it with
`auth.setSession`. The email is never sent back, so usernames can't be used to harvest emails. "Forgot password?"
takes an email or username too; the function calls `resetPasswordForEmail` with
`redirectTo: https://creatiqai.github.io/TTSpot/reset.html` and always answers "ok". That page (`docs/reset.html`,
served by **GitHub Pages** from the `docs/` folder) reads the tokens from the URL fragment, lets the member set a new
password right there (works on a PC), and on a phone also offers "Open in the TT Spot app" (`ttspot://reset-password`
+ the same fragment; Android `ttspot` intent filter, iOS `CFBundleURLSchemes`). In the app supabase_flutter picks the
tokens from the URL (auth flow is **implicit** for this reason), fires `passwordRecovery`, and the router opens
`/reset-password`. Allowed redirect URLs live in the Supabase auth config. `docs/index.html` is a tiny landing page
with the Android download.

**Email sending (2026-09-14):** auth emails go through **Resend** SMTP (`smtp.resend.com:465`, user `resend`,
password = the send-only API key kept at `C:/Users/Admin/.supabase/ttspot-resend-key.txt`, never in the repo).
Branded templates (recovery, confirmation, magic link, email change) are pushed with `python tool/email_templates.py`.
Sender is `TT Spot <onboarding@resend.dev>` until the **ttspot.my** domain is verified in Resend (Domains → Add →
add the DNS records at the registrar); until then Resend only delivers to the Resend account's own address
(creatiqai@gmail.com). After verification, change `smtp_admin_email` to e.g. `hello@ttspot.my` (same PATCH as the
templates script) and the emails reach everyone. `ttspot.my` is owned; the GitHub Pages site can move there later
(`docs/CNAME` + a CNAME record for www pointing at creatiqai.github.io).

Other demo logins (password `password123` for all): amir@example.com, weiling@example.com,
kumar@example.com, farah@example.com, jason@example.com.

Email auth is on by default. Google provider gets enabled during the auth step.

### Local alternative (needs Docker Desktop)

```powershell
supabase start        # local Postgres + Auth + Storage on localhost:54321
supabase db reset     # applies migrations AND seed.sql
```

Use the printed local `API URL` and `anon key` in env.json instead.

### Phase 5: simpler flows + club accounts (2026-09-16)

Migration `20260916000013_accounts_simplify.sql` (applied):

- **Accounts.** Tap the `@handle` on the Me tab (or Me menu → Switch account) to act as **Personal**, a **car club** you own or admin, or your **partner** business. The Me tab then shows the club page / partner dashboard; the create sheet makes posts and meets as the club (`posts.as_club`, `events.club_id`). Only owner/admins may post as the club (RLS). In-memory only: resets to Personal on relaunch.
- **Club admins.** Owner taps a member on the club page → *Make admin* sends a `club_invites` row with `role='admin'`; the member accepts from Activity or the club banner. Owner can demote (`set_club_role`) and owner/admins can remove members (`remove_club_member`). Roles: `club_member_roles`, `my_club_roles`.
- **Meets.** `events.visibility` = `public` | `friends` (default friends in the form; Everyone for clubs). Read policy: public, or organiser, friend, club member or attendee. Form trimmed to title, type (Meet / Convoy / Track day), when, where, who can see, details. No max attendees, no club picker (use the account switcher).
- **TT now.** One field (Places autocomplete, prefilled with your current spot) + Start. Fixed 3 hours.
- **Spots search.** Typing shows Google Places matches; tap one to jump the map there.
- **Friends.** `suggest_friends()` → "People you may know" (mutual friends, same club, same car make, same state, newest). No more "crew" wording.
- **Profile.** Posts · Garage · Saved (Saved has a Saved/Liked switch). Moments row replaces car circles; avatar ring is red only while a moment is live; tap avatar → view / change photo. Badge chips removed (still under Me menu → Badges). Showroom plate only when the year is set.

## 3b. Google sign-in (one-time, ~15 min)

Email sign-in works already (email confirmation is switched off on the project for development;
turn it back on before launch under Authentication → Providers → Email). "Continue with Google"
needs two OAuth clients in Google Cloud and the provider enabled in Supabase.

1. https://console.cloud.google.com → pick the **Car Meet** project (same one as the Maps key, or make one).
2. **APIs & Services → OAuth consent screen** → External → app name "Car Meet", your email → Save.
   Under *Test users* add your own Gmail while the app is unpublished.
3. **APIs & Services → Credentials → + Create credentials → OAuth client ID**, twice:

   | Type | Fields | Result |
   |---|---|---|
   | **Web application** | Name: `Supabase`. Authorised redirect URI: `https://gsoaoabefjavdaiqhahu.supabase.co/auth/v1/callback` | Copy **Client ID** *and* **Client secret** |
   | **Android** | Package name: `my.carmeet.car_meet`. SHA-1: `E7:9F:7B:7A:A4:6B:05:63:B3:CB:65:9F:62:B4:03:F8:C2:79:DA:7C` | Nothing to copy |

   That SHA-1 is this PC's debug signing key (`%USERPROFILE%\.android\debug.keystore`). A release
   build or another PC needs its own Android client with its own SHA-1.

4. Supabase dashboard → **Authentication → Providers → Google** → Enable → paste the *Web* Client ID
   and Client secret → Save. (Or give the two values to Claude and it sets them through the API.)
5. `env.json` → `"GOOGLE_WEB_CLIENT_ID": "<the Web client ID>"`. Then **stop and rerun** the app;
   `--dart-define` values are baked in at build time, hot reload won't pick them up.

Until step 5 is done, the Google button shows "Google sign-in isn't set up yet. Use email for now."

Demo logins for testing: see section 3.

## 4. App config (never commit)

Copy `env.example.json` → `env.json` and fill in from **Settings → API Keys** in the dashboard
(use the `sb_publishable_...` key; the legacy `anon` key also works):

```json
{
  "SUPABASE_URL": "https://xxxx.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "GOOGLE_WEB_CLIENT_ID": "",
  "GOOGLE_IOS_CLIENT_ID": ""
}
```

Google Maps key (Android): https://console.cloud.google.com → APIs & Services → enable
**Maps SDK for Android** → Credentials → create API key (restrict to Android app later).
Add to `android/local.properties` (gitignored):

```
MAPS_API_KEY=AIza...
```

## 5. Run

```powershell
flutter pub get
flutter run --dart-define-from-file=env.json
```

VS Code: add to `.vscode/launch.json` so F5 works:

```json
{
  "configurations": [
    {
      "name": "car_meet (dev)",
      "request": "launch",
      "type": "dart",
      "toolArgs": ["--dart-define-from-file=env.json"]
    }
  ]
}
```

## 5b. On a real phone

**Android** (any tester): every push to `main` runs `.github/workflows/android.yml`, which publishes the release APK
to a rolling GitHub Release. Share this one link with testers:
**https://github.com/CreatiqAI/TTSpot/releases/download/latest/TTSpot.apk** — open it on the phone, tap the file,
allow "install from this source". Locally: `flutter build apk --release --dart-define-from-file=env.json` →
`build/app/outputs/flutter-apk/app-release.apk`. Release builds are signed with the debug key, which is fine for sideloading. With USB debugging on:
`flutter install` or `adb install -r <apk>`. Release builds need the **full email** to log in (`testing@ttspot.my`);
only debug builds expand a bare username.

**iPhone** (no Mac needed): iOS can only be compiled on macOS, so `.github/workflows/ios.yml` builds it on GitHub's
macOS runners (free for public repos) on every push that touches `lib/`, `ios/`, `assets/` or `pubspec.*`, or from
Actions → "iOS build (unsigned IPA)" → Run workflow. It uploads an **unsigned**
`TTSpot-v<version>-<yyyymmdd>-<sha>-unsigned.ipa` artifact. **Before a push you want on the phone, bump `version:` in
`pubspec.yaml`** (e.g. `0.2.0+2` → `0.2.1+3`); the build number shows in iPhone Settings → TT Spot.
After the run is green, `python tool/fetch_ipa.py` saves it to `build/ios-artifact/` and adds the row to
`CHANGELOG.md` (the log of every build that went to a phone).
Build-time config comes from repo secrets `ENV_JSON` (= env.json), `MAPS_API_KEY`, `GOOGLE_IOS_CLIENT_ID`
(`gh secret set NAME < file`). Then:

1. On Windows install **Sideloadly** (sideloadly.io) and Apple's **iTunes** or **Apple Devices** app (USB driver).
2. Plug the iPhone in, trust the computer, open Sideloadly, sign in with your Apple ID, drag the `.ipa` in, Start.
3. On the phone: Settings → General → VPN & Device Management → trust the developer profile → open TT Spot.
4. iOS 16+ then asks for **Developer Mode**: Settings → Privacy & Security → Developer Mode → on → restart → Turn On.
5. Updating: sideloaded apps never self-update. Download the new IPA from the latest Actions run and press Start in
   Sideloadly again (login and data are kept).
6. Free Apple ID = the app expires after **7 days** (re-run Sideloadly to refresh). A paid Apple Developer account
   (USD 99/yr) gives 1-year sideloads and, better, **TestFlight**: add signing certs to the workflow and upload with
   `xcrun altool`; testers then install from the TestFlight app with no cable. Sideloadly is per-phone (PC + cable +
   the tester's own Apple ID), so for iPhone friends TestFlight is the only practical route.

iOS reads the Maps key and Google client id from `ios/Flutter/Secrets.xcconfig` (gitignored; generated locally from
env.json + local.properties, written by CI from the secrets). Google sign-in on iPhone needs an iOS client id in
Google Cloud first (see 3b); email login works without it.

## 6. Dependencies

Approved and in use: supabase_flutter, google_maps_flutter, flutter_riverpod, go_router, google_sign_in,
image_picker, geolocator, qr_flutter, mobile_scanner. Deliberately not added: intl (own formatter in lib/core/utils/dates.dart),
cached_network_image.

## 6a. Icons and art (no packages needed)

Two icon sets live in `assets/`, both MIT licensed (notices next to the files):

- **Phosphor Icons** (`assets/fonts/Phosphor.ttf` + `Phosphor-Fill.ttf`) for every UI icon. Use them through
  `AppIcons` in `lib/core/theme/app_icons.dart` (`Icon(AppIcons.mapPin)`, selected states use `...Fill`).
  That file is generated: to add a glyph, put its Phosphor name in `REGULAR`/`FILL` inside
  `tool/gen_icons.py` and re-run it (`python tool/gen_icons.py`, needs internet). Never use `Icons.*` from Material.
- **Fluent Emoji 3D** (`assets/art/*.png`, 256 px) for illustrated icons: event types, place kinds, badges, empty
  states, the create hub, map chips and the launcher icon. Use `ArtIcon(AppArt.car, size: 24)` or
  `ArtIcon.emoji('🏁')`; `AppArt.forEmoji` maps server-side emoji (badges) to art. To add one, put it in the
  `ART` table of `tool/fetch_art.py` (folder name from https://github.com/microsoft/fluentui-emoji/tree/main/assets),
  run it, then add a constant to `AppArt`.

Launcher icon and Android 12 splash: `python tool/make_launcher.py` (needs `pip install pillow`) draws the 3D car on
the TT-now orange and writes `android/app/src/main/res/mipmap-*`, `mipmap-anydpi-v26` and `values-v31/styles.xml`.

## 6b. Old note (superseded)

The approved stack is `supabase_flutter`, `google_maps_flutter`, `flutter_riverpod`, `go_router`.
The MVP scope needs these too; they are commented out in `pubspec.yaml` until you say yes:

| Package | Why | Needed by step |
|---|---|---|
| `geolocator` | get user location to center the map | map |
| `image_picker` | pick avatar / cover / car photos from gallery or camera | auth (avatar) |
| `google_sign_in` | native Google sign-in; hands the ID token to Supabase | auth |
| `intl` | format dates ("Sat, 14 Sep · 8:00 PM") | map |
| `cached_network_image` | optional: avoid re-downloading marker thumbnails | map |

## Project layout

```
lib/
  main.dart                     bootstraps Supabase + Riverpod + router (debug-only extra CA trust)
  core/
    env.dart                    --dart-define config
    supabase/supabase_client.dart   client + auth state providers
    theme/app_theme.dart        Instagram-style LIGHT theme (white, #0095F6); dark colours only for the map
    router/app_router.dart      all routes (Routes class) + auth/onboarding redirects
    router/app_shell.dart       bottom nav: Posts / Map / Chats / Me (starts the location publisher)
    config/features.dart        kSocialFeed switch (feed off by default)
    utils/{dates,geo,friendly_error}.dart
    widgets/                    PinMap, photo picker sheet, avatars, buttons, EmptyState, EventListTile
  features/
    auth/     sign in / sign up / onboarding, AuthRepository (debug: bare name -> @ttspot.my)
    map/      dark map home with Now / Upcoming / Before layers, friend avatar pins, live-meet pins, moment
              bubbles, place history chips (widgets/map_pins.dart), map_sheet, tt_now_sheet
    friends/  friendships + live pins: domain/friend, data/friends_repository, application (friendPinsProvider,
              LocationPublisher, nearbyMeetProvider), presentation/friends_screen
    points/   ledger + QR + stickers: domain/{points,verification}, data/points_repository,
              application/points_providers (PointsActions.handle / verifySpot / review),
              presentation (scan, my_qr, points, event_qr, spot_verify, admin_review)
lib/core/location/location_gate.dart           first-launch location permission screen + providers
    vendors/  partners + rewards: domain/vendor, data/vendors_repository, application/vendors_providers,
              presentation (partner_apply, admin_partners, vendor_dashboard, vendor_edit, voucher_form, redeem,
              rewards, my_vouchers, voucher_qr, vendor_report, admin_commission)
supabase/functions/verify-spot-photo/index.ts   Edge Function: OpenAI photo check for sticker check-ins
supabase/functions/places/index.ts              Edge Function: Google Places autocomplete + details proxy
supabase/functions/login/index.ts               Edge Function: username login + password reset email
lib/features/auth/presentation/reset_password_screen.dart   opened by the ttspot://reset-password link
lib/core/places/places_service.dart             client for it; lib/core/widgets/place_search_field.dart = the UI
lib/core/widgets/picker_field.dart               bottom-sheet picker used instead of dropdowns
tool/make_stickers.py                            printable spot stickers (PNG + PDF)
    events/   event details (place link, club row, meet chat, go live, photo wall), create event,
              my events, convoy_live_screen (Realtime presence)
    profile/  profile (posts/followers/following, badges, streak), car detail + build log,
              car form, car mod form, follow lists, badges screen, edit profile
    social/   domain/ (post, notification, chat, club)  data/ (social, notifications, chat, community repos)
              application/ (providers)  presentation/ (explore feed, post card, poll, masonry grid,
              stories row + viewer + creator, create post, post detail, search, create hub, activity,
              inbox, chat, club, create club, place, saved)
supabase/
  migrations/20260909000001_init.sql                schema + RLS + storage buckets
  migrations/20260910000002_social.sql              social layer (see section 3)
  migrations/20260911000003_events_view_columns.sql events view refresh
  seed.sql                                          6 users (incl. testing), cars, 15 Klang Valley events
  seed_social.sql                                   follows, club, 8 posts, likes, poll votes, stories, mods, a DM
  seed_location.sql                                 friendships, 6 past meets w/ check-ins, moments, a live TT now, pins
  seed_spots.sql                                    8 recommended spots (Genting Sempah, Ulu Yam…), tags, covers, check-ins
assets/map_style_dark.json             Google Maps dark style
```

Pattern: one repository class per feature wrapping Supabase; Riverpod providers hold logic; widgets stay dumb.
PostgREST gotcha: when a table has two FK paths to `profiles` (e.g. posts -> profiles directly and via post_likes),
name the FK in the embed: `profiles!posts_author_id_fkey(...)`.
