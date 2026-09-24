# TT Spot launch checklist (your part)

Everything the code needs is built. These steps need your accounts, money, ID or
decisions. Tick them off in order inside each section; sections can run in
parallel. **"→ Tell Claude"** means send the file or value in chat (or save the
file in `C:\Users\Admin\.ttspot\` and say where) and Claude does the rest.

Never commit keys: the GitHub repo is public.

---

## 1. Apple (after the enrollment email arrives)

- [x] developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** → + → App IDs → App
  - Bundle ID (Explicit): `my.ttspot.app`, description `TT Spot`
  - Tick **Sign In with Apple** and **Push Notifications** (signing fails without them)
- [x] developer.apple.com → **Keys** → + → name `TT Spot push`, tick **Apple Push Notifications service (APNs)** → download the `.p8` (only once). Note the **Key ID** and your **Team ID** (top right of the page)
  - Done 2026-09-24: Team ID `CXZUA638KW`, APNs Key ID `C738XQYRAX` (Sandbox & Production), file in `.ttspot`
- [x] appstoreconnect.apple.com → My Apps → + → New App: iOS, name `TT Spot`, bundle ID `my.ttspot.app`, SKU `ttspot001`
- [x] App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → + with role **Admin** → download the `.p8`
  - GitHub repo → Settings → Secrets → Actions: add `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (whole file content)
  - → Tell Claude "API key added" → Claude runs the TestFlight workflow
- [ ] When the first build shows in TestFlight: install it yourself (TestFlight app), then
  - TestFlight → External Testing → new group → beta description, feedback email `ttspotmy@gmail.com`, privacy URL `https://creatiqai.github.io/TTSpot/privacy.html`, demo login (username `testing`, password `12341234`)
  - Submit for beta review (≈1 day) → enable **Public Link** → share it

## 2. Google Play

- [ ] Finish the USD 25 payment (Maybank: turn on online/e-commerce payments and the online limit in MAE, or use another card)
- [ ] Identity verification with your IC/passport
- [ ] Borrow an Android phone, install **Play Console** app, sign in as `ttspotmy@gmail.com` (device verification)
- [ ] Create app: name `TT Spot`, app, free
- [ ] Collect **15-20 Gmail addresses** of Android testers (you need 12 active for 14 days)
- [ ] → Tell Claude "Play account ready" → Claude prepares the listing text, Data safety answers and content rating answers
- [ ] Upload the `.aab` from GitHub Actions (latest "Android build" run → artifact `TTSpot-android-aab`) to **Closed testing**, add the tester emails, share the opt-in link
- [ ] Play Console → Test and release → **App integrity** → copy the **App signing key SHA-1 and SHA-256**
  - → Tell Claude both (for Google sign-in and app links)
- [ ] After 14 days with 12+ testers: **Apply for production**

## 3. Firebase (push notifications + crash reports)

- [ ] console.firebase.google.com → Add project `TT Spot` (Google Analytics: off is fine), signed in as `ttspotmy@gmail.com`
- [ ] Add app → **Android**, package `my.ttspot.app` → download `google-services.json`
- [ ] Add app → **iOS**, bundle `my.ttspot.app` → download `GoogleService-Info.plist`
- [ ] Project settings → **Cloud Messaging** → Apple app → upload the APNs `.p8` from section 1 (Key ID + Team ID)
- [ ] Project settings → **Service accounts** → Generate new private key → JSON file
- [ ] Crashlytics → Get started (just enable it)
- [ ] Save the three files in `C:\Users\Admin\.ttspot\` → Tell Claude
  - Claude puts the app keys into env.json + the `ENV_JSON` secret and the service account into Supabase. Push then works on the next build

## 4. Google Cloud (Google sign-in + Maps)

Same Google Cloud project as the Maps key (console.cloud.google.com).

- [ ] APIs & Services → Credentials → the **Android** OAuth client → package `my.ttspot.app`, SHA-1 `97:BA:42:10:58:0E:8D:26:BC:F2:99:15:E3:79:83:5A:CC:8D:AC:98` (upload key). Add a second Android client later with the Play app-signing SHA-1 (section 2)
- [ ] + Create credentials → OAuth client ID → **iOS**, bundle `my.ttspot.app` → copy the client ID → Tell Claude
- [ ] OAuth consent screen → app name `TT Spot`, support email, privacy + terms links → **Publish app** (In production)
- [ ] Maps API key → Application restrictions: Android apps `my.ttspot.app` + both SHA-1s, and a second key (or the same) restricted to iOS bundle `my.ttspot.app`

## 5. Email + domain

- [ ] resend.com → Domains → add `ttspot.my` → add the DNS records it shows at your domain registrar / Vercel DNS → wait for **Verified**
  - → Tell Claude → Claude switches the sender to `@ttspot.my` and turns email confirmation back on
- [ ] Optional: `support@ttspot.my` forwarding to Gmail (ImprovMX or Cloudflare Email Routing)

## 6. Website (ttspot.my on Vercel)

So shared links open the app directly instead of the GitHub Pages landing page.

- [ ] Put these two files on the Vercel site, served as JSON with no redirect:
  - `https://www.ttspot.my/.well-known/assetlinks.json` ← `tool/app-links/assetlinks.json` (Claude fills the Play SHA-256 first)
  - `https://www.ttspot.my/.well-known/apple-app-site-association` ← `tool/app-links/apple-app-site-association` (Team ID already filled in)
- [ ] Add **Associated Domains** to the App ID in section 1
- [ ] → Tell Claude → Claude switches share links to `ttspot.my` and adds the app-link config

## 7. Store listing material

- [ ] Decide the age rating answers with Claude (user content + chat usually means 12+ or 17+)
- [ ] Approve the description, keywords and screenshots Claude prepares
- [ ] Answer Apple **App Privacy** and Google **Data safety** forms using the list Claude prepares
- [ ] Demo account for reviewers: keep `testing` / `12341234` working with a car, meets, points and a voucher

## 8. Content and testing (before the public beta)

- [ ] Tell Claude which demo users / meets / spots to delete, and list real spots you trust (Claude checks coordinates)
- [ ] Full test pass on TestFlight + the Android build:
  - sign up with email, Google, Apple · onboarding · map + live location
  - create a meet, RSVP from a second account, check in with GPS at a real spot and by QR
  - chat, voice note, photo · push arrives for a message and a meet reminder
  - report a post, block a user, admin Remove / Suspend · delete account
  - turnout report after a meet · share a meet link to WhatsApp and open it
- [ ] Send Claude anything that breaks (screenshot + what you tapped)

## 9. Housekeeping

- [ ] **Back up `C:\Users\Admin\.ttspot\`** (password manager or USB). It holds the Android upload key and the iOS signing key
- [ ] Supabase → Account → Access tokens: create a new token, save it over `C:\Users\Admin\.supabase\car-meet-access-token.txt`, then revoke the old one (it was pasted in chat earlier)
- [ ] Avast → turn off HTTPS scanning again if you want Android builds on this PC (GitHub Actions builds work regardless)

## 10. Business decisions

- [ ] Paid plans are hidden in the app (`lib/core/config/store_rules.dart`). Decide how you sell Official clubs and partner plans outside the app (WhatsApp / website / invoice), then admins switch them on by hand
- [ ] Have a lawyer read the Privacy Policy and Terms (drafts)
- [ ] ~10 organizer / sponsor interviews using the turnout report (see `reports/`)

---

### Claude does as soon as you deliver

| You deliver | Claude then |
|---|---|
| App Store Connect API key secrets | Runs TestFlight upload, fixes any signing error |
| Team ID | Fills app-link file, Associated Domains |
| Firebase files | env.json + `ENV_JSON` secret + `FCM_SERVICE_ACCOUNT`, test push end to end |
| iOS Google client ID | `GOOGLE_IOS_CLIENT_ID` secret, Google sign-in on iPhone |
| Play app-signing SHA-1/256 | assetlinks.json, Google Cloud note |
| Resend domain verified | Sender on ttspot.my, email confirmation on |
| Play account ready | Listing, Data safety, rating answers, screenshots |
