-- AI consent (Apple App Review 5.1.2(i)): say clearly when personal data goes
-- to a third-party AI, and get the member's OK before sending it.
--
-- The OKs live in profiles.settings.ai_consent as dates:
--   {"titi": "<iso>", "toy": "<iso>", "safety": "<iso>"}
--   titi    TiTi (edge functions titi, titi-nudge) → OpenAI
--   toy     toy car (edge function car-toy) → Kie.ai
--   safety  post / moment check (edge function moderate-content) → OpenAI;
--           a notice the app shows once before the first post (not enforced
--           here: the check itself is what keeps TT Spot safe).
--
-- This migration:
--   1. update_my_settings: `ai_consent` merges key by key, so an OK saved by
--      one screen (or by allow_toy_cars) is never wiped by a patch from a
--      phone that hadn't heard of it yet. A null value removes that key.
--   2. titi_nudge_candidates: only members with ai_consent.titi. Otherwise
--      identical to the live body (0116).
--   3. toy_consented(uuid) + toy_book: no OK for toys → nothing is booked and
--      nothing on the car changes (quiet callers get null; a manual request
--      gets a message). Cars that already have a toy keep it: one toy per car
--      (0113) means they are never rendered again anyway, so only new
--      renders need the OK. Otherwise identical to the live body (0113).
--   4. allow_toy_cars(): records ai_consent.toy for the caller server-side
--      (only ever their own) and books toys for their cars without one.
--      Returns how many were booked.

-- 1 ─────────────────────────────────────────────────── update_my_settings ──
create or replace function public.update_my_settings(p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare v jsonb;
begin
  update public.profiles
     set settings = case
       when jsonb_typeof(p_patch -> 'ai_consent') = 'object' then
         (coalesce(settings, '{}'::jsonb) || p_patch)
         || jsonb_build_object('ai_consent', jsonb_strip_nulls(
              case when jsonb_typeof(settings -> 'ai_consent') = 'object' then settings -> 'ai_consent' else '{}'::jsonb end
              || (p_patch -> 'ai_consent')))
       else coalesce(settings, '{}'::jsonb) || coalesce(p_patch, '{}'::jsonb)
     end
   where id = auth.uid()
  returning settings into v;
  return v;
end;
$function$;

-- 2 ──────────────────────────────────────────────── titi_nudge_candidates ──
create or replace function public.titi_nudge_candidates(p_slot integer, p_limit integer default 5000)
returns table(user_id uuid, last_sent_at timestamp with time zone)
language sql
stable security definer
set search_path = public
as $function$
  select p.id,
         (select max(n.sent_at) from public.titi_nudges n where n.user_id = p.id)
    from public.profiles p
   where p.suspended_at is null
     and p.username is not null
     -- Their context goes to OpenAI: only members who said OK to TiTi.
     and coalesce(p.settings -> 'ai_consent' ->> 'titi', '') <> ''
     and not public.setting_off(p.settings, 'titi_tips')
     and exists (select 1 from public.push_tokens t where t.user_id = p.id)
     and not exists (select 1 from public.titi_nudges n
                      where n.user_id = p.id and n.slot = p_slot
                        and n.day = (now() at time zone 'Asia/Kuala_Lumpur')::date)
     and (select count(*) from public.notifications x
           where x.user_id = p.id and not x.silent and x.created_at > now() - interval '24 hours') < 8
   order by p.id
   limit greatest(1, least(p_limit, 20000));
$function$;

revoke execute on function public.titi_nudge_candidates(int, int) from public, anon, authenticated;
grant execute on function public.titi_nudge_candidates(int, int) to service_role;

-- 3 ─────────────────────────────────────────────── toy_consented, toy_book ──
create or replace function public.toy_consented(p_user uuid)
returns boolean
language sql
stable security definer
set search_path = public
as $function$
  select coalesce((select settings -> 'ai_consent' ->> 'toy' from public.profiles where id = p_user), '') <> '';
$function$;

revoke execute on function public.toy_consented(uuid) from public, anon, authenticated;

create or replace function public.toy_book(p_car uuid, p_manual boolean, p_quiet boolean)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
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
  -- Apple 5.1.2(i): the car's photo goes to Kie.ai only with the owner's OK
  -- (settings.ai_consent.toy: the app's sheet, via allow_toy_cars). Without
  -- it nothing is booked and the car is left as it is.
  if not public.toy_consented(v_owner) then
    if p_quiet then return null; end if;
    raise exception 'Tap Make my toy car first to allow toy cars.';
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

-- 4 ────────────────────────────────────────────────────────── allow_toy_cars ──
create or replace function public.allow_toy_cars()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  me uuid := auth.uid();
  r record;
  n int := 0;
begin
  if me is null then raise exception 'Sign in first'; end if;
  -- The caller's own OK, dated now (an earlier date stands).
  update public.profiles
     set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('ai_consent',
           case when jsonb_typeof(settings -> 'ai_consent') = 'object' then settings -> 'ai_consent' else '{}'::jsonb end
           || jsonb_build_object('toy', coalesce(nullif(settings -> 'ai_consent' ->> 'toy', ''),
                to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))))
   where id = me;
  -- Toys for their cars that have none yet, oldest car first. Each booking
  -- is quiet: no photo, the daily cap or one already on its way just skip.
  for r in
    select id from public.cars where owner_id = me and toy_url is null order by created_at
  loop
    begin
      if public.toy_book(r.id, false, true) is not null then n := n + 1; end if;
    exception when others then
      raise warning 'allow_toy_cars %: %', r.id, sqlerrm;
    end;
  end loop;
  return n;
end;
$function$;

revoke execute on function public.allow_toy_cars() from public, anon;
grant execute on function public.allow_toy_cars() to authenticated;
