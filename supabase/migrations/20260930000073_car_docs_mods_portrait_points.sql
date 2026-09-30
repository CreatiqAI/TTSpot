-- =============================================================================
-- Car pages, part 2
--   1. car_documents: road tax (LKM), insurance, PUSPAKOM and next service for
--      one car. Owner-only, never public. A daily job pings the owner 30, 7
--      and 1 day(s) before road tax or insurance runs out ('car_doc').
--   2. car_mods grows up: category, shop (free text or a partner), one photo,
--      and a per-mod "only me" switch. Prices are the owner's business only:
--      the column is not readable by members at all, and car_mod_list() hands
--      it back to the owner alone.
--   3. AI portraits cost points (platform_settings.portrait_cost_points, 300).
--      request_car_portrait() takes them through the ledger in the same
--      transaction that books the job; a job that ends 'failed' (Kie refused
--      it, the callback failed, or it timed out) gets them back through a
--      trigger. No admin bypass: portraits_enabled is a kill switch for
--      everyone, and it is switched ON here.
-- Safe to re-run.
-- =============================================================================

-- Only used inside plpgsql bodies below, never at run time of this file, so
-- it can share the transaction with them.
alter type public.notification_type add value if not exists 'car_doc';

-- =============================================================================
-- 1. documents
-- =============================================================================
create table if not exists public.car_documents (
  car_id            uuid primary key references public.cars (id) on delete cascade,
  road_tax_expiry   date,
  insurer           text check (insurer is null or char_length(insurer) <= 60),
  policy_no         text check (policy_no is null or char_length(policy_no) <= 40),
  insurance_expiry  date,
  ncd_pct           numeric(5,2) check (ncd_pct is null or ncd_pct between 0 and 100),
  sum_insured       numeric(12,2) check (sum_insured is null or sum_insured >= 0),
  note              text check (note is null or char_length(note) <= 300),
  puspakom_due      date,
  service_due_on    date,
  service_due_km    int check (service_due_km is null or service_due_km between 1 and 2000000),
  updated_at        timestamptz not null default now()
);

alter table public.car_documents enable row level security;
drop policy if exists "car_documents: owner only" on public.car_documents;
create policy "car_documents: owner only" on public.car_documents for all to authenticated
  using (exists (select 1 from public.cars c where c.id = car_id and c.owner_id = auth.uid()))
  with check (exists (select 1 from public.cars c where c.id = car_id and c.owner_id = auth.uid()));
revoke all on public.car_documents from anon;

create or replace function public.touch_car_documents() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists car_documents_touch on public.car_documents;
create trigger car_documents_touch before update on public.car_documents
  for each row execute function public.touch_car_documents();

-- Daily at 09:00 MYT: "Road tax for your Myvi runs out in 7 days (12 Oct)."
-- One ping per car, document and step; a second run the same day is a no-op.
create or replace function public.send_car_doc_reminders() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  r record;
  v_body text;
  n int := 0;
begin
  for r in
    select c.owner_id, c.model, x.label, x.due, (x.due - v_today) as days_left
      from public.car_documents d
      join public.cars c on c.id = d.car_id
     cross join lateral (values ('Road tax', d.road_tax_expiry), ('Insurance', d.insurance_expiry)) as x(label, due)
     where x.due is not null and (x.due - v_today) in (30, 7, 1)
  loop
    v_body := r.label || ' for your ' || r.model || ' runs out '
      || case when r.days_left = 1 then 'tomorrow' else 'in ' || r.days_left || ' days' end
      || ' (' || to_char(r.due, 'FMDD Mon') || '). Renew it in time.';
    if not exists (
      select 1 from public.notifications
       where user_id = r.owner_id and type = 'car_doc' and body = v_body and created_at > now() - interval '20 hours'
    ) then
      perform public.notify(r.owner_id, null, 'car_doc', p_body => v_body);
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;

