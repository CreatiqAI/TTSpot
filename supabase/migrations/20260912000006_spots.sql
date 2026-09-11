-- =============================================================================
-- Spots: places become check-in destinations (打卡), not just meet venues.
--   cover / description / tags / recommended on places · place_checkins with a
--   300 m proof · ranked places_with_counts view · moments at a place count as
--   a check-in
-- =============================================================================

alter table public.places
  add column cover_url   text,
  add column description text check (description is null or char_length(description) <= 500),
  add column tags        text[] not null default '{}',
  add column recommended boolean not null default false;

-- anyone can fill in a blank cover / description (first come); tags & recommended stay curated
drop policy if exists "places: update own" on public.places;
create policy "places: update" on public.places for update to authenticated
  using (true) with check (true);

-- -----------------------------------------------------------------------------
-- place check-ins (one per person per place per day, Malaysia time)
-- -----------------------------------------------------------------------------
create table public.place_checkins (
  id            uuid primary key default gen_random_uuid(),
  place_id      uuid not null references public.places (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  day           date generated always as ((checked_in_at at time zone 'Asia/Kuala_Lumpur')::date) stored,
  lat           float8,
  lng           float8,
  story_id      uuid references public.stories (id) on delete set null,
  unique (place_id, user_id, day)
);
create index place_checkins_place_idx on public.place_checkins (place_id, checked_in_at desc);
create index place_checkins_user_idx on public.place_checkins (user_id, checked_in_at desc);

alter table public.place_checkins enable row level security;
create policy "place_checkins: read" on public.place_checkins for select to authenticated using (true);
create policy "place_checkins: delete own" on public.place_checkins for delete to authenticated using (user_id = auth.uid());
-- inserts go through checkin_place() / the moment trigger

create or replace function public.checkin_place(p_place uuid, p_lat float8, p_lng float8)
returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  pl public.places;
  d  float8;
  total int;
  today boolean;
begin
  if me is null then raise exception 'Not signed in'; end if;
  select * into pl from public.places where id = p_place;
  if not found then raise exception 'This spot no longer exists'; end if;
  if p_lat is null or p_lng is null then raise exception 'Turn on location to check in'; end if;
  d := public.metres_between(p_lat, p_lng, pl.lat, pl.lng);
  if d > 300 then
    raise exception 'You are % m away. Get closer to check in.', round(d)::int;
  end if;
  insert into public.place_checkins (place_id, user_id, lat, lng) values (p_place, me, p_lat, p_lng)
  on conflict (place_id, user_id, day) do nothing;
  today := found;
  select count(*)::int into total from public.place_checkins where place_id = p_place;
  perform public.award_badge(me, 'explorer') where (select count(distinct place_id) from public.place_checkins where user_id = me) >= 10;
  return json_build_object('new', today, 'total', total);
end;
$$;

insert into public.badges (id, name, description, emoji, sort) values
  ('explorer', 'Explorer', 'Checked in at 10 different spots.', '🧭', 25)
on conflict (id) do nothing;

-- a moment taken at a spot is a check-in too (when the photo has a location near it)
create or replace function public.on_story_checkin() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  pl public.places;
begin
  if new.place_id is null then return new; end if;
  select * into pl from public.places where id = new.place_id;
  if not found then return new; end if;
  if new.lat is not null and public.metres_between(new.lat, new.lng, pl.lat, pl.lng) <= 300 then
    insert into public.place_checkins (place_id, user_id, lat, lng, story_id)
    values (new.place_id, new.author_id, new.lat, new.lng, new.id)
    on conflict (place_id, user_id, day) do nothing;
  end if;
  -- first photo becomes the cover if the spot has none
  update public.places set cover_url = new.photo_url where id = new.place_id and cover_url is null;
  return new;
end; $$;
create trigger stories_after_insert_checkin after insert on public.stories
  for each row execute function public.on_story_checkin();

-- posts tagged to a spot lend it their first photo as a cover too
create or replace function public.on_post_place_cover() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.place_id is not null and cardinality(new.photo_urls) > 0 then
    update public.places set cover_url = new.photo_urls[1] where id = new.place_id and cover_url is null;
  end if;
  return new;
end; $$;
create trigger posts_after_insert_place_cover after insert on public.posts
  for each row execute function public.on_post_place_cover();

-- -----------------------------------------------------------------------------
-- ranked view
-- -----------------------------------------------------------------------------
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
  )::int as score
from public.places p;

-- regulars now count spot check-ins as well as meet check-ins
create or replace function public.place_regulars(p_place uuid, p_limit int default 8)
returns table (user_id uuid, username text, display_name text, avatar_url text, visits int)
language sql stable security definer set search_path = public as $$
  with visits as (
    select c.user_id, c.checked_in_at from public.checkins c join public.events e on e.id = c.event_id where e.place_id = p_place
    union all
    select pc.user_id, pc.checked_in_at from public.place_checkins pc where pc.place_id = p_place
  )
  select pr.id, pr.username, pr.display_name, pr.avatar_url, count(*)::int as visits
  from visits v join public.profiles pr on pr.id = v.user_id
  group by pr.id, pr.username, pr.display_name, pr.avatar_url
  order by visits desc, max(v.checked_in_at) desc
  limit p_limit;
$$;

-- who was here most recently (spot check-ins + meet check-ins)
create or replace function public.place_recent_visitors(p_place uuid, p_limit int default 12)
returns table (user_id uuid, username text, display_name text, avatar_url text, at timestamptz)
language sql stable security definer set search_path = public as $$
  with visits as (
    select c.user_id, c.checked_in_at from public.checkins c join public.events e on e.id = c.event_id where e.place_id = p_place
    union all
    select pc.user_id, pc.checked_in_at from public.place_checkins pc where pc.place_id = p_place
  )
  select distinct on (pr.id) pr.id, pr.username, pr.display_name, pr.avatar_url, v.checked_in_at
  from visits v join public.profiles pr on pr.id = v.user_id
  order by pr.id, v.checked_in_at desc
  limit p_limit;
$$;

-- did I check in here today?
create or replace function public.my_place_checkin_today(p_place uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.place_checkins
    where place_id = p_place and user_id = auth.uid()
      and day = (now() at time zone 'Asia/Kuala_Lumpur')::date
  );
$$;
