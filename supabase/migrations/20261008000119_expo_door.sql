-- =============================================================================
-- Expo mode, track A: door check-in, check-in area, event pass, event hub,
-- registration form (docs/expo-mode-plan.md items 1-6). Schema is in 0118.
-- =============================================================================

-- ------------------------------------------------------- check-in area ---

-- The event's check-in radius in metres: its own, else the global setting.
create or replace function public.event_checkin_radius(p_event uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(
    (select e.checkin_radius_m from public.events e where e.id = p_event),
    public.setting_num('checkin_radius_m', 300)::int
  );
$$;

-- "1.2 km" / "350 m" for error messages.
create or replace function public.format_distance(p_m float8)
returns text language sql immutable set search_path = public as $$
  select case when p_m >= 1000 then regexp_replace(to_char(p_m / 1000.0, 'FM999990.0'), '\.0$', '') || ' km'
              else round(p_m)::int::text || ' m' end;
$$;

-- Host: set the check-in area. Null = back to the default. Hosts up to 5 km,
-- admins up to 100 km (the column allows 50 m to 100 km).
create or replace function public.set_event_checkin_radius(p_event uuid, p_m int)
returns int language plpgsql security definer set search_path = public as $$
declare v_max int;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if not public.is_meet_host(p_event) then raise exception 'Only the host can change the check-in area.'; end if;
  v_max := case when public.is_admin() then 100000 else 5000 end;
  if p_m is not null and (p_m < 50 or p_m > v_max) then
    raise exception 'Pick between 50 m and %.', public.format_distance(v_max);
  end if;
  update public.events set checkin_radius_m = p_m where id = p_event;
  return public.event_checkin_radius(p_event);
end;
$$;

-- Live checkin_by_qr (5 args), now with the event's own radius and the entry
-- number in the result.
create or replace function public.checkin_by_qr(p_event uuid, p_code text, p_lat double precision default null::double precision, p_lng double precision default null::double precision, p_car uuid default null::uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  w bigint := floor(extract(epoch from now()) / 30)::bigint;
  already boolean;
  e public.events%rowtype;
  v_dist float8;
  v_radius float8 := public.event_checkin_radius(p_event);
  v_car uuid;
  v_no int;
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
    raise exception 'You are % from the meet. Get within % to check in.', public.format_distance(v_dist), public.format_distance(v_radius);
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
  select entry_no into v_no from public.checkins where event_id = p_event and user_id = me;
  return json_build_object('new', not already, 'points', public.rule_points('meet_checkin'), 'distance_m', round(v_dist)::int, 'entry_no', v_no);
end;
$$;

-- Live on_checkin_insert: the 500 m GPS check grows with the event's area.
create or replace function public.on_checkin_insert()
returns trigger language plpgsql security definer set search_path = public as $$
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
  if new.source not in ('organizer', 'qr') then
    if new.lat is null or new.lng is null then raise exception 'Turn on location to check in'; end if;
    if public.metres_between(new.lat, new.lng, e.lat, e.lng) > greatest(500, public.event_checkin_radius(new.event_id)) then
      raise exception 'You are too far from the meet to check in';
    end if;
  end if;
  return new;
end; $$;

-- ------------------------------------------------------------- door QR ---

-- The event's invite QR (https://ttspot.my/e/<CODE>) scanned in the app.
--   not live            -> {event_id, live:false}: the app opens the event page
--   live, no location   -> {event_id, live:true, need_location:true}
--   live                -> checks in (inside the area), or finds my check-in:
--                          {event_id, live:true, new, entry_no, points,
--                           has_floorplan, distance_m, has_form, form_done}
create or replace function public.checkin_by_door(p_code text, p_lat float8 default null, p_lng float8 default null, p_car uuid default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_event uuid;
  e public.events%rowtype;
  w record;
  v_radius float8;
  v_dist float8;
  v_car uuid;
  v_new boolean := false;
  v_no int;
begin
  if me is null then raise exception 'Not signed in'; end if;
  v_event := public.event_for_invite_code(p_code);
  if v_event is null then raise exception 'That invite code isn''t linked to a meet any more.'; end if;
  select * into e from public.events where id = v_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  select * into w from public.event_live_window(v_event);
  if e.status <> 'active' or now() < w.opens_at or now() > w.closes_at then
    return json_build_object('event_id', v_event, 'live', false);
  end if;
  if p_car is not null then v_car := public.resolve_outing_car(me, p_car); end if;

  if p_lat is not null and p_lng is not null then
    v_dist := public.metres_between(p_lat, p_lng, e.lat, e.lng);
  end if;

  if not exists (select 1 from public.checkins where event_id = v_event and user_id = me) then
    if v_dist is null then
      return json_build_object('event_id', v_event, 'live', true, 'need_location', true);
    end if;
    v_radius := public.event_checkin_radius(v_event);
    if v_dist > v_radius then
      raise exception 'You are % from the event. Get within % to check in.', public.format_distance(v_dist), public.format_distance(v_radius);
    end if;
    insert into public.checkins (event_id, user_id, lat, lng, source, car_id)
    values (v_event, me, p_lat, p_lng, 'qr', v_car)
    on conflict (event_id, user_id) do nothing;
    v_new := found;
  end if;
  if v_car is not null then
    update public.checkins set car_id = v_car where event_id = v_event and user_id = me and car_id is distinct from v_car;
    update public.event_attendees set car_id = v_car where event_id = v_event and user_id = me;
  end if;
  select entry_no into v_no from public.checkins where event_id = v_event and user_id = me;

  return json_build_object(
    'event_id', v_event,
    'live', true,
    'new', v_new,
    'entry_no', v_no,
    'points', case when v_new then public.rule_points('meet_checkin') else 0 end,
    'has_floorplan', exists (select 1 from public.event_floor_levels l where l.event_id = v_event and l.image_path is not null),
    'distance_m', case when v_dist is null then null else round(v_dist)::int end,
    'has_form', exists (select 1 from public.event_forms f where f.event_id = v_event and jsonb_array_length(f.questions) > 0),
    'form_done', exists (select 1 from public.event_registrations r where r.event_id = v_event and r.user_id = me)
  );
end;
$$;

-- ---------------------------------------------------------- event hub ---

-- Everything the event page's hub card and my pass need, for me.
create or replace function public.event_hub(p_event uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  c public.checkins%rowtype;
  f public.event_forms%rowtype;
  w record;
  v_car_id uuid;
  v_car json;
begin
  if me is null then return null; end if;
  select * into c from public.checkins where event_id = p_event and user_id = me;
  select * into f from public.event_forms where event_id = p_event;
  select * into w from public.event_live_window(p_event);

  v_car_id := coalesce(c.car_id,
                       (select a.car_id from public.event_attendees a where a.event_id = p_event and a.user_id = me),
                       (select k.id from public.cars k where k.owner_id = me order by k.is_default desc, k.created_at asc limit 1));
  select json_build_object(
           'id', k.id,
           'title', trim(k.make || ' ' || coalesce(k.model, '')),
           'cover', coalesce(k.portrait_url, k.photo_urls[1]),
           'toy_url', k.toy_url,
           'body_style', k.body_style)
    into v_car
    from public.cars k where k.id = v_car_id;

  return json_build_object(
    'checked_in', c.user_id is not null,
    'entry_no', c.entry_no,
    'pass_code', c.pass_code,
    'share_contact', coalesce(c.share_contact, false),
    'checked_in_at', c.checked_in_at,
    'live', now() between w.opens_at and w.closes_at,
    'registration', json_build_object(
      'has_form', f.event_id is not null and jsonb_array_length(f.questions) > 0,
      'required', coalesce(f.required, false),
      'questions', case when f.event_id is null then 0 else jsonb_array_length(f.questions) end,
      'done', exists (select 1 from public.event_registrations r where r.event_id = p_event and r.user_id = me)),
    'levels', (select count(*) from public.event_floor_levels l where l.event_id = p_event and l.image_path is not null),
    'exhibitors', (select count(*) from public.event_exhibitors x where x.event_id = p_event),
    'agenda', (select count(*) from public.event_agenda a where a.event_id = p_event),
    'stamp_stops', (select count(*) from public.event_exhibitors x where x.event_id = p_event and x.stamp_stop),
    'my_stamps', (select count(*) from public.event_booth_visits v where v.event_id = p_event and v.user_id = me),
    'stamp_goal', (select s.stamp_goal from public.event_expo_settings s where s.event_id = p_event),
    'contest', (select json_build_object('id', k.id, 'title', k.title) from public.event_contests k
                 where k.event_id = p_event and k.status = 'open' order by k.created_at desc limit 1),
    'my_booths', coalesce((select json_agg(json_build_object('id', x.id, 'name', x.name) order by x.sort, x.name)
                             from public.event_exhibitors x
                            where x.event_id = p_event and public.is_exhibitor_staff(x.id, me)), '[]'::json),
    'is_host', public.is_meet_host(p_event),
    'car', v_car
  );
end;
$$;

-- -------------------------------------------------------------- pass ---

-- The pass switch: booths that scan my pass may see my phone + email.
create or replace function public.set_pass_share_contact(p_event uuid, p_on boolean)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update public.checkins set share_contact = coalesce(p_on, false)
   where event_id = p_event and user_id = auth.uid();
  if not found then raise exception 'Check in first to get your pass.'; end if;
  return coalesce(p_on, false);
end;
$$;

-- The pass code lets booth staff save me as a lead, so it isn't public:
-- members read checkins through these columns only (pass_code via
-- event_hub), and can't pick their own entry number or pass code.
-- NOTE: a new checkins column needs adding to this grant to be readable.
revoke select, insert, update on public.checkins from anon, authenticated;
grant select (event_id, user_id, checked_in_at, lat, lng, source, confirmed_at, confirmed_by, car_id, entry_no, share_contact)
  on public.checkins to anon, authenticated;
grant insert (event_id, user_id, lat, lng, source, car_id) on public.checkins to authenticated;

-- ------------------------------------------------------ registration ---

-- Member: save my answers. Checks the answers against the form and that I'm
-- checked in or going. [p_answers] = {"<question id>": "text" | ["a","b"]}.
create or replace function public.save_event_registration(p_event uuid, p_answers jsonb, p_contact_ok boolean default false)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  f public.event_forms%rowtype;
  q jsonb;
  v_id text;
  v_type text;
  v_a jsonb;
  v_opts jsonb;
  v_clean jsonb := '{}'::jsonb;
  v_label text;
  v_item jsonb;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if not exists (select 1 from public.checkins where event_id = p_event and user_id = me)
     and not exists (select 1 from public.event_attendees where event_id = p_event and user_id = me) then
    raise exception 'Join or check in to this event first.';
  end if;
  select * into f from public.event_forms where event_id = p_event;
  if f.event_id is null or jsonb_array_length(f.questions) = 0 then
    raise exception 'This event has no registration form.';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then p_answers := '{}'::jsonb; end if;

  for q in select * from jsonb_array_elements(f.questions) loop
    v_id := q ->> 'id';
    v_type := coalesce(q ->> 'type', 'text');
    v_label := coalesce(q ->> 'label', 'A question');
    v_opts := coalesce(q -> 'options', '[]'::jsonb);
    v_a := p_answers -> v_id;
    if v_id is null then continue; end if;

    if v_type = 'many' then
      if v_a is not null and jsonb_typeof(v_a) = 'string' then v_a := jsonb_build_array(v_a); end if;
      if v_a is not null and jsonb_typeof(v_a) = 'array' then
        -- keep only real options, once each
        select coalesce(jsonb_agg(distinct x), '[]'::jsonb) into v_a
          from jsonb_array_elements(v_a) x where v_opts @> jsonb_build_array(x);
        if jsonb_array_length(v_a) = 0 then v_a := null; end if;
      else
        v_a := null;
      end if;
    elsif v_type = 'one' then
      if v_a is null or jsonb_typeof(v_a) <> 'string' or not v_opts @> jsonb_build_array(v_a) then v_a := null; end if;
    else
      if v_a is null or jsonb_typeof(v_a) <> 'string' or btrim(v_a #>> '{}') = '' then
        v_a := null;
      else
        v_a := to_jsonb(left(btrim(v_a #>> '{}'), 500));
      end if;
    end if;

    if v_a is null then
      if coalesce((q ->> 'required')::boolean, false) then
        raise exception 'Answer "%" first.', v_label;
      end if;
    else
      v_clean := v_clean || jsonb_build_object(v_id, v_a);
    end if;
  end loop;

  insert into public.event_registrations (event_id, user_id, answers, contact_ok)
  values (p_event, me, v_clean, f.ask_contact and coalesce(p_contact_ok, false))
  on conflict (event_id, user_id) do update
    set answers = excluded.answers, contact_ok = excluded.contact_ok, updated_at = now();
  return true;
end;
$$;

-- Host: everyone who checked in or registered, with their answers. Phone and
-- email only for members who ticked "share my contact" on the form.
create or replace function public.event_registrations_export(p_event uuid)
returns table (entry_no int, name text, username text, phone text, email text, state text, car text,
               checked_in_at timestamptz, answers jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can export registrations.'; end if;
  return query
  with people as (
    select c.user_id from public.checkins c where c.event_id = p_event
    union
    select r.user_id from public.event_registrations r where r.event_id = p_event
  )
  select c.entry_no,
         coalesce(nullif(btrim(p.display_name), ''), p.username::text),
         p.username::text,
         case when r.contact_ok then pp.phone end,
         case when r.contact_ok then u.email::text end,
         p.home_state,
         (select trim(k.make || ' ' || coalesce(k.model, ''))
            from public.cars k
           where k.id = coalesce(c.car_id, (select a.car_id from public.event_attendees a where a.event_id = p_event and a.user_id = pe.user_id))),
         c.checked_in_at,
         r.answers
    from people pe
    join public.profiles p on p.id = pe.user_id
    left join public.checkins c on c.event_id = p_event and c.user_id = pe.user_id
    left join public.event_registrations r on r.event_id = p_event and r.user_id = pe.user_id
    left join public.profile_private pp on pp.user_id = pe.user_id
    left join auth.users u on u.id = pe.user_id
   order by c.entry_no nulls last, c.checked_in_at nulls last, p.username;
end;
$$;
