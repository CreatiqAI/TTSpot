-- =============================================================================
-- Map: friends' pins carry their default car's cover (AI portrait, else the
-- first photo) so the map can draw them as a portrait badge instead of a
-- generic top-down car. The car shown is now the default car, not the oldest.
-- Same visibility rules as 0019; only the car columns changed.
-- =============================================================================
drop function if exists public.visible_pins();
create function public.visible_pins()
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
                       from public.cars c where c.owner_id = l.user_id order by c.is_default desc, c.created_at limit 1) car on true
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
