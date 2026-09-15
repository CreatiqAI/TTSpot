-- A place approved from a member suggestion is a spot even before it has a
-- photo or a check-in.
drop view if exists public.places_with_counts;
create view public.places_with_counts
with (security_invoker = true) as
with act as (
  select p.id,
         (select count(*) from public.place_checkins pc where pc.place_id = p.id and pc.checked_in_at > now() - interval '90 days')::int as checkins_90d,
         (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.event_type <> 'tt'
                 and e.starts_at between now() - interval '90 days' and now())::int as meets_90d
  from public.places p
)
select
  p.*,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now())::int  as past_meets,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at >= now())::int as upcoming_meets,
  (select max(e.starts_at) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now()) as last_meet_at,
  (select count(*) from public.checkins c join public.events e on e.id = c.event_id where e.place_id = p.id)::int      as checkins_total,
  (select count(*) from public.place_checkins pc where pc.place_id = p.id)::int                                          as spot_checkins,
  (select count(*) from public.posts po where po.place_id = p.id)::int                                                  as post_count,
  (select count(*) from public.stories s where s.place_id = p.id)::int                                                  as moment_count,
  a.checkins_90d,
  a.meets_90d,
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
    or exists (select 1 from public.place_suggestions sg where sg.place_id = p.id and sg.status = 'approved')
  ) as is_spot,
  (case p.top_override
     when 'top' then true
     when 'never' then false
     else (p.recommended or a.checkins_90d >= 20 or a.meets_90d >= 3)
   end) as is_top
from public.places p
join act a on a.id = p.id;
