-- Spots = the car cafés from Malaysia_Car_Cafes_Reference.docx (plus partner
-- shops and whatever members earn by activity). The seven demo spots seeded
-- before launch still carried test check-ins, so they kept showing on the map.
-- They are archived, not deleted: their check-ins, meets and moments stay, they
-- just stop being spots. An admin can un-archive a place by deleting its row.
-- (A side table, not a places column: the view selects p.*, and a new column
-- there would shift the view's columns, which Postgres refuses.)

create table if not exists public.archived_places (
  place_id    uuid primary key references public.places (id) on delete cascade,
  archived_at timestamptz not null default now()
);
alter table public.archived_places enable row level security;
drop policy if exists "archived_places: read" on public.archived_places;
create policy "archived_places: read" on public.archived_places for select using (true);

insert into public.archived_places (place_id)
select id from public.places
 where vendor_id is null
   and not recommended
   and name in ('Bukit Ampang Lookout Point', 'Genting Sempah R&R', 'KLCC Park Carpark', 'Kopi Dua Darjat, TTDI',
                'Sepang International Circuit', 'Sunway Pyramid Open Carpark', 'Ulu Yam Dam Road')
on conflict do nothing;

-- Same columns as before (p.* keeps its original expansion); only is_spot and
-- is_top now skip archived places.
create or replace view public.places_with_counts
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
    not exists (select 1 from public.archived_places ar where ar.place_id = p.id)
    and (
    p.recommended
    or p.vendor_id is not null
    or p.cover_url is not null
    or exists (select 1 from public.place_checkins pc where pc.place_id = p.id)
    or exists (select 1 from public.posts po where po.place_id = p.id)
    or exists (select 1 from public.stories s where s.place_id = p.id)
    or exists (select 1 from public.place_suggestions sg where sg.place_id = p.id and sg.status = 'approved')
    )
  ) as is_spot,
  (not exists (select 1 from public.archived_places ar where ar.place_id = p.id) and case p.top_override
     when 'top' then true
     when 'never' then false
     else (p.recommended or a.checkins_90d >= 20 or a.meets_90d >= 3)
   end) as is_top,
  (select vd.logo_url from public.vendors vd where vd.id = p.vendor_id) as vendor_logo,
  (select vd.name from public.vendors vd where vd.id = p.vendor_id) as vendor_name
from public.places p
join act a on a.id = p.id;
