-- =============================================================================
-- AI car portraits (Kie.ai, GPT Image 2 image-to-image, 1K)
--   A member picks a style for one of their cars; the `car-portrait` Edge
--   Function creates the Kie task and Kie calls the same function back when
--   the image is done. The row below tracks that job: pending → ready | failed.
--   Limits live in the RPC (one pending per car, N requests per car per day,
--   N = platform_settings.portrait_daily_limit). The Edge Function updates the
--   status with the service role; members only ever read their own rows and
--   pick which ready portrait fronts the car (cars.portrait_url).
-- =============================================================================

-- ------------------------------------------------------------ settings ---
insert into public.platform_settings (key, value, description) values
  ('portrait_daily_limit', '3', 'AI portrait requests allowed per car in a rolling 24 hours (each one costs Kie credits).')
on conflict (key) do nothing;

-- --------------------------------------------------------------- table ---
create table public.car_portraits (
  id          uuid primary key default gen_random_uuid(),
  car_id      uuid not null references public.cars (id) on delete cascade,
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  style       text not null check (style in ('showroom', 'night_city', 'golden_hour', 'race_poster', 'pastel_dream', 'film', 'track_day', 'line_art')),
  status      text not null default 'pending' check (status in ('pending', 'ready', 'failed')),
  task_id     text,                                   -- Kie taskId once created
  url         text,                                   -- public storage URL when ready
  error       text,                                   -- why it failed (shown to the member)
  created_at  timestamptz not null default now(),
  ready_at    timestamptz
);
create index car_portraits_car_idx on public.car_portraits (car_id, created_at desc);
create index car_portraits_owner_idx on public.car_portraits (owner_id, created_at desc);

alter table public.car_portraits enable row level security;
create policy "car_portraits: owner can read"
  on public.car_portraits for select to authenticated using (owner_id = auth.uid());
-- No insert/update policies on purpose: writes go through the RPCs below and
-- the Edge Function (service role).

-- The app listens for status changes on the car page.
alter publication supabase_realtime add table public.car_portraits;

-- ---------------------------------------------------------------- RPCs ---

-- Books a portrait job for one of my cars. Returns the new row id; the Edge
-- Function then creates the Kie task and fills task_id.
create or replace function public.request_car_portrait(p_car uuid, p_style text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_owner uuid;
  v_photos text[];
  v_limit int := greatest(0, public.setting_num('portrait_daily_limit', 3)::int);
  v_used int;
  v_id uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
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

-- Makes a ready portrait the car's picture (garage card, map, meets).
create or replace function public.choose_car_portrait(p_portrait uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_car uuid;
  v_url text;
  v_status text;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select car_id, url, status into v_car, v_url, v_status from public.car_portraits where id = p_portrait and owner_id = me;
  if v_car is null then raise exception 'Portrait not found'; end if;
  if v_status <> 'ready' or v_url is null then raise exception 'That portrait is not ready yet'; end if;
  update public.cars set portrait_url = v_url where id = v_car and owner_id = me;
end;
$$;
