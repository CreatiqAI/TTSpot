-- AI car portraits are opt-in per member, and for now the whole feature is
-- off for members. Admins can still paint (to try styles and tune prompts)
-- and can flip `portraits_enabled` in Settings when the renders are good
-- enough: every entry point in the app reads this flag.
insert into public.platform_settings (key, value, description) values
  ('portraits_enabled', 'false', 'Let members make AI car portraits (Kie). Off = only admins see the AI portrait buttons.')
on conflict (key) do nothing;

create or replace function public.request_car_portrait(p_car uuid, p_style text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_owner uuid;
  v_photos text[];
  v_limit int := greatest(0, public.setting_num('portrait_daily_limit', 3)::int);
  v_used int;
  v_id uuid;
  v_open boolean := coalesce((select value #>> '{}' from public.platform_settings where key = 'portraits_enabled'), 'false') in ('true', '1', 'on');
begin
  if me is null then raise exception 'Sign in first'; end if;
  if not v_open and not public.is_admin(me) then raise exception 'AI portraits are not open yet.'; end if;
  select owner_id, photo_urls into v_owner, v_photos from public.cars where id = p_car;
  if v_owner is null or v_owner <> me then raise exception 'That car is not in your garage'; end if;
  if coalesce(array_length(v_photos, 1), 0) = 0 then raise exception 'Add a photo of the car first'; end if;
  if p_style is null or p_style not in ('showroom', 'night_city', 'golden_hour', 'race_poster', 'pastel_dream', 'film', 'track_day', 'line_art') then
    raise exception 'Pick a style';
  end if;

  -- A job that never came back (Kie down, callback lost) must not block the car forever.
  update public.car_portraits set status = 'failed', error = 'Timed out. Try again.'
   where car_id = p_car and status = 'pending' and created_at < now() - interval '15 minutes';

  if exists (select 1 from public.car_portraits where car_id = p_car and status = 'pending') then
    raise exception 'A portrait of this car is still being painted. Give it a minute.';
  end if;

  select count(*) into v_used from public.car_portraits
   where car_id = p_car and created_at > now() - interval '24 hours';
  if v_used >= v_limit then
    raise exception 'That''s % portraits for this car today. Try again tomorrow.', v_limit;
  end if;

  insert into public.car_portraits (car_id, owner_id, style) values (p_car, me, p_style) returning id into v_id;
  return v_id;
end;
$$;
