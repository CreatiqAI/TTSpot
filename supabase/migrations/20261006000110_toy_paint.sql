-- =============================================================================
-- 0110 toy_paint: the car's colour repaints its toy
--   The owner asked what "Colour on the map" was for: picking a colour changed
--   nothing they could see. The field is now "Paint colour" and it repaints the
--   die-cast toy (0106): the toy is rendered from the cover photo in the car's
--   chosen paint, and a new colour books a new render, like a new cover does.
--
--   cars.color            the paint the member chose (one of the nine map
--                         colours) or null: match the photo, as before
--   cars.toy_color        the paint the current toy was made in (null: matched
--                         the photo). Written only by the car-toy function.
--   car_toy_jobs.paint    the paint a job renders (null: match the photo)
--
--   A toy is "done" for a car when it is ready for the current cover AND the
--   current paint. toy_book() compares both; the update trigger now also fires
--   on `color`. A job still painting an older cover or colour is superseded
--   (marked stale, its callback is ignored) when the cap allows a new one;
--   otherwise it finishes and the app asks again once the cap frees up.
--
--   Existing toys: toy_color := the car's current colour, so nothing is
--   re-rendered by this migration (no member's colour or toy changes).
--
--   car_toy_quota(car)    owner only: renders used / left in the rolling 24 h
--                         and when the next one frees up, for the edit form
--                         ("3 toy renders a day per car").
-- =============================================================================

-- ------------------------------------------------------------- columns ---
alter table public.cars add column if not exists toy_color text;
comment on column public.cars.toy_color is 'Paint key the current toy was rendered in (null: matched the photo). Written only by the car-toy function.';

alter table public.car_toy_jobs add column if not exists paint text;
comment on column public.car_toy_jobs.paint is 'Paint key this render uses (null: keep the colour of the photo).';

-- The nine paints (kCarColors in the app). Anything else (null, '', 'auto',
-- an old value) means "match the photo".
create or replace function public.toy_paint_key(p text) returns text
language sql immutable as $$
  select case when lower(btrim(coalesce(p, ''))) in ('red', 'black', 'white', 'grey', 'silver', 'blue', 'yellow', 'green', 'orange')
              then lower(btrim(p)) end
$$;

-- ------------------------------------------------------------ backfill ---
-- Every toy so far was made from the photo, whose colour is what the car's
-- colour says (recogniser + member). Recording that as the toy's paint keeps
-- every existing toy "done": no re-render, no colour change for anyone.
-- (Runs as the migration role: the guard below lets it through.)
update public.cars
   set toy_color = public.toy_paint_key(color)
 where toy_status is not null
   and toy_color is distinct from public.toy_paint_key(color);

update public.car_toy_jobs j
   set paint = public.toy_paint_key(c.color)
  from public.cars c
 where c.id = j.car_id and j.status = 'pending' and j.paint is null;

-- --------------------------------------------------------------- guard ---
-- Members still cannot write toy_*; toy_color joins the list.
create or replace function public.cars_toy_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and coalesce(current_setting('ttspot.toy_writer', true), '') <> '1' then
    if tg_op = 'INSERT' then
      new.toy_url := null; new.toy_status := null; new.toy_source := null; new.toy_task := null; new.toy_ready_at := null;
      new.toy_color := null;
    else
      new.toy_url := old.toy_url; new.toy_status := old.toy_status; new.toy_source := old.toy_source;
      new.toy_task := old.toy_task; new.toy_ready_at := old.toy_ready_at; new.toy_color := old.toy_color;
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------- book ---
-- As 0106, plus the paint: the job carries the car's paint, "already done"
-- needs the same cover AND the same paint, and a job still painting an older
-- cover or colour gives way to the new one when the cap allows. The cap
-- message says when the next render frees up (Malaysia time).
create or replace function public.toy_book(p_car uuid, p_manual boolean, p_quiet boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
  v_photos text[];
  v_color text;
  v_source text;
  v_paint text;
  v_status text;
  v_toy_source text;
  v_toy_color text;
  v_limit int := greatest(0, public.setting_num('toy_daily_limit', 3)::int);
  v_used int;
  v_oldest timestamptz;
  v_next timestamptz;
  v_pending record;
  v_id uuid;
begin
  if coalesce((select value #>> '{}' from public.platform_settings where key = 'toys_enabled'), 'true') not in ('true', '1', 'on') then
    if p_quiet then return null; end if;
    raise exception 'Toys are taking a break. Try again later.';
  end if;
  select owner_id, photo_urls, color, toy_status, toy_source, toy_color
    into v_owner, v_photos, v_color, v_status, v_toy_source, v_toy_color
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
  v_paint := public.toy_paint_key(v_color);

  -- A job that never came back must not block the car forever.
  update public.car_toy_jobs set status = 'failed', error = 'Timed out'
   where car_id = p_car and status = 'pending' and created_at < now() - interval '15 minutes';

  -- Already made for this cover in this paint.
  if v_status = 'ready' and v_toy_source = v_source and v_toy_color is not distinct from v_paint and not p_manual then
    return null;
  end if;

  select id, source, paint into v_pending
    from public.car_toy_jobs where car_id = p_car and status = 'pending'
   order by created_at desc limit 1;
  if v_pending.id is not null and v_pending.source = v_source and v_pending.paint is not distinct from v_paint then
    if p_quiet then return null; end if;
    raise exception 'The toy is still being made. Give it a minute.';
  end if;

  select count(*), min(created_at) into v_used, v_oldest
    from public.car_toy_jobs where car_id = p_car and created_at > now() - interval '24 hours';
  if v_used >= v_limit then
    if p_quiet then return null; end if;
    v_next := v_oldest + interval '24 hours';
    raise exception 'That''s % toy cars for this car in a day. The next one can start after % %.',
      v_limit,
      to_char(v_next at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MI AM'),
      case when (v_next at time zone 'Asia/Kuala_Lumpur')::date = (now() at time zone 'Asia/Kuala_Lumpur')::date then 'today' else 'tomorrow' end;
  end if;

  -- A render of an older cover or colour gives way (its callback is ignored).
  if v_pending.id is not null then
    update public.car_toy_jobs set status = 'stale', error = 'Superseded by a newer cover or paint'
     where id = v_pending.id and status = 'pending';
  end if;

  insert into public.car_toy_jobs (car_id, owner_id, source, paint, manual)
  values (p_car, v_owner, v_source, v_paint, p_manual) returning id into v_id;
  perform set_config('ttspot.toy_writer', '1', true);
  update public.cars set toy_status = 'pending', toy_task = v_id where id = p_car;
  perform set_config('ttspot.toy_writer', '', true);
  perform public.toy_post(v_id);
  return v_id;
end;
$$;
revoke execute on function public.toy_book(uuid, boolean, boolean) from public, anon, authenticated;

-- ------------------------------------------------------------ triggers ---
-- A new car with a photo, or a car whose cover or paint changed: book a toy.
create or replace function public.on_car_toy_auto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE'
     and coalesce(new.photo_urls[1], '') = coalesce(old.photo_urls[1], '')
     and public.toy_paint_key(new.color) is not distinct from public.toy_paint_key(old.color) then
    return null;
  end if;
  perform public.toy_book(new.id, false, true);
  return null;
exception when others then
  raise warning 'on_car_toy_auto %: %', new.id, sqlerrm;
  return null;
end;
$$;
drop trigger if exists cars_toy_auto_update on public.cars;
create trigger cars_toy_auto_update after update of photo_urls, color on public.cars
  for each row execute function public.on_car_toy_auto();

-- --------------------------------------------------------------- quota ---
-- For the owner's edit form: how many renders this car has left in the
-- rolling 24 hours and when the next one frees up.
create or replace function public.car_toy_quota(p_car uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_owner uuid;
  v_limit int := greatest(0, public.setting_num('toy_daily_limit', 3)::int);
  v_used int;
  v_oldest timestamptz;
  v_pending boolean;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select owner_id into v_owner from public.cars where id = p_car;
  if v_owner is null or v_owner <> me then raise exception 'That car is not in your garage'; end if;
  select count(*), min(created_at) into v_used, v_oldest
    from public.car_toy_jobs where car_id = p_car and created_at > now() - interval '24 hours';
  select exists (select 1 from public.car_toy_jobs where car_id = p_car and status = 'pending' and created_at > now() - interval '15 minutes')
    into v_pending;
  return jsonb_build_object(
    'limit', v_limit,
    'used', v_used,
    'left', greatest(0, v_limit - v_used),
    'next_at', case when v_used >= v_limit then v_oldest + interval '24 hours' end,
    'pending', v_pending,
    'enabled', coalesce((select value #>> '{}' from public.platform_settings where key = 'toys_enabled'), 'true') in ('true', '1', 'on')
  );
end;
$$;
revoke execute on function public.car_toy_quota(uuid) from public, anon;
grant execute on function public.car_toy_quota(uuid) to authenticated;

-- ---------------------------------------------------------------- sweep ---
-- As 0106, plus: a paint picked while the day's renders were used up starts
-- by itself once a render frees up (toy_book stays quiet while the cap
-- holds). Ready toys only: a repaint that failed waits for "Remake".
create or replace function public.toy_sweep() returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  n int := 0;
  v_limit int := greatest(0, public.setting_num('toy_daily_limit', 3)::int);
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
  for r in
    select c.id from public.cars c
     where c.toy_status = 'ready' and c.toy_url is not null
       and c.toy_color is distinct from public.toy_paint_key(c.color)
       and not exists (select 1 from public.car_toy_jobs j where j.car_id = c.id and j.status = 'pending')
       and (select count(*) from public.car_toy_jobs j where j.car_id = c.id and j.created_at > now() - interval '24 hours') < v_limit
     limit 5
  loop
    begin
      if public.toy_book(r.id, false, true) is not null then n := n + 1; end if;
    exception when others then
      raise warning 'toy_sweep repaint %: %', r.id, sqlerrm;
    end;
  end loop;
  return n;
end;
$$;
revoke execute on function public.toy_sweep() from public, anon, authenticated;
