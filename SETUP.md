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
(creatiqai@gmail.com). After verification, change `smtp_admin_email` to `noreply@ttspot.my` (sender name TT Spot; replies and the in-app contact go to ttspotmy@gmail.com, Gmail cannot be a Resend sender) (same PATCH as the
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

### Map v2 (2026-09-15, migration 0018)

- `cars.color` (9 keys, see `car_marker.dart` `kCarColors`); car form has a colour row. Markers are painted with `paintCar` and cached by `CarMarkerFactory`.
- `user_locations.share_mode` ('friends' | 'nearby' | 'ghost') + `share_radius_m`; `set_share_mode(mode, radius)`; the old `set_ghost` maps onto it. `visible_pins()` returns friends/clubmates as before plus `via = 'nearby'` strangers when both sides are in nearby mode and within the stranger's own radius; their lat/lng is rounded to 3 dp and profile fields are blanked. Blocks are respected.
- `tt_now(lat, lng, venue, title, p_minutes, p_invitees uuid[], p_address)`: 15–480 min, invitees are RSVP'd + notified; the app then drops one `messages.event_id` card in each invitee's DM.
- `events.address` (from Google when picked by search). Meet page: address line + Waze / Google Maps / WhatsApp / Copy link. `url_launcher` (already a transitive dependency of supabase_flutter, now direct) opens `waze://`, `comgooglemaps://`, `whatsapp://` with https fallbacks (`core/utils/open_external.dart`); iOS `LSApplicationQueriesSchemes` lists the three schemes. Share link = `https://creatiqai.github.io/TTSpot/m.html?id=<event>` (docs/m.html → `ttspot://event/<id>`).
- Migration 0019: share_mode adds `public` (Everyone). `visible_pins()` now shows nearby/public strangers to any signed-in viewer (rounded position, no face); nearby needs the viewer inside the stranger's own radius. `places` function gained `action: 'nearby'` (Places searchNearby, 250 m, includedTypes list) for the TT sheet's Use my location.
- Migration 0021: radius up to 10 000 m. `nearbyPlacesProvider(placeKey(lat,lng))` caches Places nearby per ~100 m cell; the TT pill and TT sheet read it. `MapPalette` (app_theme.dart) makes the map sheet white by day / dark at night.
- Map: `assets/map_style_light.json` by day (07:00–19:00), dark otherwise. Radar = `Circle`s driven by an AnimationController fired every 5 s only in Now mode. Controls left on the map: layer switch, eye (visibility sheet), locate. TT pill lives in the sheet (`_TtPill` in map_sheet.dart): start / at-a-spot / mine live / friend's live.

### Routing gotcha: go_router 18 + `package:flutter/material.dart` (2026-09-15)

go_router 18 checks for `MaterialApp` using `package:material_ui`'s class. This app uses `package:flutter/material.dart`'s
`MaterialApp`, a different class, so the check fails and go_router logs `Using WidgetsApp configuration` and builds
`NoTransitionPage`s: no slide animation, no iOS swipe-back. Every route therefore goes through `page(s, child)` in
`app_router.dart`, which returns an explicit `MaterialPage`. **New routes must use `pageBuilder: (_, s) => page(s, …)`,
not `builder:`.** (Diagnosed by printing `ModalRoute.of(context).runtimeType`: `_CustomTransitionPageRoute` = wrong.)

### Phase 5: simpler flows + club accounts (2026-09-15)

Migration `20260916000013_accounts_simplify.sql` (the 16 in the name is only the sort key) (applied):

- **Accounts.** Tap the `@handle` on the Me tab (or Me menu → Switch account) to act as **Personal**, a **car club** you own or admin, or your **partner** business. The Me tab then shows the club page / partner dashboard; the create sheet makes posts and meets as the club (`posts.as_club`, `events.club_id`). Only owner/admins may post as the club (RLS). In-memory only: resets to Personal on relaunch.
- **Club admins.** Owner taps a member on the club page → *Make admin* sends a `club_invites` row with `role='admin'`; the member accepts from Activity or the club banner. Owner can demote (`set_club_role`) and owner/admins can remove members (`remove_club_member`). Roles: `club_member_roles`, `my_club_roles`.
- **Meets.** `events.visibility` = `public` | `friends` (default friends in the form; Everyone for clubs). Read policy: public, or organiser, friend, club member or attendee. Form trimmed to title, type (Meet / Convoy / Track day), when, where, who can see, details. No max attendees, no club picker (use the account switcher).
- **TT now.** One field (Places autocomplete, prefilled with your current spot) + Start. Fixed 3 hours.
- **Spots search.** Typing shows Google Places matches; tap one to jump the map there.
- **Friends.** `suggest_friends()` → "People you may know" (mutual friends, same club, same car make, same state, newest). No more "crew" wording.
- **Profile.** Posts · Garage · Saved (Saved has Saved / Liked / Commented pills). **Moment albums** (migration 0014: `moment_albums`, `moment_album_items`, view `moment_albums_with_counts`; moments inside an album stay readable after they expire) show as circles under the bio; owner creates from the + tile or the Create sheet, edits/deletes from the viewer's ⋯ menu. Migration 0015: `messages.post_id/story_id` (shared cards in chat), `story_viewers()` (author sees who viewed). Migration 0016: `conversation_members.pinned_at/hidden_at`, `set_conversation_pin` (max 3), `hide_conversation` (delete-for-me; reappears on a new message). Every moment a member posted lives on in Me menu → My moments (author-only read). Migration 0017: `messages.image_url/sticker/event_id/place_id/car_id` + `chat-photos` bucket (camera / gallery / sticker / attach in the composer). Migration 0020: `messages.audio_url/audio_ms/video_url` + `chat-media` bucket (50 MB, m4a/mp4). Packages `record` (AAC-LC 64 kbps m4a to a temp file via `path_provider`), `just_audio` (VoiceBubble), `video_player` (VideoBubble, inline + long-press full screen); mic permission declared on both platforms. Composer: hold the mic (long-press) to record, slide left 80 px to cancel, auto-stop at 2 min; camera and gallery buttons open a photo / video choice. Moments row replaces car circles; avatar ring is red only while a moment is live; tap avatar → view / change photo. Badge chips removed (still under Me menu → Badges). Showroom plate only when the year is set.

### Settings + admin account + map colours (2026-09-15, migrations 0022–0023)

- `profiles.settings jsonb` + `update_my_settings(p_patch)` (merge). Keys: `notif_tt/meets/messages/friends/rewards` (bool), `map_theme` auto|light|dark (consulted by `_isNight` in map_screen.dart), `show_car_color`, `auto_checkin`, `units`, `dm_from` everyone|friends. `get_or_create_dm` raises when the target is friends-only and you are not a friend (migration 0023). `AppSettings`/`settingsProvider` in `features/settings/application`; a patch applies locally first, then the RPC, then refetches the profile.
- Settings screen (Me menu → Settings): notifications toggles (saved now, pushes arrive once the app is published), map theme, car colour, auto check-in, units, who can see my car (opens the visibility sheet), who can message me, blocked people, Privacy Policy / Terms (rendered from `core/legal/legal_text.dart`; the same text is published as `docs/privacy.html` + `docs/terms.html` by `python tool/gen_legal.py`; rerun it when the text changes), contact (mailto), version (`core/config/app_version.dart`: bump `kAppVersion`/`kAppBuild` with pubspec), change password (reset email), log out, delete account (`delete_my_account()` removes profile + auth user; typed DELETE confirm).
- `friend_tags(owner_id, friend_id, color)`: colour a friend's car/dot on the map, only for you (other user's profile ⋯ → Colour on the map). Map colours: me red, friends blue, club purple, nearby/public grey, tags override (`kTagColors` in car_marker.dart). Legend under "On the map" in the map sheet.
- Map: my car is drawn in every layer; below zoom 12.5 every person is a `CarMarkerFactory.dot` (small dot in the relationship colour), above it the painted car. `MapPalette.defaultLight` (set by MapScreen each build) makes modal sheets opened outside the map tree (Filters) follow the day theme.
- TT now: `ttPlaceProvider` remembers the place picked in the sheet; the pill and the reopened sheet keep it while you are within 1 km. Chips row has a fade + "swipe for more" hint.
- **Admin account**: `AdminAccount` in the switcher (only when `profiles.is_admin`) → `AdminDashboardScreen` (dark): stats grid (`admin_stats()`), queues (photo reviews, partner/club applications, reports via `admin_reports()`/`admin_resolve_report()`, commission), platform settings (`admin_set_setting`: commission_rate, checkin_radius_m), members (`admin_recent_users()`, ⋯ → make/remove admin or club owner via `admin_set_role`). The old ADMIN items left the Me menu; only "Switch to TT Spot Admin" remains there.

