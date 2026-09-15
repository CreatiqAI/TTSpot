-- =============================================================================
-- Map v2: cars as markers, "who can see me" with a nearby radius, TT now with
-- minutes + invitees, meet addresses.
-- =============================================================================

-- ------------------------------------------------------------- car colour ---
alter table public.cars add column color text
  check (color is null or color in ('red','black','white','grey','silver','blue','yellow','green','orange'));

-- ------------------------------------------------------------ share mode ---
alter table public.user_locations
  add column share_mode     text not null default 'friends' check (share_mode in ('friends','nearby','ghost')),
  add column share_radius_m int  not null default 2000 check (share_radius_m between 500 and 3000);
update public.user_locations set share_mode = 'ghost' where ghost;

create or replace function public.set_share_mode(p_mode text, p_radius int default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_mode not in ('friends','nearby','ghost') then raise exception 'Unknown mode'; end if;
  insert into public.user_locations (user_id, lat, lng, ghost, share_mode, share_radius_m, expires_at)
  values (auth.uid(), 3.1390, 101.6869, p_mode = 'ghost', p_mode, coalesce(p_radius, 2000), now())
  on conflict (user_id) do update
    set ghost = excluded.ghost, share_mode = excluded.share_mode,
        share_radius_m = coalesce(p_radius, public.user_locations.share_radius_m);
end;
$$;

-- Keep the old ghost switch working (it just sets the mode).
create or replace function public.set_ghost(p_ghost boolean) returns void
language sql security definer set search_path = public as $$
  select public.set_share_mode(case when p_ghost then 'ghost' else 'friends' end);
$$;

-- ------------------------------------------------------------ pins v2 ---
-- Friends + clubmates as before, plus nearby strangers when BOTH sides are in
-- 'nearby' mode and the stranger is inside their own radius of me. Strangers
-- come back at a rounded position (~100 m) with no avatar.
drop function if exists public.visible_pins();
create function public.visible_pins()
returns table (user_id uuid, lat float8, lng float8, heading float8, accuracy float8, ghost boolean, place_id uuid, event_id uuid,
               updated_at timestamptz, profiles json, places json, events json, via text, club_name text,
               car_make text, car_model text, car_color text)
language sql stable security definer set search_path = public as $$
  with me as (select l.lat, l.lng, l.share_mode from public.user_locations l where l.user_id = auth.uid())
  select l.user_id,
         case when v.via = 'nearby' then round(l.lat::numeric, 3)::float8 else l.lat end,
         case when v.via = 'nearby' then round(l.lng::numeric, 3)::float8 else l.lng end,
         l.heading, l.accuracy, l.ghost,
         case when v.via = 'nearby' then null else l.place_id end,
         case when v.via = 'nearby' then null else l.event_id end,
         l.updated_at,
         json_build_object('id', pr.id, 'username', pr.username, 'display_name', case when v.via = 'nearby' then null else pr.display_name end,
                           'bio', null, 'avatar_url', case when v.via = 'nearby' then null else pr.avatar_url end,
                           'home_state', pr.home_state, 'created_at', pr.created_at),
         case when p.id is null or v.via = 'nearby' then null else json_build_object('name', p.name) end,
         case when e.id is null or v.via = 'nearby' then null else json_build_object('title', e.title) end,
         v.via,
         (select c.name from public.club_members a join public.club_members b on b.club_id = a.club_id join public.clubs c on c.id = a.club_id
           where a.user_id = auth.uid() and b.user_id = l.user_id and b.share_location limit 1),
         car.make, car.model, car.color
  from public.user_locations l
  join public.profiles pr on pr.id = l.user_id
  left join public.places p on p.id = l.place_id
  left join public.events e on e.id = l.event_id
  left join lateral (select c.make, c.model, c.color from public.cars c where c.owner_id = l.user_id order by c.created_at limit 1) car on true
  cross join lateral (
    select case
      when public.is_friend(auth.uid(), l.user_id) then 'friend'
      when public.is_clubmate_sharing(auth.uid(), l.user_id) then 'club'
      when l.share_mode = 'nearby'
        and (select share_mode from me) = 'nearby'
        and public.metres_between((select lat from me), (select lng from me), l.lat, l.lng) <= l.share_radius_m
        and not exists (select 1 from public.blocks b where (b.blocker_id = auth.uid() and b.blocked_id = l.user_id) or (b.blocker_id = l.user_id and b.blocked_id = auth.uid()))
        then 'nearby'
      else null end as via
  ) v
  where l.user_id <> auth.uid() and not l.ghost and l.expires_at > now() and v.via is not null
  order by l.updated_at desc;
$$;

-- ------------------------------------------------------- meet address ---
alter table public.events add column address text;

-- --------------------------------------------------- TT now, minutes ---
drop function if exists public.tt_now(float8, float8, text, text, int);
create or replace function public.tt_now(p_lat float8, p_lng float8, p_venue text default null, p_title text default null,
                                         p_minutes int default 60, p_invitees uuid[] default null, p_address text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me       uuid := auth.uid();
  v_place  public.places;
  v_venue  text;
  v_title  text;
  v_id     uuid;
  f        uuid;
  v_mins   int := greatest(15, least(coalesce(p_minutes, 60), 480));
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

  insert into public.events (organizer_id, title, event_type, starts_at, ends_at, venue_name, lat, lng, is_instant, place_id, address, visibility)
  values (me, v_title, 'tt', now(), now() + make_interval(mins => v_mins), left(v_venue, 80), p_lat, p_lng, true, v_place.id, nullif(trim(p_address), ''), 'friends')
  returning id into v_id;

  insert into public.event_attendees (event_id, user_id) values (v_id, me) on conflict do nothing;
  insert into public.checkins (event_id, user_id, lat, lng, source) values (v_id, me, p_lat, p_lng, 'organizer') on conflict do nothing;

  if p_invitees is null then
    for f in select * from public.friend_ids(me) loop
      perform public.notify(f, me, 'tt_now', p_event => v_id, p_body => v_venue);
    end loop;
  else
    foreach f in array p_invitees loop
      if public.is_friend(me, f) then
        insert into public.event_attendees (event_id, user_id) values (v_id, f) on conflict do nothing;
        perform public.notify(f, me, 'tt_now', p_event => v_id, p_body => v_venue);
      end if;
    end loop;
  end if;
  return v_id;
end;
$$;

-- Invitees are RSVP'd so the meet chat exists for them; being invited is not being there.
-- (Check-ins stay location-verified.)
