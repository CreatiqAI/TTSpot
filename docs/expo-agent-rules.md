# Rules for Expo mode build agents

You are building one track of **Expo mode** in TT Spot. TT Spot is a Malaysian car community app: Flutter, Riverpod 3 without codegen, go_router, and Supabase. The owner is away and will review everything later, so finish your track completely without asking questions. Make sensible calls and list them in your final report.

## Read first

- `docs/expo-mode-plan.md`: the whole plan and its numbered features.
- `supabase/migrations/20261008000118_expo_schema.sql`: the shared schema. It is **already applied to the live database**. Don't edit it. If you truly need another column, add it in your own migration with `add column if not exists`.
- `lib/features/expo/expo_routes.dart`: every route is already registered in `lib/core/router/app_router.dart`, pointing at stub classes. Replace the stubs you own; keep each class name and constructor.
- Existing code you build on:
  - `lib/features/organizer/**`: lucky draw, announcements, crew and organizer tools.
  - `lib/features/floorplan/**`.
  - `lib/features/events/**`.
  - `lib/features/points/presentation/scan_screen.dart` and `lib/features/points/application/points_providers.dart` (`ScanOutcome`, `PointsActions.handle`).
  - `supabase/migrations/20260929000067_lucky_draw.sql` and `supabase/migrations/20260929000068_event_floorplans.sql`.

## File ownership

Only edit files your track owns, plus new test files. Each prompt lists what it owns. Shared files (the router, `event_details_screen.dart`, `organizer_tools_screen.dart`, `points.dart`, `points_providers.dart`) were already wired by the lead. Don't touch them unless your prompt says so.

## Tools and environment

- **Flutter:** `C:\Users\Admin\flutter\bin\flutter` (not on PATH). Run `flutter analyze` and the full `flutter test`. Both must be clean before you finish.
- **Packages:** no new pub packages, ever. Already available:
  - `qr_flutter`, `mobile_scanner`, `share_plus`, `path_provider`, `url_launcher`;
  - `geolocator`, `cached_network_image`, `image_picker`, `crypto`.
- **SQL:**
  - Put your RPCs in YOUR migration file (number given in your prompt). Use `security definer set search_path = public` and `create or replace`.
  - When you replace an existing live function, fetch its live body first with `pg_get_functiondef`. The repo files can be older than live.
  - Run SQL against the live project with the helper:
    `python -I C:/Users/Admin/AppData/Local/Temp/claude/c--Users-Admin-Desktop-Car/728d582b-1d46-4f67-af4a-4b586ffa8b1f/scratchpad/q.py [--tx] file.sql [--out out.json]`.
    `--tx` wraps the run in begin…rollback.
  - **Test your migration only with `--tx`** (dry run). Add a test script that creates throwaway data inside the transaction and selects results.
  - **Never apply anything live.** The lead applies all migrations after merging.
  - To read live definitions, a plain (non `--tx`) SELECT is fine.
- **No emulator.** Don't run the app on a device or emulator; the lead does device QA after merging. Write widget and unit tests where they help: parsers, models, CSV building, pure logic.

## SQL building blocks

- **Notifications:** insert into `public.notifications (user_id, type, event_id, body, actor_id)`. A trigger sends the push. Use existing enum values only:
  - `'announcement'`: body = `"<title>\n<text>"`;
  - `'lucky_draw'`: body = the sentence.
  - Look at `lucky_draw_notify` for the pattern.
- **Points:** `public.award_points(p_user, public.rule_points('<reason>'), '<reason>', '<ref_type>', '<ref_id>', null, '<unique key>')`.
- **Hosts:** `public.is_meet_host(event)` covers host, co-host, club officers and admin. `public.is_event_crew(event)` covers crew. `public.is_exhibitor_staff(exhibitor)` covers booth staff.
- **Check-in area radius:** `coalesce(e.checkin_radius_m, public.setting_num('checkin_radius_m', 300))`. Distance: `public.metres_between(lat1, lng1, lat2, lng2)`.

## Design

Match the app. Copy the look of the existing organizer screens (`lucky_draws_screen.dart`, `announcements_screen.dart`, `crew_screen.dart`) and member screens (`floorplan_screen.dart`, `lucky_draw_card.dart`).

- **Theme:** use the tokens in `lib/core/theme/` (`AppColors`, `AppFonts`, `AppRadius`, `AppIcons`). Shared widgets live in `lib/core/widgets/` (`PrimaryButton`, `SecondaryButton`, `EmptyState`…).
- **Icons:** only `AppIcons` (Phosphor). No Material `Icons.*` and no emoji characters. If you need a glyph that is missing, use the closest existing one.
- **Copy:** short, plain and friendly. The owner hates wordy text. Spell it "organizer", as the app does. Never write Dart single-quoted strings that contain an apostrophe; use double quotes.
- **No overflow at text scale 1.3:** no fixed heights on anything with text; `maxLines` plus ellipsis; Wrap or Flexible where needed.

## Code rules

- go_router routes use `pageBuilder: (_, s) => page(s, child)`. They're already registered.
- Release-mode AOT gotcha: never write a local closure that captures a nullable local and null-checks it inside a hot loop. Check before the loop.
- Use the `Supabase` client from `supabaseProvider` (see existing repositories) and Riverpod providers in an `application/` file. Follow the existing folder layout: `data/`, `domain/`, `application/`, `presentation/`.

## Finish

- Commit on your worktree branch with clear messages, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Final report (short):
  1. what you built, per plan item;
  2. the files you changed;
  3. your migration file and what it defines;
  4. calls you made and anything the lead must do;
  5. known gaps.
