# Expo mode: TT Spot at big events (plan, 2026-10-07)

Goal: one app for a car show or trade expo (MIAPEX / AIAS style). The visitor checks in at the door and gets a pass and a lucky draw number. The floor plan opens by itself. They find exhibitors, collect booth stamps and freebies, follow the stage schedule, vote for show cars and get called back for the draw. The organiser gets registration data, live numbers and exports. Exhibitors get leads.

Built ON TOP of what already exists (do not rebuild):

- **Crew roles** (`event_crew`, `is_meet_host`, `is_event_crew`) and the organizer tools screen.
- **Announcements** (audience `checked_in` already exists).
- **The lucky draw:**
  - `lucky_draws` with a seed hash, frozen entrants, alternates, claim QR, `my_draw_status` and `draw_stage`.
  - The stage screen and the `due_lucky_draws` cron.
- **Floor plans** (`event_floor_levels`, `event_floor_pins`, `event_positions`):
  - zone QR codes and the zone QR sheet;
  - the member view (`FloorplanScreen`) and the editor;
  - the invite QR (`https://ttspot.my/e/<CODE>`).
- **Check-in** (`checkins`, rotating 30 s QR `checkin_by_qr`, location radius) and the turnout report.
- **The scanner** (`ScanScreen`, `ScannedCode.parse`, `PointsActions.handle`) and **Live Activities** (meet on the lock screen).

## What we add

| # | Feature | Who sees it |
|---|---|---|
| 1 | **Door check-in with one printed QR**: the event's invite QR (`https://ttspot.my/e/<CODE>`) checks the member in when scanned in TT Spot during the event, inside the event's check-in area. Phone camera → website → store for new people | Member |
| 2 | **Check-in area per event** (`events.checkin_radius_m`, 50 m to 100 km; default stays 300 m) | Host |
| 3 | **Entry number** per event (#0001, #0002… in check-in order) = the lucky draw number. Shown on the pass, the draw card, the stage and the Live Activity | Member, stage |
| 4 | **Event pass** `/event/:id/pass`: number, name, car, pass QR (for booth lead scans), registration status, draw status, links to everything below. After a door check-in the app opens the floor plan (or the pass if no plan) with a "You're in · #0427" banner | Member |
| 5 | **Registration form**: host sets up to 8 questions (short text / one choice / many choices) + consent line + "ask to share phone & email". Member fills it after check-in (a sheet; the pass nags until done if required). Host exports CSV | Host, member |
| 6 | **Event hub card** on the event page: Pass · Floor plan · Exhibitors · Schedule · Stamps · Vote · My booth (only tiles that have data) | Member |
| 7 | **Exhibitors directory**: search by name / booth code / category; exhibitor sheet (booths, about, call, email, website, partner link); "Show on floor plan" zooms and highlights its booths. Host imports by pasting CSV; booth pins link by booth code | Member, host |
| 8 | **Partner booths stand out**: a booth pin linked to a TT Spot partner shows the partner logo large with a gold ring, plus a "Partners" filter | Member |
| 9 | **Booth stamps (stamp rally)**: stamp-stop exhibitors get a printable booth QR. Scanning it (checked in + inside the area) stamps, saves "you are here" at that booth, gives +2 points (rule `booth_stamp`, once per booth). Host sets a goal (e.g. 8 stamps) and a reward collected at the counter | Member, host |
| 10 | **Booth freebies**: an exhibitor can offer a free item (limited stock). After stamping, the member opens the freebie and the booth staff swipe "Hand over" on the member's phone. One per member, stock counted on the server | Member, booth |
| 11 | **Lead scanning**: exhibitor staff (host adds them by @handle; a linked partner's owner is staff automatically) scan a member's pass QR → lead saved. Name, @handle, state and car always; phone + email only if the member switched on "Share my contact with booths" on the pass. Member sees who has their contact and can remove it. Staff export CSV | Booth staff |
| 12 | **Stage schedule**: host adds items (time, title, where = a floor pin). Members tap "Remind me" → push 10 min before | Member, host |
| 13 | **Lucky draw roll call**: new draw option "Confirm presence N min before". At draw time − N, everyone eligible gets a push "Tap to confirm you're here". Tapping checks location against the check-in area. With roll call on, only confirmed members enter. People who left get the same push, which calls them back | Member, host |
| 14 | **Show car vote (People's Choice)**: host opens a vote; members enter their car (host approves) or host adds entries; each entry gets a number and a printable vote QR for the dashboard. Checked-in members vote once; results live for the host, public when closed | Member, host |
| 15 | **Live dashboard** for the organiser: checked in, registrations, arrivals by hour, top car makes and states, booth stamp leaderboard, freebies handed out, leads, votes, draw roll call. CSV exports (registrations, booth visits) | Host |
| 16 | **Live Activity** shows the entry number once checked in | Member (iPhone) |
| 17 | **MIAPEX demo event** (private, hosted by the admin account): the real floor plan, booths placed from the PDF, the exhibitor list from pages 4 to 13 and contacts from the company directory, so the owner can demo it to organisers | Owner |

## Rules we keep

- **The lucky draw stays legal and fair.** Entry is free and automatic on check-in. Stamps, points, votes and registration never buy extra entries or better odds. TT Spot is the sponsor of record (existing rules page).
- **Location is used at the moment of an action only:** check-in, stamp and roll call. There is no background tracking. Indoor GPS cannot find a booth, so the booth QR scan sets "you are here".
- **PDPA:** registration answers go to the organiser. Phone and email are shared only on the member's explicit tick: a form consent for the organiser, a pass switch for booths. Members can see and remove leads. Positions are purged after the event (existing cron).
- **Visitors don't download a separate event app.** Everything lives inside TT Spot.
- **Short copy, no wordy text.** Same design system: Phosphor icons via AppIcons, light theme, no overflow at font scale 1.3.

## Build tracks (parallel worktree agents)

Shared contracts are committed on main first: schema migration `0118`, route paths, stub screens, scanner cases and organizer tool rows. That way agents don't fight over the router or shared screens.

| Track | Scope | Migration |
|---|---|---|
| A Door & pass | 1–6, 16 | 0119 |
| B Exhibitors | 7, 8 | 0120 |
| C Stamps, freebies, leads | 9–11 | 0121 |
| D Schedule & roll call | 12, 13 | 0122 |
| E Vote & dashboard | 14, 15 | 0123 |
| F Demo data | 17 (PDF → floor plan PNG + booth positions + exhibitors JSON) | data only |

**After merge:** run analyze and the tests, then apply the migrations and seed the demo event. Then do a release smoke test and an overflow sweep, bump to 0.3.61 with release notes, and ship one push and one TestFlight build (with the admin alerts already on main).

## Later (not in this build)

- **Bluetooth beacons** for a live booth-level dot.
- **Universal links**, so the phone camera opens the app straight into check-in. This needs the website AASA file plus `applinks:`.
- **A big-screen web page** for the draw on ttspot.my.
- **Self-serve setup by organisers** of floor plans from a PDF.
- **Paid partner booth packages and billing.**
