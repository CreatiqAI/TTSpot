-- Enum values must land before the functions that use them (separate transaction).
alter type public.notification_type add value if not exists 'club_event';     -- official club scheduled a meet (members)
alter type public.notification_type add value if not exists 'partner_event';  -- a partner is hosting an event (everyone)
alter type public.notification_type add value if not exists 'garage';         -- a clubmate arrived at the club garage
alter type public.notification_type add value if not exists 'club_official';  -- official tier requested / approved / ended
