-- =============================================================================
-- Toy car garage: one die-cast toy render per car, made from its cover photo
--   Every car gets one toy automatically (free, no points): when the car is
--   saved at sign-up or added later, and again when the cover photo changes.
--   Kie (GPT Image 2 image-to-image, 1K, transparent) takes 1-3 minutes, so
--   nothing waits: cars.toy_status goes pending → ready and the app swaps the
--   toy in when it lands.
--
--   cars.toy_url        the cleaned PNG (public car-photos/<uid>/toys/<car>/<ts>.png)
--   cars.toy_status     null (never asked) | 'pending' | 'ready' | 'failed'
--   cars.toy_source     the cover photo URL the toy was made from; a different
--                       cover means the toy is stale (still shown until the
--                       new one is ready)
--   cars.toy_task       the car_toy_jobs row being painted / last painted
--
--   car_toy_jobs        one row per render: the 24 h cap, the Kie task id,
--                       and what the callback checks before it writes the car.
--
-- Flow: request_car_toy(car) [RPC, or the triggers below] → job row +
--   toy_status 'pending' + pg_net POST to the `car-toy` Edge Function
--   (header x-toy-secret) → the function creates the Kie task (retrying 429s)
--   → Kie calls the function back → it cleans the PNG, stores it, marks the
--   job ready and the car too, unless a newer cover/job took over (then the
--   job is 'stale'). toy_sweep() every minute re-posts jobs that never got a
--   task id, asks the function to poll Kie for jobs whose callback never
--   came, and fails jobs older than 15 minutes.
--
-- Members cannot write toy_* themselves (cars_toy_guard): only the RPC and
-- the function (service role) do, so a toy_url always points at our render.
--
-- Vault (set once, out of band; never in a migration):
--   select vault.create_secret('<random>', 'toy_hook_secret');
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/car-toy', 'toy_hook_url');
-- The same random value is the function secret TOY_HOOK_SECRET.
-- =============================================================================

create extension if not exists pg_net;

-- ------------------------------------------------------------- columns ---
alter table public.cars
  add column if not exists toy_url text,
  add column if not exists toy_status text,
  add column if not exists toy_source text,
  add column if not exists toy_task uuid,
  add column if not exists toy_ready_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'cars_toy_status_check') then
    alter table public.cars add constraint cars_toy_status_check check (toy_status in ('pending', 'ready', 'failed'));
  end if;
end $$;

comment on column public.cars.toy_url is 'Die-cast toy render of the car (transparent PNG), made by the car-toy function from the cover photo.';
comment on column public.cars.toy_status is 'null: never asked | pending | ready | failed. Written only by request_car_toy and the car-toy function.';
comment on column public.cars.toy_source is 'Cover photo URL the toy was made from; a different cover makes it stale.';
comment on column public.cars.toy_task is 'car_toy_jobs.id of the render in progress or last finished.';

-- ---------------------------------------------------------------- jobs ---
create table if not exists public.car_toy_jobs (
  id          uuid primary key default gen_random_uuid(),
  car_id      uuid not null references public.cars (id) on delete cascade,
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  source      text not null,                             -- cover photo URL sent to Kie
  status      text not null default 'pending' check (status in ('pending', 'ready', 'failed', 'stale')),
  task_id     text,                                      -- Kie taskId once created
  url         text,                                      -- the cleaned PNG when ready
  error       text,
  attempts    int not null default 0,                    -- pg_net posts so far
  manual      boolean not null default false,            -- "Remake" vs automatic
  created_at  timestamptz not null default now(),
  posted_at   timestamptz,                               -- last pg_net post
  ready_at    timestamptz
);
create index if not exists car_toy_jobs_car_idx on public.car_toy_jobs (car_id, created_at desc);
create index if not exists car_toy_jobs_pending_idx on public.car_toy_jobs (created_at) where status = 'pending';