### Accounts: email code, phone, Terms, linked logins (2026-09-15, migration 0024)

- **Sign-up** = email + password → Supabase emails a **6-digit code** (`mailer_autoconfirm=false`, `mailer_otp_length=6`, 15 min; template shows `{{ .Token }}`; all set by `python tool/auth_config.py`) → `VerifyEmailScreen` (`/verify?email=`) calls `verifyOTP(type: signup)`. Logging in before confirming resends the code and opens the same screen (the `login` function passes `email_not_confirmed` through for username logins).
- **Every account must complete**: username, phone number, current Terms (`kTermsVersion` in legal_text.dart). `profile_private(user_id, phone, terms_accepted_at, terms_version)` is readable only by the owner; `set_account_basics(phone, terms_version)`, `set_my_phone(phone)`, `my_account_basics()` (also returns `email_confirmed` and linked `providers`). `accountBasicsProvider` feeds the router: incomplete → `/onboarding` ("Complete your account" for existing members: phone + Terms tick, everything else prefilled). Phones are stored E.164; `normalizePhone` assumes Malaysia when no country code (012… → +6012…). One phone per account.
- **Settings → Account**: email (verified or not), phone (edit sheet), sign-in methods (link/unlink Google via `linkIdentityWithIdToken` with the native Google picker; `security_manual_linking_enabled=true`), change password (email accounts, reset link) or set a password (Google-only accounts). About page (`/settings/about`) shows version + what's new (`core/config/release_notes.dart`, add a block per phone build) with licences at the bottom.
- **Email delivery (done 2026-09-15)**: ttspot.my is verified in Resend (DNS on Vercel), and Supabase sends as `TT Spot <noreply@ttspot.my>` (`smtp_admin_email`). Any address can receive sign-up codes and resets now. Email verification at sign-up is still switched off (`python tool/auth_config.py --verify` turns it back on).
- Google sign-in / linking still needs the one-time §3b setup (Google Cloud OAuth clients + `external_google_enabled`); the buttons say so until then.

