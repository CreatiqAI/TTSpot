# TiTi guides: just-in-time tips (plan, 2026-10-08)

**Owner's brief:** make the app friendly for new members. Don't explain everything at once. When a member opens a page or taps into a feature for the first time, TiTi slides in, points at the parts that matter one at a time (with "Next"), then leaves smoothly. The first blind box gets a guided walk: what cards do, the Cards tab, trading, points, the box shop, and prizes. Then it stops.

## How a guide looks and behaves

1. **Arrival.** The screen dims and a soft spotlight (a rounded cutout with a slow pulsing ring) opens around one part of the page.
   - TiTi rises in from the bottom edge with a quick, springy settle and no continuous wobble. The owner rejected wobbly TiTi.
   - A speech card sits next to TiTi with a bold short title, one or two plain lines, step dots, a **Next** button (**Got it** on the last step) and a small **Skip**.
2. **Moving between steps.** The spotlight glides to the next part (animated rect) and TiTi swaps pose with a small cross-fade.
3. **"Tap it" steps.** The member must tap the highlighted thing themselves, for example "Tap Cards". The tap goes through to the real button, and a pointing hand pulses on it. The guide continues on the next screen.
4. **Ending.** TiTi drops out of view, the dim fades, and the page is back. It takes about 300 ms.
5. **No target on screen** (scrolled away, not built): that step shows as a TiTi card in the middle with no spotlight. It never crashes and never points at nothing.

## Rules

- **When it shows:**
  - first visit only, per guide;
  - after the page's data has loaded and things settle (about 0.7 s);
  - never during onboarding, never over a dialog, and never while another guide is showing.
- **Remembering:** a guide is marked seen when it starts, in `profiles.settings.guides_seen`, so it syncs across phones. Settings → **Tips from TiTi**: an on/off switch and **Replay tips**.
- **Copy:** short, warm buddy voice, English. Title 2–5 words; body at most about 18 words. No wall of text.
- **Accessibility:** works at text scale 1.3 and in dark map mode. Back closes the guide.

## Guides

| Id | When | Steps (intent) |
|---|---|---|
| `first_box` (journey) | First blind box opened ("Add to my cards" done): a new "What can cards do?" button | (1) "Nice pull!": cards are collectibles; collect, trade, some unlock prizes → **Show me** takes you to Me. (2) Me: spotlight the **Cards** tab, tap it. (3) Your collection. (4) **Trade** with friends. (5) **Points**: how you earn them (meets, spots, a post a week, badges, friends). (6) 100 points = a **blind box** (shop button). (7) **Prizes**: some cards redeem real rewards at partner shops. End: "Have fun exploring!" |
| `home` | First visit to Home | Feed (For you / Following), Clubs & Events, a post's like/save, search/tags |
| `map` | First visit to Map | Now / Events / Spots, filter chips, who sees me (eye), find me, the nearby bar, tap any pin |
| `create` | First time the + sheet opens | What you can make; TT now is the quick one |
| `chats` | First visit to Chats | TiTi pinned on top (ask anything); Activity tab |
| `titi_chat` | First chat with TiTi | What TiTi can do (meets nearby, weather, fuel, road tax…) |
| `profile` | First visit to Me (not during `first_box`) | My garage, points, badges, my QR (skip the cards step if `first_box` was seen) |
| `garage` | First time My garage opens | Your toy car, add a car, open the car page |
| `car_page` | First car page of my own | Mods log, papers and reminders, posts |
| `points` | First Points page | How to earn, weekly reset Friday 6 PM, blind box shop |
| `cards` | First Cards screen (outside `first_box`) | Collection, trade, prizes |
| `event` | First meet page | Going, check in at the meet (scan the host's QR), I'm on my way, meet chat |
| `spot` | First spot page | Check in at a spot (+10 once a week), moments |
| `club` | First club page | Join, club chat, official tag |
| `partner` | First partner page | Follow, vouchers, check in at the shop |
| `rewards` | First Rewards page | Vouchers and partners |

**Not guided:** settings, editors and admin and organizer tools; those are for people who already know the app. Expo mode is left alone for now (the owner's call).

## Build

The shared API lives in `lib/core/guide/` (scaffold on main):

- `Guide`, `GuideStep`, `GuideIds`;
- `guideControllerProvider` (`showOnce`, `seen`, `resetAll`);
- `GuideOnFirstView` (a wrapper widget that triggers a guide after the first frame when a condition is true);
- `guideJourneyProvider` (in-memory stage for multi-screen journeys);
- `GuideTabKeys` (the bottom bar's tab buttons).

| Track | Scope |
|---|---|
| Engine | overlay and animations, persistence, Settings switch + replay, AppShell tab keys, tests |
| Me & cards | `first_box` journey (open box button → profile → cards → points → shop → prizes), `profile`, `garage`, `car_page`, `points`, `cards`, `rewards` |
| Home & chats | `home`, `create`, `chats`, `titi_chat` |
| Map & places | `map`, `event`, `spot`, `club`, `partner` |
