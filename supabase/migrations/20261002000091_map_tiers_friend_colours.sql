-- Map v3: image pins with tiers, and twelve friend colours.
--
-- 1. events_with_counts gains what the map needs to size an event's pin and
--    pick its image without another round trip:
--      club_avatar_url    the hosting club's logo (pin image when the event has no cover)
--      host_is_organizer  the host is an approved organizer (profiles.is_organizer)
--    Columns are appended (CREATE OR REPLACE VIEW keeps the old ones in place).
--    The view stays security_invoker, so events, clubs and profiles RLS apply
--    to the reader exactly as before: no visibility rule changes.
--
-- 2. friend_tags.color accepts twelve colours (the seven old keys keep working).

create or replace view public.events_with_counts
with (security_invoker = true) as
select
  e.id,
  e.organizer_id,
  e.title,
  e.description,
  e.event_type,
  e.cover_url,
  e.starts_at,
  e.venue_name,
  e.lat,
  e.lng,
  e.max_attendees,
  e.status,
  e.created_at,
  e.place_id,
  e.club_id,
  e.is_instant,
  e.ends_at,
  e.visibility,
  e.address,
  e.vendor_id,
  (select count(*) from public.event_attendees a where a.event_id = e.id)::integer as attendee_count,
  (select count(*) from public.checkins c where c.event_id = e.id)::integer as checkin_count,
  (select v.name from public.vendors v where v.id = e.vendor_id) as vendor_name,
  (select v.logo_url from public.vendors v where v.id = e.vendor_id) as vendor_logo_url,
  (select c.name from public.clubs c where c.id = e.club_id) as club_name,
  (select c.tier from public.clubs c where c.id = e.club_id) as club_tier,
  (select c.avatar_url from public.clubs c where c.id = e.club_id) as club_avatar_url,
  coalesce((select p.is_organizer from public.profiles p where p.id = e.organizer_id), false) as host_is_organizer
from public.events e;

alter table public.friend_tags drop constraint if exists friend_tags_color_check;
alter table public.friend_tags add constraint friend_tags_color_check check (color in (
  'red', 'orange', 'yellow', 'lime', 'green', 'teal',
  'sky', 'blue', 'indigo', 'purple', 'pink', 'brown'
));
