-- Meet check-in flow, round two:
--   * arrival nudge: update_my_location reports a live meet within 300 m the
--     member has not checked in to (the map offers a one-tap check-in);
--   * meet-start push: due_meet_start_pushes() runs every minute (pg_cron) and
--     notifies RSVP'd members once, marked by events.start_notified_at;
--   * dwell tracking: checkin_presence records first/last ping and ping count
--     for anyone within 300 m of a live meet, RSVP'd or not. "Stayed" means
--     10+ minutes and 3+ pings;
--   * host confirmation: checkins.confirmed_at / confirmed_by. A 'small' meet
--     (< 30 RSVPs, not official-club, not partner) pings the host on every
--     check-in and the host ticks Here / Not here. A 'big' meet confirms
--     everyone who stayed automatically (auto_confirm_stayed) and the host only
--     sees the exceptions;
--   * turnout report: checked in / stayed / confirmed lines.

-- =============================================================================
-- schema
-- =============================================================================
alter table public.events add column if not exists start_notified_at timestamptz;

alter table public.checkins
  add column if not exists confirmed_at timestamptz,
  add column if not exists confirmed_by uuid references public.profiles (id) on delete set null;
-- confirmed_at set            = host says they were here
-- confirmed_by set, _at null  = host says they were not (explicit "Not here")
-- both null                   = not decided yet
create index if not exists checkins_event_confirmed_idx on public.checkins (event_id) where confirmed_at is null;

create table if not exists public.checkin_presence (
  event_id       uuid not null references public.events (id) on delete cascade,
  user_id        uuid not null references public.profiles (id) on delete cascade,
  first_seen_at  timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  pings          int not null default 1,
  primary key (event_id, user_id)
);
alter table public.checkin_presence enable row level security;
create policy "presence: read own" on public.checkin_presence for select to authenticated using (user_id = auth.uid());
-- writes only through update_my_location (security definer)

-- =============================================================================
-- helpers
-- =============================================================================

-- Minutes between the first and last ping near the meet; null when never seen.
create or replace function public.stayed_min(p_event uuid, p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select floor(extract(epoch from (last_seen_at - first_seen_at)) / 60)::int
  from public.checkin_presence where event_id = p_event and user_id = p_user;
$$;

create or replace function public.has_stayed(p_event uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select last_seen_at - first_seen_at >= interval '10 minutes' and pings >= 3
                   from public.checkin_presence where event_id = p_event and user_id = p_user), false);
$$;

