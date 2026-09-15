-- Who organises what, top spots by activity, member spot suggestions.
--
-- * TT sessions (event_type 'tt'): anyone, now or planned.
-- * Events (every other type): a car club (owner/admin), a partner business
--   (vendor owner) or a TT Spot admin. events.vendor_id is new.
-- * Top spot = admin says so (recommended / top_override) or activity in the
--   last 90 days crosses the bar; quiet spots drop back by themselves.
-- * place_suggestions: members propose a spot, admins approve into places.

-- ------------------------------------------------------------ organisers ---
alter table public.events add column if not exists vendor_id uuid references public.vendors (id) on delete set null;
create index if not exists events_vendor_idx on public.events (vendor_id);

drop policy if exists "events: organizer can insert" on public.events;
create policy "events: organizer can insert" on public.events for insert to authenticated
  with check (
    organizer_id = auth.uid()
    and (club_id is null or public.is_club_member(club_id))
    and (vendor_id is null or exists (select 1 from public.vendors v where v.id = vendor_id and v.owner_id = auth.uid() and v.active))
    and (
      event_type = 'tt'
      or public.is_admin()
      or (club_id is not null and exists (
            select 1 from public.club_members m where m.club_id = events.club_id and m.user_id = auth.uid() and m.role in ('owner', 'admin')))
      or vendor_id is not null
    )
  );

drop view if exists public.events_with_counts;
create view public.events_with_counts
with (security_invoker = true) as
select
  e.*,
  (select count(*) from public.event_attendees a where a.event_id = e.id)::int as attendee_count,
  (select count(*) from public.checkins c where c.event_id = e.id)::int as checkin_count,
  (select v.name from public.vendors v where v.id = e.vendor_id) as vendor_name,
  (select v.logo_url from public.vendors v where v.id = e.vendor_id) as vendor_logo_url
from public.events e;

-- ------------------------------------------------------------- top spots ---
alter table public.places add column if not exists top_override text check (top_override in ('top', 'never'));

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
  ) as is_spot,
  (case p.top_override
     when 'top' then true
     when 'never' then false
     else (p.recommended or a.checkins_90d >= 20 or a.meets_90d >= 3)
   end) as is_top
from public.places p
join act a on a.id = p.id;

-- Admin: force a spot up or down, or back to automatic.
create or replace function public.admin_set_top(p_place uuid, p_override text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_override is not null and p_override not in ('top', 'never') then raise exception 'top, never or null'; end if;
  update public.places set top_override = p_override, recommended = (p_override = 'top') where id = p_place;
end;
$$;

-- ------------------------------------------------------- spot suggestions ---
create table if not exists public.place_suggestions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  name          text not null check (char_length(name) between 2 and 80),
  address       text,
  lat           float8 not null,
  lng           float8 not null,
  google_place_id text,
  kind          text not null default 'other',
  note          text check (note is null or char_length(note) <= 500),
  photo_url     text,
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  place_id      uuid references public.places (id) on delete set null,
  reviewed_by   uuid references public.profiles (id),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);
alter table public.place_suggestions enable row level security;
drop policy if exists "suggestions: own" on public.place_suggestions;
create policy "suggestions: own" on public.place_suggestions for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "suggestions: insert own" on public.place_suggestions;
create policy "suggestions: insert own" on public.place_suggestions for insert to authenticated with check (user_id = auth.uid());
grant select, insert on public.place_suggestions to authenticated;