### Map markers v3 (2026-09-15, migration 0025)

- One small shape per thing (`widgets/map_glyphs.dart`, painters shared with the on-map key `widgets/map_legend.dart`): **balloon** = event, **feather flag** = TT session (`event_type = 'tt'` / `is_instant`), **badge** = spot (red star = recommended, grey pin = regular). Photo cards are gone from the map; covers live in the sheet rows. `EventMarkerFactory` was deleted.
- Zoom tiers in `map_screen.dart`: < 13 far (events, TT, spots + my own dot only; no other people, no moments), 13–14.5 mid (people as relationship-colour dots, moments), ≥ 14.5 close (cars with faces + name/time chips under every marker).
- Spots layer = `places_with_counts.is_spot` (recommended, or has cover / spot check-ins / posts / moments). Places that only hosted a meet are venue records and stay off the map. `on_event_insert` no longer creates a place for instant TT sessions; old "My spot"/"Pinned spot" rows were deleted.
- Friend colour: the dot next to a friend in the map sheet (and the profile ⋯ menu) opens `showFriendColourSheet` (`friends/presentation/friend_colour_sheet.dart`).
- Email verification is **off** for now (`python tool/auth_config.py --no-verify`); turn it back on with `--verify` once Resend delivers to everyone.

### Organisers, top spots, suggestions (2026-09-15, migrations 0026–0027)