-- =============================================================================
-- 2. mods log
-- =============================================================================
alter table public.car_mods add column if not exists category   text not null default 'other';
alter table public.car_mods add column if not exists shop       text;
alter table public.car_mods add column if not exists vendor_id  uuid references public.vendors (id) on delete set null;
alter table public.car_mods add column if not exists is_private boolean not null default false;
alter table public.car_mods add column if not exists updated_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'car_mods_category_check') then
    alter table public.car_mods add constraint car_mods_category_check check (category in (
      'engine', 'exhaust', 'intake', 'suspension', 'wheels', 'brakes', 'body', 'lighting', 'interior', 'audio', 'other'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'car_mods_shop_check') then
    alter table public.car_mods add constraint car_mods_shop_check check (shop is null or char_length(shop) <= 80);
  end if;
end;
$$;

-- Mods logged before categories existed: a best guess from the name.
update public.car_mods set category = case
    when title ~* '\m(steering|seats?|bucket|harness|shift ?knob|pedals?|dash)\M' then 'interior'
    when title ~* '\m(speakers?|subwoofer|woofer|amp|amplifier|audio|head ?unit)\M' then 'audio'
    when title ~* '\m(wheels?|rims?|tyres?|tires?|te37|rota|rays|enkei|volk|bbs|advan|spacers?)\M' then 'wheels'
    when title ~* '\m(brakes?|calipers?|rotors?|brake pads?)\M' then 'brakes'
    when title ~* '\m(coilovers?|suspension|springs?|lowering|sway ?bar|struts?|camber|dampers?|absorbers?|tein|bc racing)\M' then 'suspension'
    when title ~* '\m(exhaust|headers?|muffler|downpipe|cat ?back|extractors?)\M' then 'exhaust'
    when title ~* '\m(intake|air filter|pod filter|throttle body)\M' then 'intake'
    when title ~* '\m(turbo|ecu|remap|tune|tuned|pistons?|camshafts?|supercharger|intercooler|engine|swap|radiator)\M' then 'engine'
    when title ~* '\m(body ?kit|bonnet|hood|wing|spoiler|diffuser|lip|skirts?|bumper|carbon|fenders?|wrap|rocket bunny|aero)\M' then 'body'
    when title ~* '\m(lights?|led|hid|lamps?|headlamps?)\M' then 'lighting'
    else 'other'
  end
 where category = 'other' and updated_at is null; -- save_car_mod() always sets updated_at, so a pick of "Other" stays

-- Public mods for everyone signed in, private ones for the owner only.
drop policy if exists "car_mods: read" on public.car_mods;
drop policy if exists "car_mods: read public or own" on public.car_mods;
create policy "car_mods: read public or own" on public.car_mods for select to authenticated
  using (not is_private or exists (select 1 from public.cars c where c.id = car_id and c.owner_id = auth.uid()));

-- The price column is not readable through the API at all (a policy can hide
-- rows, not columns). The owner gets it back from car_mod_list(). A column
-- added to car_mods later must be added to this grant to be readable.
revoke all on public.car_mods from anon;
revoke select on public.car_mods from authenticated;
grant select (id, car_id, title, description, done_on, photo_urls, created_at, category, shop, vendor_id, is_private, updated_at)
  on public.car_mods to authenticated;

-- A car's mods, newest first: public ones for everyone, private ones and the
-- prices only for the owner.
create or replace function public.car_mod_list(p_car uuid)
returns table (id uuid, car_id uuid, category text, title text, description text, cost numeric, shop text,
               vendor_id uuid, vendor_name text, done_on date, photo_urls text[], is_private boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select m.id, m.car_id, m.category, m.title, m.description,
         case when c.owner_id = auth.uid() then m.cost end,
         m.shop, m.vendor_id, v.name, m.done_on, m.photo_urls, m.is_private, m.created_at
    from public.car_mods m
    join public.cars c on c.id = m.car_id
    left join public.vendors v on v.id = m.vendor_id
   where m.car_id = p_car
     and auth.uid() is not null
     and (not m.is_private or c.owner_id = auth.uid())
   order by m.done_on desc, m.created_at desc;
$$;

-- Add (p_id null) or edit one of my car's mods. Returns its id.
create or replace function public.save_car_mod(
  p_car uuid,
  p_title text,
  p_category text default 'other',
  p_done_on date default null,
  p_cost numeric default null,
  p_shop text default null,
  p_vendor uuid default null,
  p_description text default null,
  p_photo_urls text[] default '{}',
  p_private boolean default false,
  p_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_title text := nullif(trim(coalesce(p_title, '')), '');
  v_shop text := nullif(trim(coalesce(p_shop, '')), '');
  v_notes text := nullif(trim(coalesce(p_description, '')), '');
  v_photos text[] := coalesce(p_photo_urls, '{}');
  v_id uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if not exists (select 1 from public.cars where id = p_car and owner_id = me) then
    raise exception 'That car is not in your garage';
  end if;
  if v_title is null or char_length(v_title) < 2 then raise exception 'Name the mod, e.g. BC Racing coilovers.'; end if;
  if char_length(v_title) > 80 then raise exception 'Keep the name under 80 characters.'; end if;
  if coalesce(p_category, '') not in ('engine', 'exhaust', 'intake', 'suspension', 'wheels', 'brakes', 'body', 'lighting', 'interior', 'audio', 'other') then
    raise exception 'Pick a category';
  end if;
  if p_cost is not null and (p_cost < 0 or p_cost >= 100000000) then raise exception 'Check the price.'; end if;
  if char_length(coalesce(v_shop, '')) > 80 then raise exception 'Keep the shop name under 80 characters.'; end if;
  if char_length(coalesce(v_notes, '')) > 500 then raise exception 'Keep the notes under 500 characters.'; end if;
  if cardinality(v_photos) > 5 then raise exception 'Too many photos'; end if;
  if p_done_on is not null and p_done_on > (now() at time zone 'Asia/Kuala_Lumpur')::date + 1 then
    raise exception 'The install date is in the future.';
  end if;

  if p_id is null then
    insert into public.car_mods (car_id, title, category, done_on, cost, shop, vendor_id, description, photo_urls, is_private, updated_at)
    values (p_car, v_title, p_category, coalesce(p_done_on, current_date), p_cost, v_shop, p_vendor, v_notes, v_photos, coalesce(p_private, false), now())
    returning id into v_id;
  else
    update public.car_mods
       set title = v_title, category = p_category, done_on = coalesce(p_done_on, done_on), cost = p_cost,
           shop = v_shop, vendor_id = p_vendor, description = v_notes, photo_urls = v_photos,
           is_private = coalesce(p_private, false), updated_at = now()
     where id = p_id and car_id = p_car
    returning id into v_id;
    if v_id is null then raise exception 'That mod is gone. Pull to refresh.'; end if;
  end if;
  return v_id;
end;
$$;

-- =============================================================================
-- 3. AI portraits for points
-- =============================================================================
insert into public.platform_settings (key, value, description) values
  ('portrait_cost_points', '300', 'Points one AI car portrait costs (taken when it starts, refunded if it fails). 0 = free.')
on conflict (key) do nothing;

-- Owner's call (2026-09-30): portraits are open to members now, for points.
update public.platform_settings
   set value = 'true', updated_at = now(),
       description = 'Kill switch for AI car portraits (Kie). Off = nobody can start one, admins included.'
 where key = 'portraits_enabled';

-- Labels for the points history (0 = not an earn rule, hidden from "How to earn").
insert into public.point_rules (reason, points, label, description, sort) values
  ('portrait',        0, 'AI car portrait', 'Spent on an AI portrait of your car.',              210),
  ('portrait_refund', 0, 'Portrait refund', 'Points back for a portrait that didn''t come out.', 211)
on conflict (reason) do nothing;

alter table public.car_portraits add column if not exists points_spent int not null default 0;
alter table public.car_portraits add column if not exists refunded_at timestamptz;

-- Books a portrait job for one of my cars and pays for it. Returns the row id;
-- the Edge Function then creates the Kie task and fills task_id.
create or replace function public.request_car_portrait(p_car uuid, p_style text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_owner uuid;
  v_photos text[];
  v_limit int := greatest(0, public.setting_num('portrait_daily_limit', 3)::int);
  v_cost int := greatest(0, public.setting_num('portrait_cost_points', 300)::int);
  v_open boolean := coalesce((select value #>> '{}' from public.platform_settings where key = 'portraits_enabled'), 'false') in ('true', '1', 'on');
  v_balance int;
  v_used int;
  v_id uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if not v_open then raise exception 'AI portraits are paused right now. Try again later.'; end if;
  select owner_id, photo_urls into v_owner, v_photos from public.cars where id = p_car;
  if v_owner is null or v_owner <> me then raise exception 'That car is not in your garage'; end if;
  if coalesce(array_length(v_photos, 1), 0) = 0 then raise exception 'Add a photo of the car first'; end if;
  if p_style is null or p_style not in ('showroom', 'night_city', 'golden_hour', 'race_poster', 'pastel_dream', 'film', 'track_day', 'line_art') then
    raise exception 'Pick a style';
  end if;

  -- Lock my balance first: two taps at once queue here, so the second one
  -- sees the first one's pending job below and cannot spend twice.
  perform 1 from public.profiles where id = me for update;

  -- A job that never came back (Kie down, callback lost) must not block the
  -- car forever. Marking it failed refunds it (trigger below).
  update public.car_portraits set status = 'failed', error = 'Timed out. Your points are back.'
   where car_id = p_car and status = 'pending' and created_at < now() - interval '15 minutes';

  if exists (select 1 from public.car_portraits where car_id = p_car and status = 'pending') then
    raise exception 'A portrait of this car is still being painted. Give it a minute.';
  end if;

  select count(*) into v_used from public.car_portraits
   where car_id = p_car and created_at > now() - interval '24 hours';
  if v_used >= v_limit then
    raise exception 'That''s % portraits for this car today. Try again tomorrow.', v_limit;
  end if;

  select points into v_balance from public.profiles where id = me; -- after any refund above
  if coalesce(v_balance, 0) < v_cost then
    raise exception 'A portrait costs % points. You have %.', v_cost, coalesce(v_balance, 0);
  end if;

  insert into public.car_portraits (car_id, owner_id, style, points_spent) values (p_car, me, p_style, v_cost) returning id into v_id;
  if v_cost > 0 then
    perform public.award_points(me, -v_cost, 'portrait', 'car_portrait', v_id::text, 'AI car portrait', 'portrait:' || v_id);
  end if;
  return v_id;
end;
$$;

-- Whatever marks a paid job failed (the Edge Function when Kie refuses the
-- task or the callback reports a failure, the timeout above, the sweep
-- below), the points go back once.
create or replace function public.refund_failed_portrait() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'failed' and old.status is distinct from 'failed' and new.points_spent > 0 and new.refunded_at is null then
    perform public.award_points(new.owner_id, new.points_spent, 'portrait_refund', 'car_portrait', new.id::text,
                                'AI portrait refund', 'portrait_refund:' || new.id);
    new.refunded_at := now();
  end if;
  return new;
end;
$$;
drop trigger if exists car_portraits_refund on public.car_portraits;
create trigger car_portraits_refund before update of status on public.car_portraits
  for each row execute function public.refund_failed_portrait();

-- Jobs whose callback never came: fail (and so refund) them after 15 minutes
-- instead of waiting for the next request on the same car.
create or replace function public.sweep_stale_portraits() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.car_portraits set status = 'failed', error = 'Timed out. Your points are back.'
   where status = 'pending' and created_at < now() - interval '15 minutes';
  get diagnostics n = row_count;
  return n;
end;
$$;

-- =============================================================================
-- schedules
-- =============================================================================
do $outer$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron could not be created: %', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'ttspot-car-doc-reminders') then
      perform cron.unschedule('ttspot-car-doc-reminders');
    end if;
    perform cron.schedule('ttspot-car-doc-reminders', '0 1 * * *', 'select public.send_car_doc_reminders()');
    if exists (select 1 from cron.job where jobname = 'ttspot-stale-portraits') then
      perform cron.unschedule('ttspot-stale-portraits');
    end if;
    perform cron.schedule('ttspot-stale-portraits', '*/10 * * * *', 'select public.sweep_stale_portraits()');
  else
    raise notice 'pg_cron not available: run send_car_doc_reminders() daily and sweep_stale_portraits() every 10 minutes some other way';
  end if;
end;
$outer$;

-- =============================================================================
-- grants
-- =============================================================================
revoke execute on function public.touch_car_documents() from public, anon, authenticated;
revoke execute on function public.send_car_doc_reminders() from public, anon, authenticated;
revoke execute on function public.car_mod_list(uuid) from public, anon;
revoke execute on function public.save_car_mod(uuid, text, text, date, numeric, text, uuid, text, text[], boolean, uuid) from public, anon;
revoke execute on function public.request_car_portrait(uuid, text) from public, anon;
revoke execute on function public.refund_failed_portrait() from public, anon, authenticated;
revoke execute on function public.sweep_stale_portraits() from public, anon, authenticated;

grant execute on function public.car_mod_list(uuid) to authenticated;
grant execute on function public.save_car_mod(uuid, text, text, date, numeric, text, uuid, text, text[], boolean, uuid) to authenticated;
grant execute on function public.request_car_portrait(uuid, text) to authenticated;
