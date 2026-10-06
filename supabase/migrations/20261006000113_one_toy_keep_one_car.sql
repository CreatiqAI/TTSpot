-- 0113 one_toy_keep_one_car (owner decisions 2026-10-06):
-- 1. One toy per car. toy_book refuses any render once the car has a toy, so
--    a new paint colour, "Remake" or a new cover photo no longer spends Kie
--    credits. A car's first toy is still made automatically (insert, or the
--    first photo), and a failed first toy can be retried.
-- 2. Every member keeps at least one car: deleting your last car is refused.
--    Account deletion and service-role/admin deletes are not affected.

CREATE OR REPLACE FUNCTION public.toy_book(p_car uuid, p_manual boolean, p_quiet boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
  v_photos text[];
  v_color text;
  v_source text;
  v_paint text;
  v_status text;
  v_toy_source text;
  v_toy_color text;
  v_toy_url text;
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
  select owner_id, photo_urls, color, toy_status, toy_source, toy_color, toy_url
    into v_owner, v_photos, v_color, v_status, v_toy_source, v_toy_color, v_toy_url
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

  -- One toy per car (owner decision 2026-10-06): once a car has its toy it is
  -- never rendered again: no repaint, no remake, no new render for a new
  -- cover. A different toy means adding another car. A first toy that failed
  -- (no toy_url yet) can still be retried.
  if v_toy_url is not null then
    if p_quiet then return null; end if;
    raise exception 'This car already has its toy car.';
  end if;

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
$function$;
revoke execute on function public.toy_book(uuid, boolean, boolean) from public, anon, authenticated;

create or replace function public.cars_keep_one() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and auth.uid() = old.owner_id
     and coalesce(current_setting('ttspot.deleting_account', true), '') <> 'on'
     and exists (select 1 from public.profiles where id = old.owner_id)
     and (select count(*) from public.cars where owner_id = old.owner_id) <= 1 then
    raise exception 'Your garage needs at least one car. Add another car before removing this one.';
  end if;
  return old;
end;
$$;
drop trigger if exists cars_keep_one on public.cars;
create trigger cars_keep_one before delete on public.cars
  for each row execute function public.cars_keep_one();

create or replace function public.delete_my_account()
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  perform set_config('ttspot.deleting_account', 'on', true);
  delete from public.profiles where id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$function$;