- **Who organises what.** `event_type = 'tt'` (TT session, now or planned) = anyone. Every other type = a club owner/admin (`club_id`), a partner (`events.vendor_id`, owner of an active vendor) or an admin. Enforced by the events insert policy; the app maps the 42501 to a friendly message. Create sheet: personal account → "TT session · Plan one for later" (`CreateEventScreen(session: true)`: no type, no cover, friends by default); club / partner account → "Event". `events_with_counts` carries `vendor_name`/`vendor_logo_url`; the meet page shows "Hosted by <partner>".
- **Top spot** (`places_with_counts.is_top`, read into `Place.recommended`): `top_override` 'top' / 'never' wins; else `recommended` (editorial) or ≥ 20 spot check-ins or ≥ 3 events in the last 90 days. Quiet spots drop back on their own. `admin_set_top(place, override)`.
- **Suggest a spot**: Create sheet row and the Spots layer header → `SuggestSpotScreen` (Places search, kind, photo to post-photos/spots, note) → `place_suggestions`. Admin dashboard → "Spot suggestions" → `admin_review_suggestion(id, approve)` creates/reuses the place (photo = cover), marks it a spot, pays 30 points (`spot_suggested`). `admin_stats.pending_suggestions`.
- **Real venues** seeded in 0026 (Pavilion Bukit Bintang, MAEPS Serdang, Putrajaya Boulevard, Desa ParkCity Waterfront, Kayu SS2, Pelita Jalan Ampang, Steven's Corner OUG, KKB–Fraser's Hill; TTDI mamak renamed to Kopi Dua Darjat). Coordinates are approximate: open each on the map and nudge before launch. The "nadayu28" test place was removed.

### Per-account inboxes, tab sets, admin pages, chat composer (2026-09-15, migration 0028)

- **Tabs follow the account** (`core/router/tab_slot.dart` + `app_shell.dart`): personal Posts · Map · Chats · Me; club Club · Events · Chats · Account; partner Dashboard · Chats · Account; admin Dashboard · Members · Queues · Account. The four StatefulShell branches stay; `TabSlot(i)` picks the screen. Switching accounts jumps to that account's first tab. `AccountTab` = the entity's own tools + switch / settings / log out.
- **Inboxes**: `conversations.club_id / vendor_id` = owner account (meet chats inherit from the event; "Message club" DMs via `get_or_create_club_dm` / `get_or_create_vendor_dm`). `InboxScope` (chat_repository.dart) filters: personal hides chats of accounts I manage; club / partner shows only its own. `messages.as_club / as_vendor` mark replies sent as the account (trigger `check_message_actor` enforces manager + right chat); bubbles show the club / partner name and logo. `conversation_members.muted_at` + `set_conversation_mute`; muted chats do not count in the badge.
- **Admin**: light theme everywhere. Members tab = search (name, handle, email, phone) + filters (new, active today, admins, club owners, partners, no car) + role actions; Queues tab = decision queues + reports with Open / Resolved filter and resolve-with-note. `admin_recent_users` now returns `is_partner` and `email`.
- **Chat**: `widgets/chat_composer.dart` = [+] [Message…] [camera] [mic]; + opens a tile sheet (Photos, Video, Camera, Spot, Meet, My car, Sticker); mic tap → full-width "Hold to speak" bar (hold to record, slide left to cancel, X closes). Meet chats: header "n going" + members button, hosting card ("You're hosting" / "Hosted by …" · time · venue), HOST badge on the organiser's messages and in the members list. Mute switch in chat info.

### Call a friend (2026-09-16, migration 0029)

- `friend_phone(p_user)` returns a friend's E.164 number only when they set `settings.calls_from = 'friends'` (Settings → Privacy → "Who can call me", default nobody) and have not blocked you. `showCallSheet` (`friends/presentation/call_sheet.dart`) offers Phone (`tel:`) or WhatsApp (`whatsapp://send?phone=` with `wa.me` fallback). Entry points: Call action on a friend's profile header, Call button on the DM's chat info page. Android manifest declares `tel`, `https`, `whatsapp` intents + the WhatsApp package for `canLaunchUrl`.
- Real in-app calls (LiveKit / Agora) wait for the store build: incoming calls need VoIP push + CallKit / Firebase push, which sideloaded builds cannot receive.

### Map sizing (Waze standard) + intro (2026-09-16)

- Zoom tiers in `map_screen.dart`: far (< 13) = every event / TT session / spot is a small dot (`GlyphMarkerFactory.dot`: red for meets and TT, grey spot, black top spot), no people; mid (13–14.5) = shapes at 85 % (`scale:` on balloon / flag / spot), people as dots; close (≥ 14.5) = full shapes + name chips, cars. Matches how Waze collapses to dots at city zoom.
- `IntroScreen` (`features/onboarding/presentation/intro_screen.dart`): four slides after sign-in, once per account (`profiles.settings.intro_seen`), router redirect to `/intro` before onboarding. Replay from Settings → About → "Show the intro again".

