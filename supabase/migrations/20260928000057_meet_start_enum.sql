-- 'meet_start': a meet you RSVP'd to has just started; open the app when you
-- arrive to check in. Sent by due_meet_start_pushes() (see 0058). Enum values
-- must be committed before they are used, so this lives in its own migration.
alter type public.notification_type add value if not exists 'meet_start';
