-- Spots layer shows community spots only: recommended, or with a cover, spot
-- check-ins, posts or moments. Places that merely hosted a meet stay as venue
-- records for the meet page but no longer clutter the map.

drop view if exists public.places_with_counts;
create view public.places_with_counts
with (security_invoker = true) as
select
  p.*,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now())::int  as past_meets,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at >= now())::int as upcoming_meets,
  (select max(e.starts_at) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now()) as last_meet_at,
  (select count(*) from public.checkins c join public.events e on e.id = c.event_id where e.place_id = p.id)::int      as checkins_total,
  (select count(*) from public.place_checkins pc where pc.place_id = p.id)::int                                          as spot_checkins,
  (select count(*) from public.posts po where po.place_id = p.id)::int                                                  as post_count,
  (select count(*) from public.stories s where s.place_id = p.id)::int                                                  as moment_count,
  (
    (case when p.recommended then 100 else 0 end)
    + 3 * (select count(*) from public.place_checkins pc where pc.place_id = p.id)
    + 5 * (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now())
    + 2 * (select count(*) from public.posts po where po.place_id = p.id)
    + 1 * (select count(*) from public.stories s where s.place_id = p.id)
  )::int as score,
  (
    p.recommended
    or p.cover_url is not null
    or exists (select 1 from public.place_checkins pc where pc.place_id = p.id)
    or exists (select 1 from public.posts po where po.place_id = p.id)
    or exists (select 1 from public.stories s where s.place_id = p.id)
  ) as is_spot
from public.places p;

-- TT now never creates a place record ("My spot", "Pinned spot"…).
create or replace function public.on_event_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.award_badge(new.organizer_id, 'organiser');
  if new.event_type = 'convoy' then perform public.award_badge(new.organizer_id, 'convoy_captain'); end if;
  if new.place_id is null and not coalesce(new.is_instant, false) then
    select id into new.place_id from public.places
    where lower(name) = lower(new.venue_name)
      and abs(lat - new.lat) < 0.0015 and abs(lng - new.lng) < 0.0015
    limit 1;
    if new.place_id is null then
      insert into public.places (name, kind, lat, lng, created_by)
      values (new.venue_name, case when new.event_type = 'trackday' then 'circuit' when new.event_type = 'tt' then 'mamak' else 'carpark' end, new.lat, new.lng, new.organizer_id)
      returning id into new.place_id;
    end if;
  end if;
  return new;
end; $$;

-- Remove the ad-hoc ones already created by TT now.
update public.events set place_id = null
where place_id in (select id from public.places where name in ('My spot', 'Pinned spot') and cover_url is null and not recommended);
delete from public.places
where name in ('My spot', 'Pinned spot') and cover_url is null and not recommended
  and not exists (select 1 from public.place_checkins pc where pc.place_id = places.id);
