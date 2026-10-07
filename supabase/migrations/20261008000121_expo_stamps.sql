-- =============================================================================
-- Expo mode, track C: booth stamps, freebies and leads (docs/expo-mode-plan.md
-- items 9, 10, 11). Tables live in 0118; this file is RPCs only.
--
-- Stamps:   collect_booth_stamp, my_stamps, exhibitor_extras
-- Freebies: redeem_booth_freebie, redeem_rally_reward (swiped on the member's
--           phone by booth staff / the counter: "Hand over")
-- Host:     booth_setup_list, set_booth_stamp, set_stamp_rally,
--           add_exhibitor_staff, remove_exhibitor_staff, rotate_booth_code
-- Leads:    my_staff_booths, save_lead_by_pass, exhibitor_leads, my_event_leads
-- =============================================================================

-- ------------------------------------------------------------ helpers ---

-- "Honda Civic" for the car a member brought to an event (else their default car).
create or replace function public.expo_member_car(p_event uuid, p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select nullif(trim(concat_ws(' ', c.make, c.model)), '')
  from public.cars c
  where c.owner_id = p_user
  order by (c.id = (select k.car_id from public.checkins k where k.event_id = p_event and k.user_id = p_user)) desc nulls last,
           c.is_default desc nulls last, c.created_at
  limit 1;
$$;

-- Freebie stock left at a booth. Null = unlimited.
create or replace function public.booth_freebie_left(p_exhibitor uuid)
returns int language sql stable security definer set search_path = public as $$
  select case when x.freebie_limit is null then null
              else greatest(x.freebie_limit - (select count(*)::int from public.event_booth_visits v
                                               where v.exhibitor_id = x.id and v.freebie_redeemed_at is not null), 0) end
  from public.event_exhibitors x where x.id = p_exhibitor;
$$;

-- none (no freebie) / locked (stamp first) / available / redeemed / out (stock gone).
create or replace function public.booth_freebie_state(p_exhibitor uuid, p_user uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when x.freebie is null then 'none'
    when v.freebie_redeemed_at is not null then 'redeemed'
    when public.booth_freebie_left(x.id) = 0 then 'out'
    when v.user_id is not null then 'available'
    else 'locked' end
  from public.event_exhibitors x
  left join public.event_booth_visits v on v.exhibitor_id = x.id and v.user_id = p_user
  where x.id = p_exhibitor;
$$;

-- ----------------------------------------------------------- stamping ---

create or replace function public.collect_booth_stamp(p_exhibitor uuid, p_code text, p_lat float8 default null, p_lng float8 default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  me        uuid := auth.uid();
  v_ex      public.event_exhibitors%rowtype;
  e         public.events%rowtype;
  v_secret  text;
  v_radius  float8;
  v_dist    float8;
  v_new     boolean := false;
  v_points  int := 0;
  v_stamps  int;
  v_goal    int;
  v_reward  text;
  v_rally   boolean := false;
  v_pin     public.event_floor_pins%rowtype;
  v_redeemed timestamptz;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into v_ex from public.event_exhibitors where id = p_exhibitor;
  if v_ex.id is null then raise exception 'That booth is no longer at this event.'; end if;
  select s.stamp_code into v_secret from public.event_exhibitor_secrets s where s.exhibitor_id = v_ex.id;
  if v_secret is null or p_code is null or p_code <> v_secret then
    raise exception 'That booth QR is out of date. Ask the booth for the new one.';
  end if;
  if not v_ex.stamp_stop then raise exception '% is not a stamp stop.', v_ex.name; end if;
  if not exists (select 1 from public.checkins k where k.event_id = v_ex.event_id and k.user_id = me) then
    raise exception 'Check in at the door first, then scan the booth again.';
  end if;
  if p_lat is null or p_lng is null then
    raise exception 'Turn on location so we can confirm you are at the event, then scan again.';
  end if;
  select * into e from public.events where id = v_ex.event_id;
  v_radius := coalesce(e.checkin_radius_m, public.setting_num('checkin_radius_m', 300));
  if e.lat is not null and e.lng is not null then
    v_dist := public.metres_between(p_lat, p_lng, e.lat, e.lng);
    if v_dist > v_radius then
      raise exception 'You are % m from the event. Scan the QR at the booth.', round(v_dist)::int;
    end if;
  end if;

  insert into public.event_booth_visits (exhibitor_id, user_id, event_id)
  values (v_ex.id, me, v_ex.event_id)
  on conflict (exhibitor_id, user_id) do nothing;
  v_new := found;

  if v_new and public.award_points(me, public.rule_points('booth_stamp'), 'booth_stamp', 'exhibitor', v_ex.id::text, null,
                                   'booth_stamp:' || v_ex.id || ':' || me) then
    v_points := public.rule_points('booth_stamp');
  end if;

  -- "You are here": the exhibitor's first booth pin on the plan.
  select p.* into v_pin
  from public.event_floor_pins p join public.event_floor_levels l on l.id = p.level_id
  where p.exhibitor_id = v_ex.id and l.event_id = v_ex.event_id
  order by l.sort, p.label nulls last, p.created_at
  limit 1;
  if v_pin.id is not null then
    insert into public.event_positions as ep (event_id, user_id, level_id, x, y, zone_pin_id)
    values (v_ex.event_id, me, v_pin.level_id, v_pin.x, v_pin.y, v_pin.id)
    on conflict on constraint event_positions_pkey do update
      set level_id = excluded.level_id, x = excluded.x, y = excluded.y, zone_pin_id = excluded.zone_pin_id;
  end if;

  select count(*)::int into v_stamps
  from public.event_booth_visits v join public.event_exhibitors x on x.id = v.exhibitor_id
  where v.event_id = v_ex.event_id and v.user_id = me and x.stamp_stop;

  select s.stamp_goal, s.stamp_reward into v_goal, v_reward from public.event_expo_settings s where s.event_id = v_ex.event_id;
  if v_goal is not null and v_stamps >= v_goal then
    insert into public.event_rally_claims (event_id, user_id) values (v_ex.event_id, me) on conflict do nothing;
  end if;
  v_rally := exists (select 1 from public.event_rally_claims c where c.event_id = v_ex.event_id and c.user_id = me);

  select v.freebie_redeemed_at into v_redeemed from public.event_booth_visits v where v.exhibitor_id = v_ex.id and v.user_id = me;

  return json_build_object(
    'event_id', v_ex.event_id,
    'exhibitor_id', v_ex.id,
    'exhibitor_name', v_ex.name,
    'new', v_new,
    'points', v_points,
    'stamps', v_stamps,
    'goal', v_goal,
    'rally_done', v_rally,
    'reward', v_reward,
    'freebie', v_ex.freebie,
    'freebie_left', public.booth_freebie_left(v_ex.id),
    'freebie_redeemed', v_redeemed is not null,
    'level_id', v_pin.level_id
  );
end;
$$;

-- --------------------------------------------- freebies & the reward ---

-- Booth staff swipe "Hand over" on the member's phone. One per member;
-- the exhibitor row is locked so the last item can't go out twice.
create or replace function public.redeem_booth_freebie(p_exhibitor uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  me     uuid := auth.uid();
  v_ex   public.event_exhibitors%rowtype;
  v_red  timestamptz;
  v_has  boolean;
  v_used int;
  v_now  timestamptz := now();
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into v_ex from public.event_exhibitors where id = p_exhibitor for update;
  if v_ex.id is null then raise exception 'That booth is no longer at this event.'; end if;
  if v_ex.freebie is null then raise exception 'This booth has no freebie right now.'; end if;
  select true, v.freebie_redeemed_at into v_has, v_red
  from public.event_booth_visits v where v.exhibitor_id = v_ex.id and v.user_id = me for update;
  if v_has is null then raise exception 'Scan the booth QR to get the stamp first.'; end if;
  if v_red is not null then raise exception 'Already handed over.'; end if;
  if v_ex.freebie_limit is not null then
    select count(*)::int into v_used from public.event_booth_visits v
    where v.exhibitor_id = v_ex.id and v.freebie_redeemed_at is not null;
    if v_used >= v_ex.freebie_limit then raise exception 'All gone. Sorry, % is out of stock.', v_ex.freebie; end if;
  end if;
  update public.event_booth_visits set freebie_redeemed_at = v_now where exhibitor_id = v_ex.id and user_id = me;
  return json_build_object(
    'freebie', v_ex.freebie,
    'redeemed_at', v_now,
    'left', case when v_ex.freebie_limit is null then null else greatest(v_ex.freebie_limit - v_used - 1, 0) end
  );
end;
$$;

-- The rally reward, collected at the counter (crew swipe it on the member's phone).
create or replace function public.redeem_rally_reward(p_event uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  me     uuid := auth.uid();
  v_done timestamptz;
  v_red  timestamptz;
  v_now  timestamptz := now();
begin
  if me is null then raise exception 'Sign in first'; end if;
  select c.completed_at, c.redeemed_at into v_done, v_red
  from public.event_rally_claims c where c.event_id = p_event and c.user_id = me for update;
  if v_done is null then raise exception 'Collect all the stamps first.'; end if;
  if v_red is not null then raise exception 'Already handed over.'; end if;
  update public.event_rally_claims set redeemed_at = v_now where event_id = p_event and user_id = me;
  return json_build_object(
    'reward', (select s.stamp_reward from public.event_expo_settings s where s.event_id = p_event),
    'redeemed_at', v_now
  );
end;
$$;

-- ------------------------------------------------------------- status ---

-- My stamp card for an event: every stamp stop, my stamps, freebies, the rally.
create or replace function public.my_stamps(p_event uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_stops json;
  v_goal int;
  v_reward text;
  v_done timestamptz;
  v_red timestamptz;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select coalesce(json_agg(r order by r.sort, r.name), '[]'::json) into v_stops from (
    select x.id, x.name, x.booths, x.logo_url, x.sort,
           v.stamped_at, x.freebie,
           public.booth_freebie_state(x.id, me) as freebie_state,
           v.freebie_redeemed_at,
           public.booth_freebie_left(x.id) as freebie_left,
           pin.id as pin_id, pin.level_id, pin.x, pin.y
    from public.event_exhibitors x
    left join public.event_booth_visits v on v.exhibitor_id = x.id and v.user_id = me
    left join lateral (
      select p.id, p.level_id, p.x, p.y
      from public.event_floor_pins p join public.event_floor_levels l on l.id = p.level_id
      where p.exhibitor_id = x.id
      order by l.sort, p.label nulls last, p.created_at
      limit 1
    ) pin on true
    where x.event_id = p_event and x.stamp_stop
  ) r;
  select s.stamp_goal, s.stamp_reward into v_goal, v_reward from public.event_expo_settings s where s.event_id = p_event;
  select c.completed_at, c.redeemed_at into v_done, v_red from public.event_rally_claims c where c.event_id = p_event and c.user_id = me;
  return json_build_object(
    'stops', v_stops,
    'goal', v_goal,
    'reward', v_reward,
    'checked_in', exists (select 1 from public.checkins k where k.event_id = p_event and k.user_id = me),
    'rally', case when v_red is not null then 'redeemed' when v_done is not null then 'done' else 'none' end,
    'rally_completed_at', v_done,
    'rally_redeemed_at', v_red
  );
end;
$$;

-- One exhibitor as I see it (the exhibitor sheet): stamp, freebie, and leads if I'm staff.
create or replace function public.exhibitor_extras(p_exhibitor uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_ex public.event_exhibitors%rowtype;
  v_at timestamptz;
  v_staff boolean;
begin
  select * into v_ex from public.event_exhibitors where id = p_exhibitor;
  if v_ex.id is null then return null; end if;
  select v.stamped_at into v_at from public.event_booth_visits v where v.exhibitor_id = v_ex.id and v.user_id = me;
  v_staff := public.is_exhibitor_staff(v_ex.id, me);
  return json_build_object(
    'stamp_stop', v_ex.stamp_stop,
    'stamped', v_at is not null,
    'stamped_at', v_at,
    'freebie', case when v_ex.stamp_stop then v_ex.freebie end,
    'freebie_state', case when v_ex.stamp_stop then public.booth_freebie_state(v_ex.id, me) else 'none' end,
    'freebie_left', public.booth_freebie_left(v_ex.id),
    'am_staff', v_staff,
    'lead_count', case when v_staff then (select count(*)::int from public.event_leads l where l.exhibitor_id = v_ex.id) end
  );
end;
$$;

-- ------------------------------------------------------- booth setup ---

create or replace function public.booth_setup_list(p_event uuid)
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can set up booths.'; end if;
  return coalesce((
    select json_agg(r order by r.sort, r.name) from (
      select x.id, x.name, x.booths, x.sort, x.stamp_stop, x.freebie, x.freebie_limit,
             s.stamp_code,
             (select count(*)::int from public.event_booth_visits v where v.exhibitor_id = x.id) as stamps,
             (select count(*)::int from public.event_booth_visits v where v.exhibitor_id = x.id and v.freebie_redeemed_at is not null) as freebies_redeemed,
             (select count(*)::int from public.event_leads l where l.exhibitor_id = x.id) as leads,
             coalesce((select json_agg(json_build_object('user_id', p.id, 'username', p.username, 'name', coalesce(p.display_name, p.username::text))
                                       order by st.created_at)
                       from public.event_exhibitor_staff st join public.profiles p on p.id = st.user_id
                       where st.exhibitor_id = x.id), '[]'::json) as staff
      from public.event_exhibitors x
      left join public.event_exhibitor_secrets s on s.exhibitor_id = x.id
      where x.event_id = p_event
    ) r
  ), '[]'::json);
end;
$$;

create or replace function public.set_booth_stamp(p_exhibitor uuid, p_stop boolean, p_freebie text default null, p_limit int default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  select event_id into v_event from public.event_exhibitors where id = p_exhibitor;
  if v_event is null then raise exception 'That exhibitor no longer exists.'; end if;
  if not public.is_meet_host(v_event) then raise exception 'Only the host can set up booths.'; end if;
  if p_limit is not null and (p_limit < 1 or p_limit > 100000) then raise exception 'Stock must be between 1 and 100,000.'; end if;
  update public.event_exhibitors
     set stamp_stop = coalesce(p_stop, false),
         freebie = nullif(left(trim(coalesce(p_freebie, '')), 80), ''),
         freebie_limit = case when nullif(trim(coalesce(p_freebie, '')), '') is null then null else p_limit end
   where id = p_exhibitor;
  insert into public.event_exhibitor_secrets (exhibitor_id) values (p_exhibitor) on conflict do nothing;
end;
$$;

create or replace function public.set_stamp_rally(p_event uuid, p_goal int, p_reward text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can set up the stamp rally.'; end if;
  if p_goal is not null and (p_goal < 1 or p_goal > 50) then raise exception 'The goal must be between 1 and 50 stamps.'; end if;
  insert into public.event_expo_settings as s (event_id, stamp_goal, stamp_reward, updated_at)
  values (p_event, p_goal, nullif(left(trim(coalesce(p_reward, '')), 120), ''), now())
  on conflict (event_id) do update
    set stamp_goal = excluded.stamp_goal, stamp_reward = excluded.stamp_reward, updated_at = now();
end;
$$;

create or replace function public.add_exhibitor_staff(p_exhibitor uuid, p_username text)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_ex public.event_exhibitors%rowtype;
  v_title text;
  v_user public.profiles%rowtype;
  v_handle text := trim(leading '@' from trim(coalesce(p_username, '')));
begin
  select * into v_ex from public.event_exhibitors where id = p_exhibitor;
  if v_ex.id is null then raise exception 'That exhibitor no longer exists.'; end if;
  if not public.is_meet_host(v_ex.event_id) then raise exception 'Only the host can add booth staff.'; end if;
  if v_handle = '' then raise exception 'Enter an @handle.'; end if;
  select * into v_user from public.profiles where username = v_handle::citext;
  if v_user.id is null then raise exception 'No one is called @%.', v_handle; end if;
  insert into public.event_exhibitor_staff (exhibitor_id, user_id, added_by) values (v_ex.id, v_user.id, me)
  on conflict do nothing;
  if found then
    select title into v_title from public.events where id = v_ex.event_id;
    insert into public.notifications (user_id, type, event_id, body, actor_id)
    values (v_user.id, 'announcement', v_ex.event_id,
            'You''re booth staff' || E'\n' || v_ex.name || ' at ' || coalesce(v_title, 'the event') || '. Scan passes to save leads.',
            me);
  end if;
  return json_build_object('user_id', v_user.id, 'username', v_user.username, 'name', coalesce(v_user.display_name, v_user.username::text));
end;
$$;

create or replace function public.remove_exhibitor_staff(p_exhibitor uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  select event_id into v_event from public.event_exhibitors where id = p_exhibitor;
  if v_event is null then raise exception 'That exhibitor no longer exists.'; end if;
  if not public.is_meet_host(v_event) then raise exception 'Only the host can remove booth staff.'; end if;
  delete from public.event_exhibitor_staff where exhibitor_id = p_exhibitor and user_id = p_user;
end;
$$;

-- New stamp code: the old printed QR stops working.
create or replace function public.rotate_booth_code(p_exhibitor uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_event uuid; v_code text := substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 12);
begin
  select event_id into v_event from public.event_exhibitors where id = p_exhibitor;
  if v_event is null then raise exception 'That exhibitor no longer exists.'; end if;
  if not public.is_meet_host(v_event) then raise exception 'Only the host can change booth codes.'; end if;
  insert into public.event_exhibitor_secrets as s (exhibitor_id, stamp_code) values (p_exhibitor, v_code)
  on conflict (exhibitor_id) do update set stamp_code = excluded.stamp_code;
  return v_code;
end;
$$;

-- --------------------------------------------------------------- leads ---

-- The booths I staff at an event (lead scanning picks one).
create or replace function public.my_staff_booths(p_event uuid)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', x.id, 'name', x.name, 'booths', x.booths) order by x.sort, x.name), '[]'::json)
  from public.event_exhibitors x
  where x.event_id = p_event and public.is_exhibitor_staff(x.id, auth.uid());
$$;

create or replace function public.save_lead_by_pass(p_event uuid, p_pass_code text, p_exhibitor uuid default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  me      uuid := auth.uid();
  v_ex    public.event_exhibitors%rowtype;
  v_n     int;
  v_names text;
  v_user  uuid;
  v_prof  public.profiles%rowtype;
  v_new   boolean;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if p_exhibitor is not null then
    select * into v_ex from public.event_exhibitors where id = p_exhibitor and event_id = p_event;
    if v_ex.id is null or not public.is_exhibitor_staff(v_ex.id, me) then
      raise exception 'You are not staff at that booth.';
    end if;
  else
    select count(*)::int, string_agg(x.name, ', ' order by x.sort, x.name) into v_n, v_names
    from public.event_exhibitors x where x.event_id = p_event and public.is_exhibitor_staff(x.id, me);
    if v_n = 0 then raise exception 'Only booth staff can scan passes. Ask the organizer to add you.'; end if;
    if v_n > 1 then raise exception 'You staff % booths (%). Pick one first.', v_n, v_names; end if;
    select * into v_ex from public.event_exhibitors x where x.event_id = p_event and public.is_exhibitor_staff(x.id, me);
  end if;

  select k.user_id into v_user from public.checkins k where k.event_id = p_event and k.pass_code = p_pass_code;
  if v_user is null then raise exception 'That pass is not for this event.'; end if;
  if v_user = me then raise exception 'That is your own pass.'; end if;

  insert into public.event_leads (exhibitor_id, user_id, scanned_by) values (v_ex.id, v_user, me)
  on conflict (exhibitor_id, user_id) do nothing;
  v_new := found;
  if v_new then
    insert into public.notifications (user_id, type, event_id, body, actor_id)
    values (v_user, 'announcement', p_event, v_ex.name || ' saved your contact' || E'\n' || 'See or remove it on your event pass.', me);
  end if;

  select * into v_prof from public.profiles where id = v_user;
  return json_build_object(
    'exhibitor_id', v_ex.id,
    'exhibitor_name', v_ex.name,
    'new', v_new,
    'name', coalesce(v_prof.display_name, v_prof.username::text),
    'username', v_prof.username,
    'car', public.expo_member_car(p_event, v_user)
  );
end;
$$;

-- Booth staff: everyone we scanned. Phone + email only when that member
-- switched on "Share my contact with booths" on their pass.
create or replace function public.exhibitor_leads(p_exhibitor uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_event uuid;
begin
  select event_id into v_event from public.event_exhibitors where id = p_exhibitor;
  if v_event is null then raise exception 'That exhibitor no longer exists.'; end if;
  if not public.is_exhibitor_staff(p_exhibitor) then raise exception 'Only booth staff can see leads.'; end if;
  return coalesce((
    select json_agg(r order by r.created_at desc) from (
      select l.id, l.user_id, l.note, l.created_at,
             coalesce(p.display_name, p.username::text) as name,
             p.username, p.avatar_url, p.home_state as state,
             car.make as car_make, car.model as car_model,
             coalesce(k.share_contact, false) as shared,
             case when k.share_contact then pp.phone end as phone,
             case when k.share_contact then u.email::text end as email
      from public.event_leads l
      join public.profiles p on p.id = l.user_id
      left join public.checkins k on k.event_id = v_event and k.user_id = l.user_id
      left join public.profile_private pp on pp.user_id = l.user_id
      left join auth.users u on u.id = l.user_id
      left join lateral (
        select c.make, c.model from public.cars c
        where c.owner_id = l.user_id
        order by (c.id = k.car_id) desc nulls last, c.is_default desc nulls last, c.created_at
        limit 1
      ) car on true
      where l.exhibitor_id = p_exhibitor
    ) r
  ), '[]'::json);
end;
$$;

-- Members: booths holding my contact at an event (I can delete the row; RLS).
create or replace function public.my_event_leads(p_event uuid)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', l.id, 'exhibitor_id', x.id, 'exhibitor_name', x.name, 'booths', x.booths, 'created_at', l.created_at)
                           order by l.created_at desc), '[]'::json)
  from public.event_leads l join public.event_exhibitors x on x.id = l.exhibitor_id
  where x.event_id = p_event and l.user_id = auth.uid();
$$;

-- ------------------------------------------------------------- grants ---

-- Helpers: only the RPCs above call them.
revoke execute on function public.expo_member_car(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.booth_freebie_left(uuid) from public, anon, authenticated;
revoke execute on function public.booth_freebie_state(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.collect_booth_stamp(uuid, text, float8, float8) from public, anon;
revoke execute on function public.redeem_booth_freebie(uuid) from public, anon;
revoke execute on function public.redeem_rally_reward(uuid) from public, anon;
revoke execute on function public.my_stamps(uuid) from public, anon;
revoke execute on function public.exhibitor_extras(uuid) from public, anon;
revoke execute on function public.booth_setup_list(uuid) from public, anon;
revoke execute on function public.set_booth_stamp(uuid, boolean, text, int) from public, anon;
revoke execute on function public.set_stamp_rally(uuid, int, text) from public, anon;
revoke execute on function public.add_exhibitor_staff(uuid, text) from public, anon;
revoke execute on function public.remove_exhibitor_staff(uuid, uuid) from public, anon;
revoke execute on function public.rotate_booth_code(uuid) from public, anon;
revoke execute on function public.my_staff_booths(uuid) from public, anon;
revoke execute on function public.save_lead_by_pass(uuid, text, uuid) from public, anon;
revoke execute on function public.exhibitor_leads(uuid) from public, anon;
revoke execute on function public.my_event_leads(uuid) from public, anon;

grant execute on function public.collect_booth_stamp(uuid, text, float8, float8) to authenticated;
grant execute on function public.redeem_booth_freebie(uuid) to authenticated;
grant execute on function public.redeem_rally_reward(uuid) to authenticated;
grant execute on function public.my_stamps(uuid) to authenticated;
grant execute on function public.exhibitor_extras(uuid) to authenticated;
grant execute on function public.booth_setup_list(uuid) to authenticated;
grant execute on function public.set_booth_stamp(uuid, boolean, text, int) to authenticated;
grant execute on function public.set_stamp_rally(uuid, int, text) to authenticated;
grant execute on function public.add_exhibitor_staff(uuid, text) to authenticated;
grant execute on function public.remove_exhibitor_staff(uuid, uuid) to authenticated;
grant execute on function public.rotate_booth_code(uuid) to authenticated;
grant execute on function public.my_staff_booths(uuid) to authenticated;
grant execute on function public.save_lead_by_pass(uuid, text, uuid) to authenticated;
grant execute on function public.exhibitor_leads(uuid) to authenticated;
grant execute on function public.my_event_leads(uuid) to authenticated;
