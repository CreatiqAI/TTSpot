-- Organizer tools (0066, 0067) send two new kinds of notification:
--   'announcement' : a host / co-host message to people linked to a meet
--                    (body = "<title>\n<text>"), also "you're on the crew";
--   'lucky_draw'   : draw reminders, "starting now", "you won", results,
--                    standby promotions and prize hand-overs (body is the
--                    sentence to show).
-- Enum values must be committed before they are used, so they live here.
alter type public.notification_type add value if not exists 'announcement';
alter type public.notification_type add value if not exists 'lucky_draw';
