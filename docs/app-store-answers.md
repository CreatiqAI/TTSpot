# App Store answers: TT Spot (my.ttspot.app)

Prepared 8 October 2026 for build 0.3.62+, against the Privacy Policy and Terms dated 8 October 2026 (`lib/core/legal/legal_text.dart`, live at https://www.ttspot.my/privacy.html and /terms.html once the website branch `legal-2026-10-08` goes live).

Privacy Policy URL: `https://www.ttspot.my/privacy.html`
Support / marketing URL: `https://www.ttspot.my`

---

## 1. App Privacy ("nutrition label")

**Do you or your third-party partners collect data from this app?** Yes.

**Tracking:** No for every data type. TT Spot has no ads SDK, no IDFA, no App Tracking Transparency prompt, and shares no data with data brokers. Every third party (Supabase, Mapbox, Google Places, Firebase, OpenAI, Kie.ai, Resend) is a service provider working for TT Spot.

Purposes Apple offers: Third-Party Advertising, Developer's Advertising or Marketing, Analytics, Product Personalization, App Functionality, Other Purposes. TT Spot uses only **App Functionality**, **Analytics** and **Product Personalization**.

### Data types to tick

| Apple category | Data type | Linked to user | Tracking | Purposes | What it is in TT Spot |
|---|---|---|---|---|---|
| Contact Info | Name | Yes | No | App Functionality | Display name and username |
| Contact Info | Email Address | Yes | No | App Functionality | Sign-in, account emails (Resend); shared with an event organiser only with consent |
| Contact Info | Phone Number | Yes | No | App Functionality | Required once (one account per person); friends can call only if allowed; organisers and booths get it only with consent |
| Financial Info | Other Financial Info | Yes | No | App Functionality | Optional car papers: insurer, policy number, NCD, sum insured |
| Location | Precise Location | Yes | No | App Functionality, Analytics | Map sharing, TT now, check-ins, booth stamps, draw roll call, opt-in background sharing. Analytics because the Mapbox map SDK sends its own anonymous telemetry |
| Location | Coarse Location | Yes | No | App Functionality, Analytics | Rounded position shown to Nearby / Everyone, rough position for address search and nearby meets, weather area for TiTi tips |
| User Content | Emails or Text Messages | Yes | No | App Functionality | Chat messages and TiTi chats |
| User Content | Photos or Videos | Yes | No | App Functionality | Profile, car, post, moment, chat and TiTi photos and videos; car photos sent to OpenAI / Kie.ai |
| User Content | Audio Data | Yes | No | App Functionality | Voice notes in chat |
| User Content | Customer Support | Yes | No | App Functionality | Reports on posts, members, meets and clubs |
| User Content | Other User Content | Yes | No | App Functionality | Posts, comments, meets, car details and mods, registration answers, show car votes, cards and trades |
| Search History | Search History | No | No | App Functionality | Address search text sent to Google Places through our server, with no account ID |
| Identifiers | User ID | Yes | No | App Functionality | Supabase account ID; also set as the Crashlytics user ID |
| Identifiers | Device ID | Yes | No | App Functionality | Push notification token (FCM / APNs) |
| Purchases | Purchase History | Yes | No | App Functionality | Partner voucher redemptions and the bill amount the partner types (no in-app purchases) |
| Usage Data | Product Interaction | Yes | No | App Functionality, Analytics, Product Personalization | Check-ins, points history, post views and likes, feed ranking, page tips seen, partner page views; Mapbox telemetry |
| Diagnostics | Crash Data | Yes | No | App Functionality | Firebase Crashlytics, linked through the user ID |
| Diagnostics | Other Diagnostic Data | Yes | No | App Functionality, Analytics | App version, device model and OS sent with crash reports; Mapbox SDK diagnostics |

### Leave unticked

- Contact Info: Physical Address (home **state** only), Other User Contact Info
- Health & Fitness; Financial Info: Payment Info, Credit Info
- Sensitive Info
- Contacts (the app never reads the address book)
- User Content: Gameplay Content (cards and boxes are covered under Other User Content)
- Browsing History
- Usage Data: Advertising Data, Other Usage Data
- Diagnostics: Performance Data (no Firebase Performance)
- Surroundings, Body, Other Data

### Cross-check before you submit

- In Xcode, open the archive and run **Generate Privacy Report**. It merges the privacy manifests of Mapbox, Firebase and the other SDKs. Anything it lists that the table above leaves out, add it.
- The Mapbox SDK telemetry is the only reason "Analytics" appears on Location and Diagnostics. To drop it, turn Mapbox telemetry off in code and remove those Analytics ticks.

---

## 2. Age rating (2025 questionnaire)

**Recommendation: 18+**, which matches the Terms ("You must be 18 or older"). The answers below probably calculate to a lower rating (13+ or 16+). In **Age Rating > Override**, choose **18+**.

### In-app controls and capabilities

| Question | Answer | Why |
|---|---|---|
| Parental Controls | No | None in the app |
| Age Assurance | No | Age 18+ is declared in the Terms; there is no age verification |
| Unrestricted Web Access | No | No in-app browser; links open in Safari or the linked app |
| User-Generated Content | **Yes** | Posts, moments, comments, chat, meets, clubs. Moderated: an automatic OpenAI check on every post and moment, report on every item, block on every member, reviewed within 24 h |
| Messaging and Chat | **Yes** | One-to-one and group chat with text, photos, video and voice notes. Members can limit messages to friends only |
| Advertising | **Yes** | No ad networks, but partner shops promote vouchers, meets and events inside the app |

### Mature themes

| Question | Answer |
|---|---|
| Profanity or Crude Humor | None |
| Horror / Fear Themes | None |
| Alcohol, Tobacco, or Drug Use or References | None |

### Medical or wellness

| Question | Answer |
|---|---|
| Medical or Treatment Information | None |
| Health or Wellness Topics | No |

### Sexuality or nudity

| Question | Answer |
|---|---|
| Mature or Suggestive Themes | None |
| Sexual Content or Nudity | None (forbidden by the Terms and filtered) |
| Graphic Sexual Content and Nudity | None |

### Violence

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Guns or Other Weapons | None |

### Chance-based activities

| Question | Answer | Why |
|---|---|---|
| Simulated Gambling | None | No casino-style mechanics |
| Contests | **Frequent** | Free lucky draws at events and People's Choice show car votes |
| Gambling (real money) | No | No real-money wagering. Draw entry is free; nothing bought or earned adds entries |
| Loot Boxes | **Yes** | Card blind boxes. They open only with points earned by using the app, cannot be bought with money, and the odds are shown before opening |

### If App Store Connect asks these too

The form has changed more than once. If it shows these questions, answer:

- **Location sharing with other users:** Yes. Members choose Friends, Friends + nearby, Everyone or Nobody. Strangers see only a rounded position. Sharing while the app is closed is opt-in.
- **AI chatbot / generative AI:** Yes. TiTi (OpenAI) answers questions and can send short tips. AI toy cars and portraits come from Kie.ai. Every AI feature asks permission before it first sends data, and the Terms say AI answers can be wrong.
- **Digital purchases:** No. There are no in-app purchases or subscriptions.
- **Made for Kids:** No.

---

## 3. Export compliance

- **Does your app use encryption?** Yes, but only standard encryption: HTTPS/TLS through iOS networking and the Supabase, Firebase, Mapbox and other SDKs, plus Sign in with Apple. There is no proprietary or non-standard algorithm.
- This is **exempt** under Category 5, Part 2 (the "standard encryption / mass-market" exemption for authentication and secure transport), so no documentation or ERN is needed.
- `ITSAppUsesNonExemptEncryption` is already `false` in `ios/Runner/Info.plist`, so App Store Connect will not ask on each build.
- France declaration: not needed for this case.

---

## 4. Review notes (draft for App Review Information > Notes)

> **Demo account:** username `testing`, password `12341234` (log in with the username, no email needed). It is an ordinary member account with no admin rights. Because the Terms were updated on 8 Oct 2026, the first login may show "Complete your account". Tick the Terms and tap Done to reach the map.
>
> **About the app:** TT Spot is a car community for Malaysia: a live map of meets, car spots and friends' cars, a feed, chat, car clubs, and event tools for car shows.
>
> **Location:** The app asks for location "While Using" to show your car to the friends you choose and to verify check-ins. Background location is **off by default**. It is opt-in only, under **Settings > Privacy > Share location when TT Spot is closed**, behind an in-app disclosure. It can be turned off there at any time. Members can also hide completely with "Nobody (ghost)".
>
> **Lucky draws:** Organisers of verified events can run a lucky draw. Entry is **free and automatic** on check-in, one entry per member, and nothing bought or earned adds entries. The rules are shown in the app on the event page. TT Spot is the sponsor of record, prizes come from the organiser, and **Apple is not a sponsor** and is not involved in any draw. The Terms cover this under "Lucky draws".
>
> **Blind boxes:** Card blind boxes open **only with points earned in the app** (checking in, posting, bringing a friend). They cannot be bought with money, and cards have no cash value. The **odds for each rarity are shown in the app** before a box is opened.
>
> **Payments:** The app has **no in-app purchases and sells no digital goods**. Partner (workshop and shop) plans and official car club plans are business arrangements made directly with TT Spot outside the app. Plan prices are not shown in the app and nothing links to an outside payment. Partner vouchers are redeemed in person at the shop.
>
> **AI features:** TiTi, the in-app assistant (OpenAI), car photo recognition (OpenAI) and AI toy cars and portraits (Kie.ai) **ask the member's permission before their data is first sent** to these providers. The Privacy Policy names each provider and what it receives. OpenAI does not train on this data. New posts and moments go through OpenAI's automated moderation check.
>
> **User-generated content:** Every post, comment, moment, message, meet, club and profile can be reported. Any member can be blocked. Reports are reviewed within 24 hours.
>
> **Account deletion:** **Settings > Account > Delete account** (type DELETE to confirm) deletes the account and everything posted from the app.
>
> **Contact:** ttspotmy@gmail.com

---

## Before you submit: check these

1. **The AI permission prompt must ship in the build.** The policy and these notes say TiTi, car photo recognition and the toy car ask permission before data first goes to OpenAI or Kie.ai (guideline 5.1.2(i)). In 0.3.62 there is no such prompt: TiTi chats send straight away, car photos are recognised during onboarding, and the toy car is made automatically on car save (migration 0106). Ship the prompt, or change the policy, before you submit.
2. **The demo account must re-accept the Terms.** `kTermsVersion` is now `2026-10-08`, so every member, `testing` included, sees "Complete your account" once. Log in as `testing` on the review build and accept the Terms, so the reviewer goes straight to the map.
3. Run **Generate Privacy Report** in Xcode and reconcile it with section 1.
