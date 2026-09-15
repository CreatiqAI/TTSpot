-- =============================================================================
-- Map visibility: add 'public' (everyone, no radius). Nearby / public cars are
-- visible to any signed-in member (not only mutual), at a rounded position.
-- =============================================================================
alter table public.user_locations drop constraint if exists user_locations_share_mode_check;
alter table public.user_locations add constraint user_locations_share_mode_check
  check (share_mode in ('friends','nearby','public','ghost'));

create or replace function public.set_share_mode(p_mode text, p_radius int default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_mode not in ('friends','nearby','public','ghost') then raise exception 'Unknown mode'; end if;
  insert into public.user_locations (user_id, lat, lng, ghost, share_mode, share_radius_m, expires_at)
  values (auth.uid(), 3.1390, 101.6869, p_mode = 'ghost', p_mode, coalesce(p_radius, 2000), now())
  on conflict (user_id) do update
    set ghost = excluded.ghost, share_mode = excluded.share_mode,
        share_radius_m = coalesce(p_radius, public.user_locations.share_radius_m);
end;
$$;

drop function if exists public.visible_pins();
create function public.visible_pins()
returns table (user_id uuid, lat float8, lng float8, heading float8, accuracy float8, ghost boolean, place_id uuid, event_id uuid,
               updated_at timestamptz, profiles json, places json, events json, via text, club_name text,
               car_make text, car_model text, car_color text)
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