create or replace function public.admin_place_suggestions(p_limit int default 100)
returns table (id uuid, username text, name text, address text, lat float8, lng float8, kind text, note text, photo_url text,
               status text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select s.id, p.username::text, s.name, s.address, s.lat, s.lng, s.kind, s.note, s.photo_url, s.status, s.created_at
  from public.place_suggestions s join public.profiles p on p.id = s.user_id
  where public.is_admin()
  order by (s.status = 'pending') desc, s.created_at desc
  limit greatest(1, least(p_limit, 300));
$$;

-- Approve: creates (or reuses) the place, sets the cover from the photo, pays the member.
create or replace function public.admin_review_suggestion(p_id uuid, p_approve boolean, p_kind text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare s public.place_suggestions; v_place uuid;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select * into s from public.place_suggestions where id = p_id and status = 'pending';
  if not found then raise exception 'Already reviewed'; end if;
  if not p_approve then
    update public.place_suggestions set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
    return null;
  end if;
  select id into v_place from public.places p
  where abs(p.lat - s.lat) < 0.0015 and abs(p.lng - s.lng) < 0.0015 and lower(p.name) = lower(s.name) limit 1;
  if v_place is null then
    insert into public.places (name, kind, lat, lng, created_by, cover_url, description)
    values (s.name, coalesce(p_kind, s.kind, 'other'), s.lat, s.lng, s.user_id, s.photo_url, s.note)
    returning id into v_place;
  else
    update public.places set cover_url = coalesce(cover_url, s.photo_url), kind = coalesce(p_kind, kind) where id = v_place;
  end if;
  update public.place_suggestions set status = 'approved', place_id = v_place, reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  begin
    perform public.award_points(s.user_id, 30, 'spot_suggested', 'place', v_place::text, 'Spot added: ' || s.name);
  exception when others then null; -- points are a bonus, never a blocker
  end;
  return v_place;
end;
$$;

create or replace function public.admin_stats() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return json_build_object(
    'users', (select count(*) from public.profiles where username is not null),
    'users_7d', (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'meets_upcoming', (select count(*) from public.events where status = 'active' and starts_at > now()),
    'meets_live', (select count(*) from public.events where status = 'active' and now() between starts_at - interval '1 hour' and coalesce(ends_at, starts_at + interval '6 hours')),
    'checkins_today', (select count(*) from public.checkins where checked_in_at > date_trunc('day', now())),
    'posts_7d', (select count(*) from public.posts where created_at > now() - interval '7 days'),
    'pending_verifications', (select count(*) from public.spot_verifications where status in ('pending', 'review')),
    'pending_partners', (select count(*) from public.partner_applications where status = 'pending'),
    'pending_suggestions', (select count(*) from public.place_suggestions where status = 'pending'),
    'open_reports', (select count(*) from public.reports where resolved_at is null),
    'vendors', (select count(*) from public.vendors where active),
    'clubs', (select count(*) from public.clubs),
    'on_map_now', (select count(*) from public.user_locations where updated_at > now() - interval '20 minutes' and not ghost)
  );
end;
$$;

-- ------------------------------------------------------ real venues (seed) ---
-- Replace the made-up TTDI mamak with a real TTDI kopitiam and drop the
-- test-user leftover; add well-known Klang Valley gathering venues.
-- Coordinates are approximate: check each on the map before launch.
update public.places set name = 'Kopi Dua Darjat, TTDI', lat = 3.1405, lng = 101.6285, kind = 'mamak',
  description = 'Kopitiam on Persiaran Zaaba. Easy parking after 9 pm, regular TTDI teh tarik crowd.'
  where id = 'e6ddeccb-f291-40e3-bf98-8fe82984c614';
update public.events set place_id = null where place_id = '54dbe320-6510-4798-be08-984e11dda980';
delete from public.places where id = '54dbe320-6510-4798-be08-984e11dda980';

insert into public.places (name, kind, lat, lng, recommended, description, tags)
select v.name, v.kind, v.lat, v.lng, v.recommended, v.description, v.tags
from (values
  ('Pavilion Bukit Bintang', 'mall', 3.1490, 101.7132, true, 'Weekend-night supercar spotting at the main entrance. Look, do not rev.', array['night','supercars','city']),
  ('MAEPS Serdang', 'carpark', 2.9868, 101.7010, true, 'Huge open grounds. Home of Malaysia Autoshow and the big meets.', array['events','big meets','open space']),
  ('Putrajaya Boulevard', 'route', 2.9266, 101.6890, true, 'Persiaran Perdana. Wide, lit, quiet at night. Photo runs and convoy start point.', array['photos','night','convoy']),
  ('Desa ParkCity Waterfront', 'other', 3.1867, 101.6300, false, 'Lakeside cafés, family-friendly Sunday morning coffee runs.', array['coffee','sunday','family']),
  ('Kayu Nasi Kandar, SS2', 'mamak', 3.1178, 101.6231, false, '24-hour nasi kandar. The SS2 late-night TT default.', array['24h','mamak','late night']),
  ('Nasi Kandar Pelita, Jalan Ampang', 'mamak', 3.1608, 101.7172, false, 'KL city mamak with a big roadside car park. Post-Pavilion stop.', array['24h','mamak','city']),
  ('Steven''s Corner, OUG', 'mamak', 3.0740, 101.6720, false, 'OUG institution. Roti and teh tarik till late, easy street parking.', array['mamak','late night','south KL']),
  ('Kuala Kubu Bharu to Fraser''s Hill', 'route', 3.5636, 101.6560, true, 'The classic hill run. Meet at KKB town, drive up early before the traffic.', array['drive','hills','early morning'])
) as v(name, kind, lat, lng, recommended, description, tags)
where not exists (select 1 from public.places p where lower(p.name) = lower(v.name));
