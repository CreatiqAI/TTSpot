-- =============================================================================
-- Which car are you bringing?
--
-- A member with more than one car picks the car they bring to a TT now, to a
-- meet they join (RSVP) and to the meet they check in at. The choice lives on
-- event_attendees.car_id and checkins.car_id. Everything that lists cars for a
-- meet (host door list, going list, recap, turnout report, friends' map pins)
-- now shows the car chosen for that outing, falling back to the default car.
--
-- Backwards compatible: the shipped app (0.3.36) still calls tt_now and
-- checkin_by_qr without p_car and still inserts RSVPs / manual check-ins
-- without car_id. Those rows get a car from the triggers below (check-in: the
-- RSVP car, else the default; RSVP: the check-in car, else the default).
-- =============================================================================

-- ------------------------------------------------------------------ schema ---
alter table public.event_attendees add column if not exists car_id uuid references public.cars (id) on delete set null;
alter table public.checkins        add column if not exists car_id uuid references public.cars (id) on delete set null;
create index if not exists event_attendees_car_idx on public.event_attendees (car_id) where car_id is not null;
create index if not exists checkins_car_idx        on public.checkins (car_id) where car_id is not null;

-- ----------------------------------------------------------------- helpers ---

-- p_car when p_user owns it (else raises), or p_user's default car when p_car
-- is null (null when they have no car at all).
create or replace function public.resolve_outing_car(p_user uuid, p_car uuid) returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  if p_car is not null then
    if not exists (select 1 from public.cars where id = p_car and owner_id = p_user) then
      raise exception 'That car is not in your garage';
    end if;
    return p_car;
  end if;
  return (select id from public.cars where owner_id = p_user order by is_default desc, created_at asc limit 1);
end;
$$;

-- The car p_user brought to p_event: the check-in's car, else the RSVP's car,
-- else their default car. p_event may be null (then: the default car).
create or replace function public.outing_car(p_event uuid, p_user uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select c.car_id from public.checkins c where c.event_id = p_event and c.user_id = p_user),
    (select a.car_id from public.event_attendees a where a.event_id = p_event and a.user_id = p_user),
    (select k.id from public.cars k where k.owner_id = p_user order by k.is_default desc, k.created_at asc limit 1)
  );
$$;

-- --------------------------------------------------------------- triggers ---
-- Every insert path (RPCs, the app's plain inserts, auto check-in in
-- update_my_location, the "checking in implies going" attendee insert) gets a
-- validated car without having to know about it.

create or replace function public.on_attendee_car() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.car_id is not distinct from old.car_id then return new; end if;
  if new.car_id is null and tg_op = 'INSERT' then
    new.car_id := coalesce(
      (select c.car_id from public.checkins c where c.event_id = new.event_id and c.user_id = new.user_id),
      public.resolve_outing_car(new.user_id, null));
  elsif new.car_id is not null then
    perform public.resolve_outing_car(new.user_id, new.car_id);
  end if;
  return new;
end;
$$;
drop trigger if exists event_attendees_car on public.event_attendees;
create trigger event_attendees_car before insert or update of car_id on public.event_attendees
  for each row execute function public.on_attendee_car();

-- Automatic (GPS) check-in and old clients: the RSVP car, else the default.
create or replace function public.on_checkin_car() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.car_id is not distinct from old.car_id then return new; end if;
  if new.car_id is null and tg_op = 'INSERT' then
    new.car_id := coalesce(
      (select a.car_id from public.event_attendees a where a.event_id = new.event_id and a.user_id = new.user_id),
      public.resolve_outing_car(new.user_id, null));
  elsif new.car_id is not null then
    perform public.resolve_outing_car(new.user_id, new.car_id);
  end if;
  return new;
end;
$$;
drop trigger if exists checkins_car on public.checkins;
create trigger checkins_car before insert or update of car_id on public.checkins
  for each row execute function public.on_checkin_car();

