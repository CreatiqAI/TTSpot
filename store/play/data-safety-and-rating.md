# Play Console answers: Data safety, content rating, app content

Answers match what the app does as of 0.3.38. Where a question is a judgement call it is marked **(check)**.

## Data safety (Policy → App content → Data safety)

**Does your app collect or share any of the required user data types?** Yes
**Is all of the user data collected by your app encrypted in transit?** Yes (HTTPS/TLS to Supabase, Firebase, Mapbox, OpenAI)
**Which account creation methods?** Username and password; Sign in with Apple (iOS only, answer "Other" if asked)
**Can users request that their data is deleted?** Yes. In the app: Me → Menu → Settings → Delete account. On the web: https://www.ttspot.my/delete-account.html

**Is data shared with third parties?** No. Supabase, Firebase, Mapbox and OpenAI process data on TT Spot's behalf as service providers, which Play does not count as sharing.

Data types to tick, all **Collected**, **not shared**, **processed ephemerally: No**, **required or optional** as marked:

| Category | Data type | Required? | Purposes |
|---|---|---|---|
| Location | Precise location | Optional (the app works without it, the map just can't show you) | App functionality |
| Location | Approximate location | Optional | App functionality |
| Personal info | Name | Required | App functionality, Account management |
| Personal info | Email address | Required | Account management, Developer communications |
| Personal info | User IDs | Required | App functionality, Account management |
| Personal info | Phone number | Required | Account management, Fraud prevention, security and compliance |
| Photos and videos | Photos | Optional | App functionality |
| Photos and videos | Videos | Optional | App functionality |
| Audio | Voice or sound recordings | Optional (voice notes in chat) | App functionality |
| Messages | Other in-app messages | Optional (chat) | App functionality |
| App activity | App interactions | Required | App functionality, Analytics **(check: only if you keep usage stats; points, check-ins and meets count as app functionality)** |
| App activity | Other user-generated content | Optional (posts, comments, moments) | App functionality |
| App info and performance | Crash logs | Required | App functionality **(Firebase Crashlytics)** |
| App info and performance | Diagnostics | Required | App functionality |
| Device or other IDs | Device or other IDs | Required | App functionality (push notification token) |

Not collected: financial info, health, contacts, calendar, web history, installed apps, files and docs, SMS.

## Content rating (Policy → App content → Content rating)

Category: **Social** (IARC questionnaire "All other app types" if Social isn't offered)

| Question | Answer |
|---|---|
| Violence, blood, sexual content, profanity, drugs | No |
| Does the app let users interact or exchange content? | **Yes** (chat, posts, comments) |
| Does the app share the user's current physical location with other users? | **Yes** (friends can see you on the map if you allow it) |
| Does the app allow users to buy digital goods? | No (points are earned, not bought) |
| Gambling: real-money gambling, or simulated gambling? | No. **(check)** Lucky draws are free and blind boxes are opened with earned points only, never money |
| Does the app contain loot boxes purchasable with real money? | No |
| Unrestricted internet access / web browser | No |

Expected result: around PEGI 12 / Everyone 10+ with "Users interact" and "Shares location" notices. The app itself asks for 18+ in its Terms.

## Other App content items

- **Privacy policy:** https://www.ttspot.my/privacy.html
- **App access:** "All or some functionality is restricted". Give the reviewer the demo login: username `testing`, password `12341234` (has a car, meets, points and a voucher).
- **Ads:** No, the app does not contain ads.
- **Target audience:** 18 and over only.
- **News app:** No.
- **COVID-19 contact tracing / status:** No.
- **Government app:** No.
- **Financial features:** None.
- **Health:** No.
- **Data deletion page:** https://www.ttspot.my/delete-account.html
- **Advertising ID:** No, the app does not use the advertising ID. **(check: Firebase Analytics is not included, so this is correct)**
- **Foreground service / exact alarms / full-screen intents:** not used. **Location permission:** foreground only ("while using the app").

## After the listing

1. Create a **Closed testing** track, upload the `.aab` from the latest GitHub Actions "Android build" run (artifact `TTSpot-android-aab`).
2. Add 12 or more tester emails, share the opt-in link, and keep them active for 14 days.
3. Then App integrity → copy the app signing SHA-1 and SHA-256 and send them to Claude (app links and the Maps key restriction).
4. After 14 days: apply for production.