-- 'small' = fewer than 30 RSVPs and neither an official-club nor a partner
-- meet. Small meets are confirmed by the host by hand; big meets confirm
-- whoever stayed 10+ minutes on their own.
create or replace function public.meet_mode(p_event uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when e.vendor_id is not null then 'big'
    when e.club_id is not null and exists (select 1 from public.clubs c where c.id = e.club_id and c.tier = 'official') then 'big'
    when (select count(*) from public.event_attendees a where a.event_id = e.id) >= 30 then 'big'
    else 'small'
  end
  from public.events e where e.id = p_event;
$$;

-- Who may run the door: the organiser, officers of the hosting club, admins
-- (same circle as the turnout report).
create or replace function public.is_meet_host(p_event uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select p_user is not null and exists (
    select 1 from public.events e
    where e.id = p_event
      and (e.organizer_id = p_user or public.is_admin(p_user)
           or (e.club_id is not null and exists (select 1 from public.club_members m
                 where m.club_id = e.club_id and m.user_id = p_user and m.role in ('owner', 'vp', 'secretary'))))
  );
$$;

-- =============================================================================
-- host confirmation
-- =============================================================================

create or replace function public.host_confirm_checkin(p_event uuid, p_user uuid, p_confirmed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can confirm arrivals'; end if;
  update public.checkins
     set confirmed_at = case when p_confirmed then now() end,
         confirmed_by = auth.uid()
   where event_id = p_event and user_id = p_user;
end;
$$;

-- Confirms every check-in the host has not decided on yet ("Confirm all so
-- far" on a small meet, "Confirm the rest" on a big one). Explicit "Not here"
-- marks are left alone. Returns how many were confirmed.
create or replace function public.host_confirm_all(p_event uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can confirm arrivals'; end if;
  update public.checkins
     set confirmed_at = now(), confirmed_by = auth.uid()
   where event_id = p_event and confirmed_at is null and confirmed_by is null;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Big meets: confirm everyone who stayed 10+ min and is still undecided.
-- Called from update_my_location on the host's own ping and by the app when
-- the host opens the list or the report. Quietly does nothing for small meets
-- and for non-hosts, so it is safe to call opportunistically.
create or replace function public.auto_confirm_stayed(p_event uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; v_org uuid;
begin
  if not public.is_meet_host(p_event) then return 0; end if;
  if public.meet_mode(p_event) <> 'big' then return 0; end if;
  select organizer_id into v_org from public.events where id = p_event;
  update public.checkins c
     set confirmed_at = now(), confirmed_by = coalesce(v_org, auth.uid())
   where c.event_id = p_event and c.confirmed_at is null and c.confirmed_by is null
     and public.has_stayed(p_event, c.user_id);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- The host's door list: everyone who checked in (the host themself left out),
-- newest first, with their default car, how long they were seen near the
-- meet, and what the host decided.
create or replace function public.event_checkin_list(p_event uuid)
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
  rejected       boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can see who is here'; end if;
  return query
    select c.user_id, p.username, p.display_name, p.avatar_url,
           (select nullif(trim(concat_ws(' ', k.make, k.model)), '')
              from public.cars k where k.owner_id = c.user_id
             order by k.is_default desc, k.created_at desc limit 1),
           c.checked_in_at, c.source,
           coalesce(public.stayed_min(p_event, c.user_id), 0),
           public.has_stayed(p_event, c.user_id),
           c.confirmed_at is not null,
           c.confirmed_at is null and c.confirmed_by is not null
      from public.checkins c
      join public.profiles p on p.id = c.user_id
      join public.events e on e.id = c.event_id
     where c.event_id = p_event and c.user_id <> e.organizer_id
     order by c.checked_in_at desc;
end;
$$;

-- Small meets: the host hears about every arrival (type 'checkin').
create or replace function public.on_checkin_notify_host() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  select organizer_id into v_org from public.events where id = new.event_id;
  if v_org is not null and v_org <> new.user_id and public.meet_mode(new.event_id) = 'small' then
    perform public.notify(v_org, new.user_id, 'checkin', p_event => new.event_id);
  end if;
  return new;
end;
$$;
drop trigger if exists checkins_after_insert_notify on public.checkins;
create trigger checkins_after_insert_notify after insert on public.checkins
  for each row execute function public.on_checkin_notify_host();

-- =============================================================================
-- location ping: nudge at 300 m, dwell tracking, host auto-confirm
-- =============================================================================
create or replace function public.update_my_location(p_lat float8, p_lng float8, p_heading float8 default null, p_accuracy float8 default null)
returns json
language plpgsql security definer set search_path = public as $$
declare
  me         uuid := auth.uid();
  v_place    public.places;
  v_ev_id    uuid;
  v_ev_title text;
  v_ev_org   uuid;
  v_dist     float8;
  v_rsvpd    boolean;
  v_already  boolean;
  v_checked  uuid;
  v_near     boolean := false;   -- within the 300 m check-in radius
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
  select e.id, e.title, e.organizer_id, public.metres_between(p_lat, p_lng, e.lat, e.lng),
         exists (select 1 from public.event_attendees a where a.event_id = e.id and a.user_id = me),
         exists (select 1 from public.checkins c where c.event_id = e.id and c.user_id = me)
  into v_ev_id, v_ev_title, v_ev_org, v_dist, v_rsvpd, v_already
  from public.events e
  where e.status = 'active'
    and now() between e.starts_at - interval '1 hour' and coalesce(e.ends_at, e.starts_at + interval '6 hours')
    and abs(e.lat - p_lat) < 0.01 and abs(e.lng - p_lng) < 0.01
    and public.metres_between(p_lat, p_lng, e.lat, e.lng) <= 500
  order by public.metres_between(p_lat, p_lng, e.lat, e.lng)
  limit 1;

  if v_ev_id is not null then
    v_near := v_dist <= 300;

    -- dwell: anyone within 300 m, RSVP'd or not
    if v_near then
      insert into public.checkin_presence (event_id, user_id) values (v_ev_id, me)
      on conflict (event_id, user_id) do update
        set last_seen_at = now(), pings = checkin_presence.pings + 1;
    end if;

    if v_already then
      v_checked := v_ev_id;
    elsif v_rsvpd or v_ev_org = me then
      begin
        insert into public.checkins (event_id, user_id, lat, lng, source) values (v_ev_id, me, p_lat, p_lng, 'auto');
        v_checked := v_ev_id;
      exception when others then v_checked := null;
      end;
    end if;

    -- the host's own ping settles a big meet's list
    if v_ev_org = me then
      begin
        perform public.auto_confirm_stayed(v_ev_id);
      exception when others then null;
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
    -- the nudge only fires inside the 300 m check-in radius
    'nearby_event_id', case when v_near and v_checked is null then v_ev_id end,
    'nearby_event_title', case when v_near and v_checked is null then v_ev_title end,
    'nearby_distance_m', case when v_ev_id is not null then round(v_dist)::int end
  );
end;
$$;

-- =============================================================================
-- meet-start push
-- =============================================================================

-- Every RSVP'd member gets one 'meet_start' notification when the meet begins.
-- Idempotent through events.start_notified_at; only meets that started in the
-- last five minutes qualify, so a long cron outage does not flood old meets.
create or replace function public.due_meet_start_pushes() returns int
language plpgsql security definer set search_path = public as $$
declare
  e record;
  n int := 0;
  k int;
begin
  for e in
    update public.events
       set start_notified_at = now()
     where status = 'active'
       and start_notified_at is null
       and starts_at between now() - interval '5 minutes' and now()
    returning id, organizer_id
  loop
    insert into public.notifications (user_id, actor_id, type, event_id)
    select a.user_id, e.organizer_id, 'meet_start', e.id
      from public.event_attendees a
     where a.event_id = e.id and a.user_id <> e.organizer_id;
    get diagnostics k = row_count;
    n := n + k;
  end loop;
  return n;
end;
$$;

-- pg_cron is already in use (car of the week, story expiry); guarded anyway
-- so the migration applies on a project without it. If the notice below shows
-- up, call public.due_meet_start_pushes() every minute from elsewhere
-- (an Edge Function on a schedule, for example).
do $outer$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron could not be created: %', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'ttspot-meet-start') then
      perform cron.unschedule('ttspot-meet-start');
    end if;
    perform cron.schedule('ttspot-meet-start', '* * * * *', 'select public.due_meet_start_pushes()');
  else
    raise notice 'pg_cron not available: schedule public.due_meet_start_pushes() every minute some other way';
  end if;
end;
$outer$;

-- =============================================================================
-- turnout report: checked in / stayed / confirmed
-- =============================================================================
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
    from c cross join lateral (
      select make, model from public.cars where owner_id = c.user_id order by is_default desc, created_at desc limit 1
    ) k
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

-- =============================================================================
-- grants
-- =============================================================================
revoke execute on function public.stayed_min(uuid, uuid) from public, anon;
revoke execute on function public.has_stayed(uuid, uuid) from public, anon;
revoke execute on function public.meet_mode(uuid) from public, anon;
revoke execute on function public.is_meet_host(uuid, uuid) from public, anon;
revoke execute on function public.host_confirm_checkin(uuid, uuid, boolean) from public, anon;
revoke execute on function public.host_confirm_all(uuid) from public, anon;
revoke execute on function public.auto_confirm_stayed(uuid) from public, anon;
revoke execute on function public.event_checkin_list(uuid) from public, anon;
revoke execute on function public.due_meet_start_pushes() from public, anon, authenticated;
grant execute on function public.stayed_min(uuid, uuid) to authenticated;
grant execute on function public.has_stayed(uuid, uuid) to authenticated;
grant execute on function public.meet_mode(uuid) to authenticated;
grant execute on function public.is_meet_host(uuid, uuid) to authenticated;
grant execute on function public.host_confirm_checkin(uuid, uuid, boolean) to authenticated;
grant execute on function public.host_confirm_all(uuid) to authenticated;
grant execute on function public.auto_confirm_stayed(uuid) to authenticated;
grant execute on function public.event_checkin_list(uuid) to authenticated;