alter table public.car_toy_jobs enable row level security;
drop policy if exists "car_toy_jobs: owner can read" on public.car_toy_jobs;
create policy "car_toy_jobs: owner can read"
  on public.car_toy_jobs for select to authenticated using (owner_id = auth.uid());
-- No insert/update policies: the RPC and the function (service role) write.

insert into public.platform_settings (key, value, description) values
  ('toy_daily_limit', '3', 'Toy renders allowed per car in a rolling 24 hours (each one costs Kie credits).'),
  ('toys_enabled', 'true', 'Make a die-cast toy of every car from its cover photo (false: stop asking Kie; existing toys stay).')
on conflict (key) do nothing;

-- The garage listens for toy_status flips on the owner's own cars.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cars') then
    alter publication supabase_realtime add table public.cars;
  end if;
end $$;

-- --------------------------------------------------------------- guard ---
-- A member's own update (cars RLS lets the owner update any column) must not
-- touch toy_*; the RPC sets ttspot.toy_writer for its own write, the function
-- runs as service_role (auth.uid() null).
create or replace function public.cars_toy_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and coalesce(current_setting('ttspot.toy_writer', true), '') <> '1' then
    if tg_op = 'INSERT' then
      new.toy_url := null; new.toy_status := null; new.toy_source := null; new.toy_task := null; new.toy_ready_at := null;
    else
      new.toy_url := old.toy_url; new.toy_status := old.toy_status; new.toy_source := old.toy_source;
      new.toy_task := old.toy_task; new.toy_ready_at := old.toy_ready_at;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists cars_toy_guard on public.cars;
create trigger cars_toy_guard before insert or update on public.cars
  for each row execute function public.cars_toy_guard();

-- ---------------------------------------------------------------- hook ---
-- Posts { jobId } to the function. Never raises: a lost post is picked up
-- by toy_sweep().
create or replace function public.toy_post(p_job uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
  v_url text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'toy_hook_secret';
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'toy_hook_url';
  update public.car_toy_jobs set attempts = attempts + 1, posted_at = now() where id = p_job;
  if v_secret is null or v_url is null then
    raise warning 'toy_post %: toy_hook_secret / toy_hook_url not set', p_job;
    return;
  end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('jobId', p_job),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-toy-secret', v_secret),
    timeout_milliseconds := 30000
  );
exception when others then
  raise warning 'toy_post %: %', p_job, sqlerrm;