### Partner fixes (2026-09-16, migration 0030)

- Shop address fields (`partner_apply_screen.dart`, `vendor_edit_screen.dart`) are `PlaceSearchField`s (Google Places via the `places` function); the picked name + address is stored as text.
- Stale-cache rules: `showAccountSwitcher` and app resume (AppShell `didChangeAppLifecycleState`) invalidate `myVendorProvider`, `managedClubsProvider`, `currentProfileProvider`, `accountBasicsProvider`; switching to `AdminAccount` invalidates every admin provider; approve/reject invalidates `adminStatsProvider`.
- `vendor_monthly_report(p_vendor)`: null = the caller's own vendor, always; only admins may pass another vendor. Cross-vendor totals: `admin_commission_report`.

### Partner pages + shop on the map (2026-09-16, migration 0031)

- `vendors.lat/lng/hours/photo_urls` (≤ 6), `partner_applications.lat/lng` (from the Google-picked address), `places.vendor_id` (one place per partner). `sync_vendor_place(vendor)` creates / updates the place (name, kind = business type, position, logo as cover) on approval and on every `update_my_vendor(...)` (new signature with p_lat/p_lng/p_hours/p_photo_urls; the 4-arg one was dropped). Partners approved before this need to re-pick their address once in Edit shop to get a position.
- `vendors_public` view (owner_id, hours, photos, phone, live_vouchers, upcoming_events) feeds `PartnerScreen` at `/partner/:id`: logo, photo carousel in the app bar, type chip, description, Message (`get_or_create_vendor_dm`), WhatsApp, address, hours, Waze / Maps / Check in (→ the linked place page), vouchers (from `shopVouchersProvider` filtered by vendorId), upcoming events (`vendorEventsProvider`).
- Map: partner places render as `MapPinFactory.partner` (round logo, white ring, red tag; dot at far zoom is red); tap → partner page. Legend row "Partner shop". `places_with_counts` carries `vendor_id/vendor_logo/vendor_name` and `is_spot` is true for partner places. Place kinds now include the business types (`Place.kindLabel/kindArt`).
- Entry points: Rewards shop voucher card (tap the partner name), event page "Hosted by", place page "Partner page" button, Partner account tab "My partner page".

### Partners, round two (2026-09-16, migration 0033)

- **Opening hours are structured.** `vendors.hours_json` = `{"mon": {"open": "10:00", "close": "19:00"}, …, "sun": null}`; `hours` (text) is still written as the generated summary ("Mon–Fri 10 AM–7 PM · Sat 10 AM–5 PM · Sun closed") so older rows and the place page keep working. Dart: `OpeningHours` / `DayHours` / `HoursEditor` in `features/vendors/presentation/widgets/hours_editor.dart` (per-day switch, tap a time for the wheel picker, "Same as Monday for Tue–Sat"). The partner page shows `OpeningHours.status()` ("Open now · closes 7 PM" / "Closed · opens tomorrow 10 AM") with the week expandable underneath.
- **Posting as the partner.** `posts.vendor_id + as_vendor`; the insert policy allows `as_vendor` only when `can_act_as_vendor(vendor_id)`. `posts_with_counts` recreated (still `p.*`). Post model has `vendor` (NamedRef from `vendor:vendors(id, name, logo_url)`) and `asVendor`; post card and grid tiles show the partner as the face (→ `/partner/:id`) with "by @username". Entry points: Partner account tab "Post as <name>", the + hub while the partner account is active (Post / Poll only; Spotted, Guide and the Club tag hide). Partner page lists the last 5 posts.
- **Partner numbers.** `vendor_page_views (vendor_id, viewer_id, day)` + `view_partner(vendor)` (one row per member per day; the owner never counts; called from `partnerViewedProvider` when the page opens). `my_vendor()` now also returns `hours_json, views_30d, checkins_30d` (check-ins at the linked place) and `claims_30d` (voucher_claims on this vendor's vouchers). Dashboard shows them as a second stat row.

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
Actions → "iOS build (unsigned IPA)" → Run workflow. It uploads an unsigned
`TTSpot-<version>.ipa` artifact (version = `pubspec.yaml`, e.g. `TTSpot-0.2.0.ipa`). **Before a push you want on the phone, bump `version:` in
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
