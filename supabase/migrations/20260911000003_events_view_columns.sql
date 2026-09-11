-- events_with_counts was created before events.place_id / club_id existed, and a
-- "select e.*" view is expanded at creation time. Recreate it so the new columns
-- come through.
drop view if exists public.events_with_counts;
create view public.events_with_counts
with (security_invoker = true) as
select
  e.*,
  (select count(*) from public.event_attendees a where a.event_id = e.id)::int as attendee_count
from public.events e;