end;
$$;
revoke execute on function public.toy_post(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- book ---
-- Books a toy render for a car. p_manual = "Remake" (skips the same-cover
-- short-cut, still capped). p_quiet: the automatic path, which returns null
-- instead of raising when nothing should happen. Returns the job id, or
-- null when nothing was booked (toys off, no photo, same cover already
-- done, one still pending, cap reached).
create or replace function public.toy_book(p_car uuid, p_manual boolean, p_quiet boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
  v_photos text[];
  v_source text;
  v_status text;
  v_toy_source text;
  v_limit int := greatest(0, public.setting_num('toy_daily_limit', 3)::int);
  v_used int;
  v_id uuid;
begin
  if coalesce((select value #>> '{}' from public.platform_settings where key = 'toys_enabled'), 'true') not in ('true', '1', 'on') then
    if p_quiet then return null; end if;
    raise exception 'Toys are taking a break. Try again later.';
  end if;
  select owner_id, photo_urls, toy_status, toy_source into v_owner, v_photos, v_status, v_toy_source
    from public.cars where id = p_car for update;
  if v_owner is null then
    if p_quiet then return null; end if;
    raise exception 'Car not found';
  end if;
  v_source := case when coalesce(array_length(v_photos, 1), 0) > 0 then v_photos[1] end;
  if v_source is null or v_source not like 'http%' then
    if p_quiet then return null; end if;
    raise exception 'Add a photo of the car first';
  end if;

  -- A job that never came back must not block the car forever.
  update public.car_toy_jobs set status = 'failed', error = 'Timed out'
   where car_id = p_car and status = 'pending' and created_at < now() - interval '15 minutes';

  if v_status = 'ready' and v_toy_source = v_source and not p_manual then return null; end if;
  if exists (select 1 from public.car_toy_jobs where car_id = p_car and status = 'pending') then
    if p_quiet then return null; end if;
    raise exception 'The toy is still being made. Give it a minute.';
  end if;
  select count(*) into v_used from public.car_toy_jobs where car_id = p_car and created_at > now() - interval '24 hours';
  if v_used >= v_limit then
    if p_quiet then return null; end if;
    raise exception 'That''s % toys for this car today. Try again tomorrow.', v_limit;
  end if;

  insert into public.car_toy_jobs (car_id, owner_id, source, manual) values (p_car, v_owner, v_source, p_manual) returning id into v_id;
  perform set_config('ttspot.toy_writer', '1', true);
  update public.cars set toy_status = 'pending', toy_task = v_id where id = p_car;
  perform set_config('ttspot.toy_writer', '', true);
  perform public.toy_post(v_id);
  return v_id;
end;
$$;
revoke execute on function public.toy_book(uuid, boolean, boolean) from public, anon, authenticated;

-- The app's entry point (lazy backfill when a garage opens, and "Remake").
-- Owner only. Returns the job id, or null when there was nothing to do.
create or replace function public.request_car_toy(p_car uuid, p_manual boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_owner uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select owner_id into v_owner from public.cars where id = p_car;
  if v_owner is null or v_owner <> me then raise exception 'That car is not in your garage'; end if;
  return public.toy_book(p_car, p_manual, not p_manual);
end;
$$;
revoke execute on function public.request_car_toy(uuid, boolean) from public, anon;
grant execute on function public.request_car_toy(uuid, boolean) to authenticated;

-- ------------------------------------------------------------ triggers ---
-- A new car with a photo, or a car whose cover changed: book a toy. AFTER
-- triggers so the job row can reference the car; the app re-reads the car
-- after saving anyway.
create or replace function public.on_car_toy_auto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and coalesce(new.photo_urls[1], '') = coalesce(old.photo_urls[1], '') then return null; end if;
  perform public.toy_book(new.id, false, true);
  return null;
exception when others then
  raise warning 'on_car_toy_auto %: %', new.id, sqlerrm;
  return null;
end;
$$;
drop trigger if exists cars_toy_auto_insert on public.cars;
create trigger cars_toy_auto_insert after insert on public.cars
  for each row execute function public.on_car_toy_auto();
drop trigger if exists cars_toy_auto_update on public.cars;
create trigger cars_toy_auto_update after update of photo_urls on public.cars
  for each row execute function public.on_car_toy_auto();

-- ---------------------------------------------------------------- sweep ---
-- Every minute. Lost posts are re-posted (3 tries), jobs whose callback never
-- came get polled by the function, and anything older than 15 minutes fails.
create or replace function public.toy_sweep() returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select id, car_id from public.car_toy_jobs
     where status = 'pending' and created_at < now() - interval '15 minutes'
  loop
    update public.car_toy_jobs set status = 'failed', error = coalesce(error, 'Timed out') where id = r.id;
    update public.cars set toy_status = 'failed' where id = r.car_id and toy_task = r.id;
    n := n + 1;
  end loop;
  for r in
    select id from public.car_toy_jobs
     where status = 'pending'
       and ((task_id is null and attempts < 3 and coalesce(posted_at, created_at) < now() - interval '90 seconds')
         or (task_id is not null and coalesce(posted_at, created_at) < now() - interval '3 minutes'))
     limit 20
  loop
    perform public.toy_post(r.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke execute on function public.toy_sweep() from public, anon, authenticated;

do $outer$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'ttspot-toy-sweep';
    perform cron.schedule('ttspot-toy-sweep', '* * * * *', 'select public.toy_sweep()');
  else
    raise notice 'pg_cron not available: run toy_sweep() every minute some other way';
  end if;
end;
$outer$;
