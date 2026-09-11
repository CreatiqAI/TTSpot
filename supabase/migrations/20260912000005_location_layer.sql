-- =============================================================================
-- TT Spot location layer
--   friendships (mutual, Snapchat-style) · live pins while the app is open ·
--   check-ins that turn a meet into a record · moments pinned to meets/places ·
--   "TT now" instant meets · place history · device tokens for push
-- =============================================================================

-- -----------------------------------------------------------------------------
-- friendships
-- -----------------------------------------------------------------------------
create table public.friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references public.profiles (id) on delete cascade,
  addressee_id  uuid not null references public.profiles (id) on delete cascade,
  status        text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at    timestamptz not null default now(),
  accepted_at   timestamptz,
  constraint no_self_friend check (requester_id <> addressee_id)
);
create unique index friendships_pair_idx
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_addressee_idx on public.friendships (addressee_id, status);
create index friendships_requester_idx on public.friendships (requester_id, status);

create or replace function public.is_friend(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = p_a and f.addressee_id = p_b)
        or (f.requester_id = p_b and f.addressee_id = p_a))
  );
$$;

create or replace function public.friend_ids(p_user uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select case when f.requester_id = p_user then f.addressee_id else f.requester_id end
  from public.friendships f
  where f.status = 'accepted' and (f.requester_id = p_user or f.addressee_id = p_user);
$$;

create or replace function public.friend_count(p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.friend_ids(p_user);
$$;

-- 'none' | 'pending_out' | 'pending_in' | 'friends'
create or replace function public.friendship_status(p_user uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  f  public.friendships;
begin
  if me is null or p_user = me then return 'none'; end if;
  select * into f from public.friendships
  where least(requester_id, addressee_id) = least(me, p_user)
    and greatest(requester_id, addressee_id) = greatest(me, p_user);
  if not found then return 'none'; end if;
  if f.status = 'accepted' then return 'friends'; end if;
  return case when f.requester_id = me then 'pending_out' else 'pending_in' end;
end;
$$;

-- Send a request; auto-accepts when the other side already asked.
create or replace function public.send_friend_request(p_user uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  f  public.friendships;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_user = me then raise exception 'You cannot add yourself'; end if;
  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = me and b.blocked_id = p_user) or (b.blocker_id = p_user and b.blocked_id = me)
  ) then raise exception 'You cannot add this user'; end if;

  select * into f from public.friendships
  where least(requester_id, addressee_id) = least(me, p_user)
    and greatest(requester_id, addressee_id) = greatest(me, p_user);
  if found then
    if f.status = 'accepted' then return 'friends'; end if;
    if f.requester_id = me then return 'pending_out'; end if;
    update public.friendships set status = 'accepted', accepted_at = now() where id = f.id;
    return 'friends';
  end if;
  insert into public.friendships (requester_id, addressee_id) values (me, p_user);
  return 'pending_out';
end;
$$;

create or replace function public.respond_friend_request(p_user uuid, p_accept boolean) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if p_accept then
    update public.friendships set status = 'accepted', accepted_at = now()
    where requester_id = p_user and addressee_id = me and status = 'pending';
    return 'friends';
  end if;
  delete from public.friendships where requester_id = p_user and addressee_id = me and status = 'pending';
  return 'none';
end;
$$;

create or replace function public.remove_friend(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.friendships
  where least(requester_id, addressee_id) = least(auth.uid(), p_user)
    and greatest(requester_id, addressee_id) = greatest(auth.uid(), p_user);
end;
$$;

create or replace function public.on_friendship_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' then
    perform public.notify(new.addressee_id, new.requester_id, 'friend_request');
  end if;
  return new;
end; $$;
create trigger friendships_after_insert after insert on public.friendships
  for each row execute function public.on_friendship_insert();

create or replace function public.on_friendship_accept() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'pending' and new.status = 'accepted' then
    perform public.notify(new.requester_id, new.addressee_id, 'friend_accepted');
    -- both sides now see each other's friend-request notification as handled
    delete from public.notifications
    where type = 'friend_request' and user_id = new.addressee_id and actor_id = new.requester_id;
  end if;
  return new;
end; $$;
create trigger friendships_after_accept after update on public.friendships
  for each row execute function public.on_friendship_accept();

alter table public.friendships enable row level security;
create policy "friendships: read own" on public.friendships for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());
-- writes go through the RPCs above (security definer); no direct insert/update policies.

-- -----------------------------------------------------------------------------
-- events: instant meets + explicit end
-- -----------------------------------------------------------------------------
alter table public.events
  add column is_instant boolean not null default false,
  add column ends_at    timestamptz;

-- when a meet counts as "live": 1 h before start until ends_at (or start + 6 h)
create or replace function public.event_live_window(p_event uuid)
returns table (opens_at timestamptz, closes_at timestamptz)
language sql stable security definer set search_path = public as $$
  select e.starts_at - interval '1 hour', coalesce(e.ends_at, e.starts_at + interval '6 hours')
  from public.events e where e.id = p_event;
$$;

-- -----------------------------------------------------------------------------
-- check-ins: "went", proven by location
-- -----------------------------------------------------------------------------
create table public.checkins (
  event_id       uuid not null references public.events (id) on delete cascade,
  user_id        uuid not null references public.profiles (id) on delete cascade,
  checked_in_at  timestamptz not null default now(),
  lat            float8,
  lng            float8,
  source         text not null default 'manual' check (source in ('manual', 'auto', 'organizer')),
  primary key (event_id, user_id)
);
create index checkins_user_idx on public.checkins (user_id, checked_in_at desc);

-- ~ metres between two points (good enough for a few km)
create or replace function public.metres_between(lat1 float8, lng1 float8, lat2 float8, lng2 float8) returns float8
language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

create or replace function public.on_checkin_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e public.events;
  w record;
begin
  select * into e from public.events where id = new.event_id;
  if e.status <> 'active' then raise exception 'This meet was cancelled'; end if;
  select * into w from public.event_live_window(new.event_id);
  if now() < w.opens_at or now() > w.closes_at then
    raise exception 'Check-in only works around the meet time';
  end if;
  if new.source <> 'organizer' then
    if new.lat is null or new.lng is null then raise exception 'Turn on location to check in'; end if;
    if public.metres_between(new.lat, new.lng, e.lat, e.lng) > 500 then
      raise exception 'You are too far from the meet to check in';
    end if;
  end if;
  return new;
end; $$;
create trigger checkins_before_insert before insert on public.checkins
  for each row execute function public.on_checkin_insert();

create or replace function public.on_checkin_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- checking in implies going; ignore "full" errors, they still went
  begin
    insert into public.event_attendees (event_id, user_id) values (new.event_id, new.user_id)
    on conflict do nothing;
  exception when others then null;
  end;
  perform public.award_badge(new.user_id, 'first_meet');
  if (select count(*) from public.checkins where user_id = new.user_id) >= 10 then
    perform public.award_badge(new.user_id, 'regular');
  end if;
  return new;
end; $$;
create trigger checkins_after_insert after insert on public.checkins
  for each row execute function public.on_checkin_after();

alter table public.checkins enable row level security;
create policy "checkins: read" on public.checkins for select to authenticated using (true);
create policy "checkins: insert own" on public.checkins for insert to authenticated with check (user_id = auth.uid());
create policy "checkins: delete own" on public.checkins for delete to authenticated using (user_id = auth.uid());

-- events view now carries check-in counts too
drop view if exists public.events_with_counts;
create view public.events_with_counts
with (security_invoker = true) as
select
  e.*,
  (select count(*) from public.event_attendees a where a.event_id = e.id)::int as attendee_count,
  (select count(*) from public.checkins c where c.event_id = e.id)::int as checkin_count
from public.events e;

-- -----------------------------------------------------------------------------
-- live pins: where friends are, updated while the app is open
-- -----------------------------------------------------------------------------
create table public.user_locations (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  lat         float8 not null check (lat between -90 and 90),
  lng         float8 not null check (lng between -180 and 180),
  heading     float8,
  accuracy    float8,
  ghost       boolean not null default false,
  place_id    uuid references public.places (id) on delete set null,
  event_id    uuid references public.events (id) on delete set null,
  updated_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '24 hours'
);
alter table public.user_locations replica identity full;

alter table public.user_locations enable row level security;
create policy "locations: read self or friends" on public.user_locations for select to authenticated
  using (user_id = auth.uid() or (not ghost and expires_at > now() and public.is_friend(auth.uid(), user_id)));
create policy "locations: insert own" on public.user_locations for insert to authenticated with check (user_id = auth.uid());
create policy "locations: update own" on public.user_locations for update to authenticated using (user_id = auth.uid());
create policy "locations: delete own" on public.user_locations for delete to authenticated using (user_id = auth.uid());

alter publication supabase_realtime add table public.user_locations;

-- Called every few seconds while the map is open. Snaps to the nearest place,
-- auto-checks-in to a meet the user RSVP'd to, and reports a nearby live meet
-- the app can offer a check-in for.
create or replace function public.update_my_location(p_lat float8, p_lng float8, p_heading float8 default null, p_accuracy float8 default null)
returns json
language plpgsql security definer set search_path = public as $$
declare
  me        uuid := auth.uid();
  v_place   public.places;
  v_ev_id   uuid;
  v_ev_title text;
  v_ev_org  uuid;
  v_rsvpd   boolean;
  v_already boolean;
  v_checked uuid;
begin
  if me is null then raise exception 'Not signed in'; end if;

  select * into v_place from public.places p
  where abs(p.lat - p_lat) < 0.01 and abs(p.lng - p_lng) < 0.01
  order by public.metres_between(p_lat, p_lng, p.lat, p.lng)
  limit 1;
  if found and public.metres_between(p_lat, p_lng, v_place.lat, v_place.lng) > 150 then
    v_place := null;
  end if;

  -- nearest live meet within 500 m
  select e.id, e.title, e.organizer_id,
         exists (select 1 from public.event_attendees a where a.event_id = e.id and a.user_id = me),
         exists (select 1 from public.checkins c where c.event_id = e.id and c.user_id = me)
  into v_ev_id, v_ev_title, v_ev_org, v_rsvpd, v_already
  from public.events e
  where e.status = 'active'
    and now() between e.starts_at - interval '1 hour' and coalesce(e.ends_at, e.starts_at + interval '6 hours')
    and abs(e.lat - p_lat) < 0.01 and abs(e.lng - p_lng) < 0.01
    and public.metres_between(p_lat, p_lng, e.lat, e.lng) <= 500
  order by public.metres_between(p_lat, p_lng, e.lat, e.lng)
  limit 1;

  if v_ev_id is not null then
    if v_already then
      v_checked := v_ev_id;
    elsif v_rsvpd or v_ev_org = me then
      begin
        insert into public.checkins (event_id, user_id, lat, lng, source) values (v_ev_id, me, p_lat, p_lng, 'auto');
        v_checked := v_ev_id;
      exception when others then v_checked := null;
      end;
    end if;
  end if;

  insert into public.user_locations (user_id, lat, lng, heading, accuracy, place_id, event_id, updated_at, expires_at)
  values (me, p_lat, p_lng, p_heading, p_accuracy, v_place.id, v_checked, now(), now() + interval '24 hours')
  on conflict (user_id) do update
    set lat = excluded.lat, lng = excluded.lng, heading = excluded.heading, accuracy = excluded.accuracy,
        place_id = excluded.place_id, event_id = excluded.event_id,
        updated_at = now(), expires_at = now() + interval '24 hours';

  return json_build_object(
    'place_id', v_place.id,
    'place_name', v_place.name,
    'checked_in_event_id', v_checked,
    'nearby_event_id', case when v_ev_id is not null and v_checked is null then v_ev_id end,
    'nearby_event_title', case when v_ev_id is not null and v_checked is null then v_ev_title end
  );
end;
$$;

create or replace function public.set_ghost(p_ghost boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.user_locations (user_id, lat, lng, ghost, expires_at)
  values (auth.uid(), 3.1390, 101.6869, p_ghost, now())   -- placeholder row; expired so nobody sees it
  on conflict (user_id) do update set ghost = excluded.ghost;
end;
$$;

-- -----------------------------------------------------------------------------
-- moments: stories pinned to a meet or place. Live on the map for 24 h,
-- kept forever in the meet's / place's album.
-- -----------------------------------------------------------------------------
alter table public.stories
  add column lat       float8,
  add column lng       float8,
  add column event_id  uuid references public.events (id) on delete set null,
  add column place_id  uuid references public.places (id) on delete set null;
create index stories_event_idx on public.stories (event_id) where event_id is not null;
create index stories_place_idx on public.stories (place_id) where place_id is not null;

drop policy "stories: read live" on public.stories;
create policy "stories: read" on public.stories for select to authenticated
  using (expires_at > now() or event_id is not null or place_id is not null);

-- a moment tagged to a meet inherits the meet's place
create or replace function public.on_story_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.event_id is not null and new.place_id is null then
    select place_id into new.place_id from public.events where id = new.event_id;
  end if;
  if new.lat is null and new.event_id is not null then
    select lat, lng into new.lat, new.lng from public.events where id = new.event_id;
  end if;
  if new.lat is null and new.place_id is not null then
    select lat, lng into new.lat, new.lng from public.places where id = new.place_id;
  end if;
  return new;
end; $$;
create trigger stories_before_insert before insert on public.stories
  for each row execute function public.on_story_insert();

-- expiry job: only untagged moments are ever deleted
select cron.unschedule('ttspot-expire-stories');
select cron.schedule('ttspot-expire-stories', '15 * * * *',
  $$delete from public.stories where expires_at < now() - interval '1 day' and event_id is null and place_id is null$$);

-- -----------------------------------------------------------------------------
-- TT now: an instant meet at your spot, friends get pinged
-- -----------------------------------------------------------------------------
create or replace function public.tt_now(p_lat float8, p_lng float8, p_venue text default null, p_title text default null, p_hours int default 3)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me       uuid := auth.uid();
  v_place  public.places;
  v_venue  text;
  v_title  text;
  v_id     uuid;
  f        uuid;
begin
  if me is null then raise exception 'Not signed in'; end if;

  select * into v_place from public.places p
  where abs(p.lat - p_lat) < 0.01 and abs(p.lng - p_lng) < 0.01
  order by public.metres_between(p_lat, p_lng, p.lat, p.lng)
  limit 1;
  if found and public.metres_between(p_lat, p_lng, v_place.lat, v_place.lng) > 200 then
    v_place := null;
  end if;

  v_venue := coalesce(nullif(trim(p_venue), ''), v_place.name, 'My spot');
  v_title := left(coalesce(nullif(trim(p_title), ''), 'TT now @ ' || v_venue), 80);
  if char_length(v_title) < 3 then v_title := 'TT now'; end if;

  insert into public.events (organizer_id, title, event_type, starts_at, ends_at, venue_name, lat, lng, is_instant, place_id)
  values (me, v_title, 'tt', now(), now() + make_interval(hours => greatest(1, least(p_hours, 8))), left(v_venue, 80), p_lat, p_lng, true, v_place.id)
  returning id into v_id;

  insert into public.event_attendees (event_id, user_id) values (v_id, me) on conflict do nothing;
  insert into public.checkins (event_id, user_id, lat, lng, source) values (v_id, me, p_lat, p_lng, 'organizer') on conflict do nothing;

  for f in select * from public.friend_ids(me) loop
    perform public.notify(f, me, 'tt_now', p_event => v_id, p_body => v_venue);
  end loop;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- place history
-- -----------------------------------------------------------------------------
create view public.places_with_counts
with (security_invoker = true) as
select
  p.*,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now())::int  as past_meets,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at >= now())::int as upcoming_meets,
  (select max(e.starts_at) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now()) as last_meet_at,
  (select count(*) from public.checkins c join public.events e on e.id = c.event_id where e.place_id = p.id)::int      as checkins_total
from public.places p;

create or replace function public.place_regulars(p_place uuid, p_limit int default 8)
returns table (user_id uuid, username text, display_name text, avatar_url text, visits int)
language sql stable security definer set search_path = public as $$
  select pr.id, pr.username, pr.display_name, pr.avatar_url, count(*)::int as visits
  from public.checkins c
  join public.events e on e.id = c.event_id
  join public.profiles pr on pr.id = c.user_id
  where e.place_id = p_place
  group by pr.id, pr.username, pr.display_name, pr.avatar_url
  order by visits desc, max(c.checked_in_at) desc
  limit p_limit;
$$;

-- which weekdays (0 = Sunday … 6 = Saturday, Malaysia time) meets happen here
create or replace function public.place_busy_days(p_place uuid)
returns table (dow int, meets int)
language sql stable security definer set search_path = public as $$
  select extract(dow from e.starts_at at time zone 'Asia/Kuala_Lumpur')::int as dow, count(*)::int as meets
  from public.events e
  where e.place_id = p_place and e.status = 'active'
  group by 1 order by meets desc, dow;
$$;

-- what happened at a meet: who went, which cars came, how many moments
create or replace function public.event_recap(p_event uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'went', (select count(*) from public.checkins c where c.event_id = p_event),
    'going', (select count(*) from public.event_attendees a where a.event_id = p_event),
    'moments', (select count(*) from public.stories s where s.event_id = p_event),
    'cars', coalesce((
      select json_agg(json_build_object('id', cr.id, 'make', cr.make, 'model', cr.model, 'photo', cr.photo_urls[1], 'owner', pr.username))
      from public.checkins c
      join public.cars cr on cr.owner_id = c.user_id
      join public.profiles pr on pr.id = c.user_id
      where c.event_id = p_event
    ), '[]'::json)
  );
$$;

-- meets my friends are going to (upcoming), with which friends
create or replace function public.friends_upcoming_events()
returns table (event_id uuid, friend_ids uuid[])
language sql stable security definer set search_path = public as $$
  select a.event_id, array_agg(a.user_id)
  from public.event_attendees a
  join public.events e on e.id = a.event_id
  where a.user_id in (select public.friend_ids(auth.uid()))
    and e.status = 'active' and e.starts_at >= now() - interval '1 hour'
  group by a.event_id;
$$;

-- -----------------------------------------------------------------------------
-- push (phase 2 wiring)
-- -----------------------------------------------------------------------------
create table public.device_tokens (
  token       text primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  platform    text not null default 'android',
  updated_at  timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
create policy "device_tokens: own" on public.device_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