-- ------------------------------------------------------------ change car ---
-- RSVPs and manual check-ins are plain table inserts from the app (RLS:
-- user_id = auth.uid(); the triggers above validate car_id). Changing the car
-- afterwards goes through here, since neither table has an update policy.
-- Updates my RSVP and my check-in for the meet; p_car null = my default car.
create or replace function public.set_event_car(p_event uuid, p_car uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v  uuid;
  n  int;
  m  int;
begin
  if me is null then raise exception 'Sign in first'; end if;
  v := public.resolve_outing_car(me, p_car);
  update public.event_attendees set car_id = v where event_id = p_event and user_id = me;
  get diagnostics n = row_count;
  update public.checkins set car_id = v where event_id = p_event and user_id = me;
  get diagnostics m = row_count;
  if n + m = 0 then raise exception 'Join the meet first'; end if;
  return v;
end;
$$;

-- The car each member is bringing to (or brought to) a meet: everyone who
-- RSVP'd or checked in and has a car. Feeds the going list, the check-in card
-- and "Bringing: … · Change" on the meet page.
create or replace function public.event_cars(p_event uuid)
returns table (user_id uuid, car_id uuid, car_title text, car_cover text)
language sql stable security definer set search_path = public as $$
  select u.user_id, k.id,
         nullif(trim(concat_ws(' ', k.make, k.model)), ''),
         coalesce(k.portrait_url, k.photo_urls[1])
    from (select a.user_id from public.event_attendees a where a.event_id = p_event
          union
          select c.user_id from public.checkins c where c.event_id = p_event) u
    join public.cars k on k.id = public.outing_car(p_event, u.user_id);
$$;

-- ----------------------------------------------------------------- tt_now ---
-- Gains p_car: the host's car for the session (null = default car).
-- The old 7-argument overload is dropped first: with both present, a call that
-- leaves p_car out (the shipped app) matches both and PostgREST refuses it as
-- ambiguous. The new one accepts every old call through the default.
drop function if exists public.tt_now(float8, float8, text, text, int, uuid[], text);
create or replace function public.tt_now(p_lat float8, p_lng float8, p_venue text default null, p_title text default null,
                                         p_minutes int default 60, p_invitees uuid[] default null, p_address text default null,
                                         p_car uuid default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me       uuid := auth.uid();
  v_place  public.places;
  v_venue  text;
  v_title  text;
  v_id     uuid;
  v_car    uuid;
  f        uuid;
  v_mins   int := greatest(15, least(coalesce(p_minutes, 60), 480));
begin
  if me is null then raise exception 'Not signed in'; end if;
  v_car := public.resolve_outing_car(me, p_car);

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

  insert into public.events (organizer_id, title, event_type, starts_at, ends_at, venue_name, lat, lng, is_instant, place_id, address, visibility)
  values (me, v_title, 'tt', now(), now() + make_interval(mins => v_mins), left(v_venue, 80), p_lat, p_lng, true, v_place.id, nullif(trim(p_address), ''), 'friends')
  returning id into v_id;

  insert into public.event_attendees (event_id, user_id, car_id) values (v_id, me, v_car) on conflict do nothing;
  insert into public.checkins (event_id, user_id, lat, lng, source, car_id) values (v_id, me, p_lat, p_lng, 'organizer', v_car) on conflict do nothing;

  if p_invitees is null then
    for f in select * from public.friend_ids(me) loop
      perform public.notify(f, me, 'tt_now', p_event => v_id, p_body => v_venue);
    end loop;
  else
    foreach f in array p_invitees loop
      if public.is_friend(me, f) then
        -- invitees get their default car; they can change it on the meet page
        insert into public.event_attendees (event_id, user_id) values (v_id, f) on conflict do nothing;
        perform public.notify(f, me, 'tt_now', p_event => v_id, p_body => v_venue);
      end if;
    end loop;
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------- checkin_by_qr ---
-- Gains p_car (null = the RSVP car, else the default). Old 4-argument overload
-- dropped for the same ambiguity reason as tt_now. A repeat scan with a car
-- updates the car on the existing check-in.
drop function if exists public.checkin_by_qr(uuid, text, float8, float8);
create or replace function public.checkin_by_qr(p_event uuid, p_code text, p_lat float8 default null, p_lng float8 default null,
                                                p_car uuid default null) returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  w bigint := floor(extract(epoch from now()) / 30)::bigint;
  already boolean;
  e public.events%rowtype;
  v_dist float8;
  v_radius float8 := public.setting_num('checkin_radius_m', 300);
  v_car uuid;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_car is not null then v_car := public.resolve_outing_car(me, p_car); end if;
  if p_code is null or (p_code <> public.event_qr_code_at(p_event, w) and p_code <> public.event_qr_code_at(p_event, w - 1)) then
    raise exception 'That code has expired. Scan the organiser''s screen again.';
  end if;
  if p_lat is null or p_lng is null then
    raise exception 'Turn on location so we can confirm you are at the meet.';
  end if;
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  v_dist := public.metres_between(p_lat, p_lng, e.lat, e.lng);
  if v_dist > v_radius then
    raise exception 'You are % m from the meet. Get within % m to check in.', round(v_dist)::int, v_radius::int;
  end if;
  select exists (select 1 from public.checkins where event_id = p_event and user_id = me) into already;
  if not already then
    -- car_id null: the trigger fills in the RSVP car, else the default
    insert into public.checkins (event_id, user_id, lat, lng, source, car_id) values (p_event, me, p_lat, p_lng, 'qr', v_car);
  elsif v_car is not null then
    update public.checkins set car_id = v_car where event_id = p_event and user_id = me;
  end if;
  if v_car is not null then
    update public.event_attendees set car_id = v_car where event_id = p_event and user_id = me;
  end if;
  return json_build_object('new', not already, 'points', public.rule_points('meet_checkin'), 'distance_m', round(v_dist)::int);
end;
$$;

-- ----------------------------------------------------- event_checkin_list ---
-- Adds car_id and car_cover; `car` ("Make Model") is now the car they brought.
-- Return columns change, so drop + create (the old app reads columns by name
-- and ignores the new ones).
drop function if exists public.event_checkin_list(uuid);
create function public.event_checkin_list(p_event uuid)
returns table (
  user_id        uuid,
  username       text,
  display_name   text,
  avatar_url     text,
  car            text,
  checked_in_at  timestamptz,
  source         text,
  stayed_min     int,
  stayed         boolean,
  confirmed      boolean,
  rejected       boolean,
  car_id         uuid,
  car_cover      text
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can see who is here'; end if;
  return query
    select c.user_id, p.username::text, p.display_name, p.avatar_url,
           nullif(trim(concat_ws(' ', k.make, k.model)), ''),
           c.checked_in_at, c.source,
           coalesce(public.stayed_min(p_event, c.user_id), 0),
           public.has_stayed(p_event, c.user_id),
           c.confirmed_at is not null,
           c.confirmed_at is null and c.confirmed_by is not null,
           k.id,
           coalesce(k.portrait_url, k.photo_urls[1])
      from public.checkins c
      join public.profiles p on p.id = c.user_id
      join public.events e on e.id = c.event_id
      left join public.cars k on k.id = public.outing_car(p_event, c.user_id)
     where c.event_id = p_event and c.user_id <> e.organizer_id
     order by c.checked_in_at desc;
end;
$$;

-- -------------------------------------------------------------- event_recap ---
-- One car per check-in (the car they brought), not every car in their garage.
create or replace function public.event_recap(p_event uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'went', (select count(*) from public.checkins c where c.event_id = p_event),
    'going', (select count(*) from public.event_attendees a where a.event_id = p_event),
    'moments', (select count(*) from public.stories s where s.event_id = p_event),
    'cars', coalesce((
      select json_agg(json_build_object('id', cr.id, 'make', cr.make, 'model', cr.model,
                                        'photo', coalesce(cr.portrait_url, cr.photo_urls[1]), 'owner', pr.username))
      from public.checkins c
      join public.cars cr on cr.id = public.outing_car(p_event, c.user_id)
      join public.profiles pr on pr.id = c.user_id
      where c.event_id = p_event
    ), '[]'::json)
  );
$$;

-- ----------------------------------------------------- event_turnout_report ---
-- Cars by make / top models count the car each member brought.
create or replace function public.event_turnout_report(p_event uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e public.events;
  v jsonb;
begin
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  if not public.is_meet_host(p_event) then
    raise exception 'Only the host can see this report';
  end if;

  with c as (
    select ch.user_id, ch.checked_in_at, ch.source, ch.confirmed_at,
      exists (select 1 from public.event_attendees a where a.event_id = p_event and a.user_id = ch.user_id) as rsvped,
      not exists (select 1 from public.checkins o where o.user_id = ch.user_id and o.checked_in_at < ch.checked_in_at) as first_ever,
      public.has_stayed(p_event, ch.user_id) as stayed
    from public.checkins ch where ch.event_id = p_event
  ),
  car as (
    select c.user_id, k.make, k.model
    from c join public.cars k on k.id = public.outing_car(p_event, c.user_id)
  )
  select jsonb_build_object(
    'title', e.title,
    'starts_at', e.starts_at,
    'mode', public.meet_mode(p_event),
    'rsvps', (select count(*) from public.event_attendees where event_id = p_event),
    'checked_in', (select count(*) from c),
    'stayed', (select count(*) from c where stayed),
    'confirmed', (select count(*) from c where confirmed_at is not null),
    'rsvp_showed', (select count(*) from c where rsvped),
    'walk_ins', (select count(*) from c where not rsvped),
    'first_timers', (select count(*) from c where first_ever),
    'by_source', coalesce((select jsonb_object_agg(source, n) from (select source, count(*) n from c group by source) s), '{}'::jsonb),
    'by_make', coalesce((select jsonb_agg(jsonb_build_object('make', make, 'count', n) order by n desc, make)
                          from (select initcap(trim(make)) make, count(*) n from car group by 1) m), '[]'::jsonb),
    'top_models', coalesce((select jsonb_agg(jsonb_build_object('make', make, 'model', model, 'count', n) order by n desc)
                          from (select initcap(trim(make)) make, trim(model) model, count(*) n from car group by 1, 2 order by 3 desc limit 10) m), '[]'::jsonb),
    'no_car', (select count(*) from c where not exists (select 1 from car where car.user_id = c.user_id)),
    'arrivals', coalesce((select jsonb_agg(jsonb_build_object('at', b, 'count', n) order by b)
                          from (select date_bin('15 minutes', checked_in_at, e.starts_at) b, count(*) n from c group by 1) a), '[]'::jsonb),
    'clubs', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'count', n) order by n desc)
                          from (select cl.name, count(distinct c.user_id) n
                                from c join public.club_members m on m.user_id = c.user_id join public.clubs cl on cl.id = m.club_id
                                group by cl.name order by 2 desc limit 5) k), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

-- ------------------------------------------------------------ visible_pins ---
-- Same as 0059 except the car: while a friend is checked in at a meet
-- (user_locations.event_id), their pin shows the car they brought there.
create or replace function public.visible_pins()
returns table (user_id uuid, lat float8, lng float8, heading float8, accuracy float8, ghost boolean, place_id uuid, event_id uuid,
               updated_at timestamptz, profiles json, places json, events json, via text, club_name text,
               car_make text, car_model text, car_color text, car_photo text)
language sql stable security definer set search_path = public as $$
  with me as (select l.lat, l.lng from public.user_locations l where l.user_id = auth.uid())
  select l.user_id,
         case when v.via in ('nearby','public') then round(l.lat::numeric, 3)::float8 else l.lat end,
         case when v.via in ('nearby','public') then round(l.lng::numeric, 3)::float8 else l.lng end,
         l.heading, l.accuracy, l.ghost,
         case when v.via in ('nearby','public') then null else l.place_id end,
         case when v.via in ('nearby','public') then null else l.event_id end,
         l.updated_at,
         json_build_object('id', pr.id, 'username', pr.username, 'display_name', case when v.via in ('nearby','public') then null else pr.display_name end,
                           'bio', null, 'avatar_url', case when v.via in ('nearby','public') then null else pr.avatar_url end,
                           'home_state', pr.home_state, 'created_at', pr.created_at),
         case when p.id is null or v.via in ('nearby','public') then null else json_build_object('name', p.name) end,
         case when e.id is null or v.via in ('nearby','public') then null else json_build_object('title', e.title) end,
         v.via,
         (select c.name from public.club_members a join public.club_members b on b.club_id = a.club_id join public.clubs c on c.id = a.club_id
           where a.user_id = auth.uid() and b.user_id = l.user_id and b.share_location limit 1),
         car.make, car.model, car.color, car.photo
  from public.user_locations l
  join public.profiles pr on pr.id = l.user_id
  left join public.places p on p.id = l.place_id
  left join public.events e on e.id = l.event_id
  left join lateral (select c.make, c.model, c.color, coalesce(c.portrait_url, c.photo_urls[1]) as photo
                       from public.cars c
                      where c.owner_id = l.user_id
                      order by (c.id = (select ch.car_id from public.checkins ch where ch.event_id = l.event_id and ch.user_id = l.user_id)) desc nulls last,
                               c.is_default desc, c.created_at
                      limit 1) car on true
  cross join lateral (
    select case
      when public.is_friend(auth.uid(), l.user_id) then 'friend'
      when public.is_clubmate_sharing(auth.uid(), l.user_id) then 'club'
      when exists (select 1 from public.blocks b where (b.blocker_id = auth.uid() and b.blocked_id = l.user_id) or (b.blocker_id = l.user_id and b.blocked_id = auth.uid())) then null
      when l.share_mode = 'public' then 'public'
      when l.share_mode = 'nearby'
        and exists (select 1 from me)
        and public.metres_between((select lat from me), (select lng from me), l.lat, l.lng) <= l.share_radius_m
        then 'nearby'
      else null end as via
  ) v
  where l.user_id <> auth.uid() and not l.ghost and l.expires_at > now() and v.via is not null
  order by l.updated_at desc
  limit 300;
$$;

-- ------------------------------------------------------------------ grants ---
revoke execute on function public.resolve_outing_car(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.outing_car(uuid, uuid) from public, anon;
revoke execute on function public.on_attendee_car() from public, anon, authenticated;
revoke execute on function public.on_checkin_car() from public, anon, authenticated;
revoke execute on function public.set_event_car(uuid, uuid) from public, anon;
revoke execute on function public.event_cars(uuid) from public, anon;
revoke execute on function public.tt_now(float8, float8, text, text, int, uuid[], text, uuid) from anon;
revoke execute on function public.checkin_by_qr(uuid, text, float8, float8, uuid) from anon;
revoke execute on function public.event_checkin_list(uuid) from public, anon;
grant execute on function public.outing_car(uuid, uuid) to authenticated;
grant execute on function public.set_event_car(uuid, uuid) to authenticated;
grant execute on function public.event_cars(uuid) to authenticated;
grant execute on function public.tt_now(float8, float8, text, text, int, uuid[], text, uuid) to authenticated;
grant execute on function public.checkin_by_qr(uuid, text, float8, float8, uuid) to authenticated;
grant execute on function public.event_checkin_list(uuid) to authenticated;
