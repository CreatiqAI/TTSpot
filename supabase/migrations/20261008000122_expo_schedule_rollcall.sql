-- =============================================================================
-- Expo mode, track D (docs/expo-mode-plan.md items 12 and 13):
--   * the stage schedule: host items, "Remind me", a push 10 min before;
--   * the lucky draw roll call: "Confirm you're here" N min before the draw,
--     only confirmed members enter;
--   * the entry number (#0427, checkins.entry_no) on the draw card, the
--     stage and the winners list.
-- Tables and columns are in 0118. Functions patched here were copied from
-- their LIVE definitions (pg_get_functiondef, 2026-10-07) and extended.
-- =============================================================================

-- =============================================================================
-- schedule
-- =============================================================================

-- Where an item happens, in words: the typed place, else the pin's label,
-- else the pin's kind ("Stage").
create or replace function public.agenda_place(p_label text, p_pin uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    nullif(trim(coalesce(p_label, '')), ''),
    (select coalesce(nullif(trim(p.label), ''), initcap(replace(p.kind, '_', ' ')))
       from public.event_floor_pins p where p.id = p_pin)
  );
$$;

-- Every item of an event, with my reminder and where its pin is.
-- reminder_count is for hosts only (null for everyone else).
create or replace function public.event_agenda_list(p_event uuid)
returns table (
  id uuid, event_id uuid, title text, about text, starts_at timestamptz, ends_at timestamptz,
  pin_id uuid, place_label text, place text, pin_kind text, pin_level_id uuid,
  reminder_on boolean, reminder_count int
)
language sql stable security definer set search_path = public as $$
  select a.id, a.event_id, a.title, a.about, a.starts_at, a.ends_at,
         a.pin_id, a.place_label, public.agenda_place(a.place_label, a.pin_id), p.kind, p.level_id,
         exists (select 1 from public.event_agenda_reminders r where r.item_id = a.id and r.user_id = auth.uid()),
         case when public.is_meet_host(a.event_id)
              then (select count(*)::int from public.event_agenda_reminders r where r.item_id = a.id) end
    from public.event_agenda a
    left join public.event_floor_pins p on p.id = a.pin_id
   where a.event_id = p_event and auth.uid() is not null
   order by a.starts_at, a.title;
$$;

-- Host: add (p_item null) or edit an item. Moving the start time re-arms
-- the reminder push.
create or replace function public.save_agenda_item(
  p_event uuid,
  p_item uuid,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz default null,
  p_about text default null,
  p_pin uuid default null,
  p_place text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e public.events;
  a public.event_agenda;
  v_open timestamptz;
  v_close timestamptz;
  v_title text := left(trim(coalesce(p_title, '')), 80);
  v_about text := nullif(left(trim(coalesce(p_about, '')), 500), '');
  v_place text := nullif(left(trim(coalesce(p_place, '')), 60), '');
begin
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  if not public.is_meet_host(p_event) then raise exception 'Only the host or a co-host can edit the schedule'; end if;
  if char_length(v_title) = 0 then raise exception 'Give it a title'; end if;
  if p_starts_at is null then raise exception 'Pick a start time'; end if;
  if p_ends_at is not null and p_ends_at <= p_starts_at then raise exception 'The end has to be after the start'; end if;
  select opens_at, closes_at into v_open, v_close from public.event_period(p_event);
  if p_starts_at < v_open or p_starts_at > v_close then raise exception 'Pick a time during the event'; end if;
  if p_pin is not null and not exists (
    select 1 from public.event_floor_pins p join public.event_floor_levels l on l.id = p.level_id
     where p.id = p_pin and l.event_id = p_event) then
    raise exception 'That spot is not on this event''s floor plan';
  end if;

  if p_item is null then
    if (select count(*) from public.event_agenda where event_id = p_event) >= 200 then
      raise exception 'Up to 200 schedule items';
    end if;
    insert into public.event_agenda (event_id, title, about, starts_at, ends_at, pin_id, place_label, created_by)
    values (p_event, v_title, v_about, p_starts_at, p_ends_at, p_pin, v_place, auth.uid())
    returning * into a;
  else
    update public.event_agenda
       set title = v_title, about = v_about, starts_at = p_starts_at, ends_at = p_ends_at,
           pin_id = p_pin, place_label = v_place,
           reminded_at = case when starts_at <> p_starts_at then null else reminded_at end
     where id = p_item and event_id = p_event
    returning * into a;
    if a.id is null then raise exception 'Schedule item not found'; end if;
  end if;
  return a.id;
end;
$$;

create or replace function public.delete_agenda_item(p_item uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  select event_id into v_event from public.event_agenda where id = p_item;
  if v_event is null then raise exception 'Schedule item not found'; end if;
  if not public.is_meet_host(v_event) then raise exception 'Only the host or a co-host can edit the schedule'; end if;
  delete from public.event_agenda where id = p_item;
end;
$$;

-- Member: "Remind me" on/off. Returns true when the reminder is now on.
create or replace function public.toggle_agenda_reminder(p_item uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  a public.event_agenda;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into a from public.event_agenda where id = p_item;
  if a.id is null then raise exception 'Schedule item not found'; end if;
  delete from public.event_agenda_reminders where item_id = p_item and user_id = me;
  if found then return false; end if;
  if a.starts_at <= now() then raise exception 'This has already started'; end if;
  insert into public.event_agenda_reminders (item_id, user_id) values (p_item, me) on conflict do nothing;
  return true;
end;
$$;

-- Cron: items starting in the next 10 minutes push everyone who asked.
-- Items more than 2 minutes past their start are skipped (outage guard).
create or replace function public.due_agenda_reminders() returns int
language plpgsql security definer set search_path = public as $$
declare
  a record;
  n int := 0;
  k int;
  v_place text;
begin
  for a in
    update public.event_agenda x set reminded_at = now()
     where x.reminded_at is null
       and x.starts_at <= now() + interval '10 minutes'
       and x.starts_at > now() - interval '2 minutes'
       and exists (select 1 from public.events e where e.id = x.event_id and e.status <> 'cancelled')
    returning x.id, x.event_id, x.title, x.starts_at, x.pin_id, x.place_label
  loop
    v_place := public.agenda_place(a.place_label, a.pin_id);
    insert into public.notifications (user_id, type, event_id, body)
    select r.user_id, 'announcement'::public.notification_type, a.event_id,
           a.title || E'\n' || 'Starts at ' || public.lucky_draw_time(a.starts_at) || coalesce(' · ' || v_place, '')
      from public.event_agenda_reminders r
     where r.item_id = a.id;
    get diagnostics k = row_count;
    n := n + k;
  end loop;
  return n;
end;
$$;

do $outer$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron could not be created: %', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'ttspot-agenda-reminders') then
      perform cron.unschedule('ttspot-agenda-reminders');
    end if;
    perform cron.schedule('ttspot-agenda-reminders', '* * * * *', 'select public.due_agenda_reminders()');
  else
    raise notice 'pg_cron not available: schedule public.due_agenda_reminders() every minute some other way';
  end if;
end;
$outer$;

-- =============================================================================
-- lucky draw roll call
-- =============================================================================

-- "2.3 km" / "450 m" for messages.
create or replace function public.distance_words(p_m float8) returns text
language sql immutable as $$
  select case when p_m < 1000 then round(p_m)::int || ' m'
              else to_char(p_m / 1000.0, 'FM999990.0') || ' km' end;
$$;

-- The roll call is open from draw_at - presence_minutes until entries close.
create or replace function public.lucky_draw_presence_open(d public.lucky_draws) returns boolean
language sql stable as $$
  select d.status = 'scheduled' and d.presence_minutes is not null
     and now() >= d.draw_at - make_interval(mins => d.presence_minutes)
     and now() <= coalesce(d.cutoff_at, d.draw_at);
$$;

-- With a roll call, only members who confirmed they're here are in.
create or replace function public.lucky_draw_eligible(p_draw uuid)
returns table (user_id uuid)
language sql stable security definer set search_path = public as $$
  select c.user_id
  from public.lucky_draws d
  join public.events e on e.id = d.event_id
  join public.checkins c on c.event_id = d.event_id
  where d.id = p_draw
    and c.checked_in_at <= coalesce(d.cutoff_at, d.draw_at)
    and (c.confirmed_at is not null or (c.source = 'qr' and c.confirmed_by is null))
    and c.user_id <> e.organizer_id
    and not exists (select 1 from public.event_crew k where k.event_id = d.event_id and k.user_id = c.user_id)
    and (d.presence_minutes is null
         or exists (select 1 from public.lucky_draw_presence pr where pr.draw_id = d.id and pr.user_id = c.user_id));
$$;

-- save_lucky_draw gains p_presence_minutes (null = no roll call). The old
-- 8-argument version is dropped; the new one has defaults for everything
-- after p_draw_at, so old calls (named params) still work.
drop function if exists public.save_lucky_draw(uuid, uuid, text, timestamptz, timestamptz, boolean, int, jsonb);

create or replace function public.save_lucky_draw(
  p_event uuid,
  p_draw uuid,
  p_title text,
  p_draw_at timestamptz,
  p_cutoff_at timestamptz default null,
  p_must_be_present boolean default true,
  p_claim_minutes int default 15,
  p_prizes jsonb default '[]'::jsonb,
  p_presence_minutes int default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  e public.events;
  d public.lucky_draws;
  v_open timestamptz;
  v_close timestamptz;
  v_cutoff timestamptz := coalesce(p_cutoff_at, p_draw_at);
  v_id uuid;
  v_seed bytea;
  v_prize jsonb;
  v_total int := 0;
  v_i int := 0;
begin
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  if e.status = 'cancelled' then raise exception 'This meet was cancelled'; end if;
  if not public.is_meet_host(p_event) then raise exception 'Only the host or a co-host can set up a lucky draw'; end if;
  if not public.is_organizer(e.organizer_id) then
    raise exception 'Lucky draws are for verified organizers. Apply in Me > Apply to be an organizer.';
  end if;
  if char_length(trim(coalesce(p_title, ''))) < 2 then raise exception 'Give the draw a name'; end if;
  if p_draw_at is null or p_draw_at <= now() then raise exception 'Pick a draw time in the future'; end if;
  if v_cutoff > p_draw_at then raise exception 'The cut-off must be at or before the draw'; end if;
  select opens_at, closes_at into v_open, v_close from public.event_period(p_event);
  if p_draw_at < v_open or p_draw_at > v_close then raise exception 'The draw has to happen during the meet'; end if;
  if coalesce(p_claim_minutes, 15) not between 1 and 240 then raise exception 'Claim window is 1 to 240 minutes'; end if;
  if p_presence_minutes is not null then
    if p_presence_minutes not between 5 and 120 then raise exception 'Roll call is 5 to 120 minutes before the draw'; end if;
    if v_cutoff <= p_draw_at - make_interval(mins => p_presence_minutes) then
      raise exception 'Entries close before the roll call opens. Move the cut-off later or turn roll call off.';
    end if;
  end if;
  if jsonb_typeof(coalesce(p_prizes, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_prizes, '[]'::jsonb)) = 0 then
    raise exception 'Add at least one prize';
  end if;
  if jsonb_array_length(p_prizes) > 20 then raise exception 'Up to 20 prizes'; end if;
  for v_prize in select * from jsonb_array_elements(p_prizes) loop
    if char_length(trim(coalesce(v_prize ->> 'name', ''))) = 0 then raise exception 'Every prize needs a name'; end if;
    if coalesce((v_prize ->> 'quantity')::int, 1) not between 1 and 50 then raise exception 'Quantity is 1 to 50'; end if;
    v_total := v_total + coalesce((v_prize ->> 'quantity')::int, 1);
  end loop;
  if v_total > 100 then raise exception 'Up to 100 winners per draw'; end if;

  if p_draw is null then
    if (select count(*) from public.lucky_draws where event_id = p_event and status <> 'cancelled') >= 5 then
      raise exception 'A meet can have up to 5 draws';
    end if;
    v_seed := extensions.gen_random_bytes(32);
    insert into public.lucky_draws (event_id, title, draw_at, cutoff_at, must_be_present, claim_minutes, presence_minutes, seed_hash, created_by)
    values (p_event, left(trim(p_title), 80), p_draw_at, v_cutoff, coalesce(p_must_be_present, true), coalesce(p_claim_minutes, 15),
            p_presence_minutes, encode(extensions.digest(v_seed, 'sha256'), 'hex'), me)
    returning * into d;
    insert into public.lucky_draw_secrets (draw_id, seed) values (d.id, v_seed);
    insert into public.lucky_draw_audit (draw_id, action, actor_id, seed_hash, detail)
    values (d.id, 'scheduled', me, d.seed_hash, jsonb_build_object('draw_at', p_draw_at, 'cutoff_at', v_cutoff, 'prizes', p_prizes,
                                                                   'presence_minutes', p_presence_minutes));
  else
    select * into d from public.lucky_draws where id = p_draw for update;
    if d.id is null or d.event_id <> p_event then raise exception 'Draw not found'; end if;
    if d.status <> 'scheduled' then raise exception 'This draw has already run or was cancelled'; end if;
    -- A new draw time means a new roll call: earlier confirmations no longer count.
    if d.draw_at <> p_draw_at then
      delete from public.lucky_draw_presence where draw_id = d.id;
    end if;
    update public.lucky_draws
       set title = left(trim(p_title), 80), draw_at = p_draw_at, cutoff_at = v_cutoff,
           must_be_present = coalesce(p_must_be_present, true), claim_minutes = coalesce(p_claim_minutes, 15),
           presence_minutes = p_presence_minutes,
           presence_asked_at = case when draw_at <> p_draw_at or presence_minutes is null then null else presence_asked_at end,
           reminded_30_at = case when draw_at <> p_draw_at then null else reminded_30_at end,
           reminded_5_at = case when draw_at <> p_draw_at then null else reminded_5_at end,
           start_notified_at = case when draw_at <> p_draw_at then null else start_notified_at end
     where id = p_draw
    returning * into d;
    delete from public.lucky_draw_prizes where draw_id = d.id;
    insert into public.lucky_draw_audit (draw_id, action, actor_id, seed_hash, detail)
    values (d.id, 'edited', me, d.seed_hash, jsonb_build_object('draw_at', p_draw_at, 'cutoff_at', v_cutoff, 'prizes', p_prizes,
                                                                'presence_minutes', p_presence_minutes));
  end if;

  for v_prize in select * from jsonb_array_elements(p_prizes) loop
    insert into public.lucky_draw_prizes (draw_id, name, quantity, sort)
    values (d.id, left(trim(v_prize ->> 'name'), 80), coalesce((v_prize ->> 'quantity')::int, 1), v_i);
    v_i := v_i + 1;
  end loop;
  return d.id;
end;
$$;

-- Member: "I'm here". Checks the draw, the roll call window, that I'm in the
-- audience (checked in, not host or crew) and that I'm inside the event's
-- check-in area. Location is used for this tap only.
create or replace function public.confirm_draw_presence(p_draw uuid, p_lat float8, p_lng float8) returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  d public.lucky_draws;
  e public.events;
  v_dist float8;
  v_radius float8;
  v_opens timestamptz;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into d from public.lucky_draws where id = p_draw;
  if d.id is null then raise exception 'Draw not found'; end if;
  if d.status = 'cancelled' then raise exception 'This lucky draw was cancelled'; end if;
  if d.status <> 'scheduled' then raise exception 'This draw has already run'; end if;
  if d.presence_minutes is null then raise exception 'This draw has no roll call. You''re in if you checked in.'; end if;
  v_opens := d.draw_at - make_interval(mins => d.presence_minutes);
  if now() < v_opens then
    raise exception 'Roll call opens at %. Tap again then.', public.lucky_draw_time(v_opens);
  end if;
  if now() > coalesce(d.cutoff_at, d.draw_at) then
    raise exception 'Roll call closed at %.', public.lucky_draw_time(coalesce(d.cutoff_at, d.draw_at));
  end if;
  select * into e from public.events where id = d.event_id;
  if e.organizer_id = me or exists (select 1 from public.event_crew k where k.event_id = d.event_id and k.user_id = me) then
    raise exception 'You''re running this event, so you can''t enter the draw.';
  end if;
  if not exists (select 1 from public.lucky_draw_audience(d.id) a where a.user_id = me) then
    raise exception 'Check in at the event first to be in the draw.';
  end if;
  if p_lat is null or p_lng is null then
    raise exception 'Turn on location so we can confirm you''re here.';
  end if;
  v_radius := coalesce(e.checkin_radius_m, public.setting_num('checkin_radius_m', 300));
  v_dist := public.metres_between(p_lat, p_lng, e.lat, e.lng);
  if v_dist > v_radius then
    raise exception 'You''re % away. Come back to the hall and tap again.', public.distance_words(v_dist);
  end if;
  insert into public.lucky_draw_presence (draw_id, user_id, distance_m)
  values (d.id, me, round(v_dist)::int)
  on conflict (draw_id, user_id) do update set distance_m = excluded.distance_m;
  return json_build_object('confirmed', true, 'distance_m', round(v_dist)::int);
end;
$$;

-- Crew: how many confirmed so far (the host list shows "38 confirmed").
create or replace function public.draw_presence_count(p_draw uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare v_event uuid;
begin
  select event_id into v_event from public.lucky_draws where id = p_draw;
  if v_event is null then raise exception 'Draw not found'; end if;
  if not public.is_event_crew(v_event) then raise exception 'Only the host or crew can see this'; end if;
  return (select count(*)::int from public.lucky_draw_presence where draw_id = p_draw);
end;
$$;

-- =============================================================================
-- reads, now with the entry number and the roll call
-- =============================================================================

create or replace function public.my_draw_status(p_event uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(s.j order by s.at), '[]'::jsonb)
  from (
    select d.draw_at as at, jsonb_build_object(
      'id', d.id,
      'title', d.title,
      'draw_at', d.draw_at,
      'cutoff_at', d.cutoff_at,
      'must_be_present', d.must_be_present,
      'claim_minutes', d.claim_minutes,
      'status', d.status,
      'entrant_count', d.entrant_count,
      'prizes', coalesce((select jsonb_agg(jsonb_build_object('name', p.name, 'quantity', p.quantity) order by p.sort)
                          from public.lucky_draw_prizes p where p.draw_id = d.id), '[]'::jsonb),
      'checked_in', exists (select 1 from public.checkins c where c.event_id = d.event_id and c.user_id = auth.uid()),
      'entry_no', (select c.entry_no from public.checkins c where c.event_id = d.event_id and c.user_id = auth.uid()),
      'eligible', case when d.status = 'drawn'
                       then exists (select 1 from public.lucky_draw_entrants en where en.draw_id = d.id and en.user_id = auth.uid())
                       else exists (select 1 from public.lucky_draw_eligible(d.id) x where x.user_id = auth.uid()) end,
      'excluded', case when e.organizer_id = auth.uid() then 'host'
                       when exists (select 1 from public.event_crew k where k.event_id = d.event_id and k.user_id = auth.uid()) then 'crew' end,
      'presence_required', d.presence_minutes is not null,
      'presence_minutes', d.presence_minutes,
      'presence_open', public.lucky_draw_presence_open(d),
      'presence_confirmed', exists (select 1 from public.lucky_draw_presence pr where pr.draw_id = d.id and pr.user_id = auth.uid()),
      'win', (select jsonb_build_object('id', w.id, 'prize', p.name, 'rank', w.rank, 'claim_code', w.claim_code,
                                        'expires_at', w.expires_at, 'status', w.status, 'is_alternate', w.is_alternate,
                                        'has_prize', w.prize_id is not null, 'claimed_at', w.claimed_at)
                from public.lucky_draw_winners w left join public.lucky_draw_prizes p on p.id = w.prize_id
               where w.draw_id = d.id and w.user_id = auth.uid())
    ) as j
    from public.lucky_draws d join public.events e on e.id = d.event_id
    where d.event_id = p_event and d.status <> 'cancelled' and auth.uid() is not null
  ) s;
$$;

-- The return type changes (entry_no), so drop and recreate.
drop function if exists public.draw_results(uuid);
create function public.draw_results(p_draw uuid)
returns table (rank int, prize text, display_name text, username text, avatar_url text, status text, is_alternate boolean, user_id uuid, entry_no int)
language sql stable security definer set search_path = public as $$
  select w.rank, p.name, coalesce(pr.display_name, pr.username::text), pr.username::text, pr.avatar_url, w.status, w.is_alternate, w.user_id,
         (select c.entry_no from public.checkins c where c.event_id = d.event_id and c.user_id = w.user_id)
  from public.lucky_draw_winners w
  join public.lucky_draws d on d.id = w.draw_id and d.status = 'drawn'
  join public.lucky_draw_prizes p on p.id = w.prize_id
  join public.profiles pr on pr.id = w.user_id
  where w.draw_id = p_draw and auth.uid() is not null
  order by p.sort, w.rank;
$$;

-- Stage: winners carry entry_no; plus the roll call count and a sample of
-- entry numbers to roll during the reveal.
create or replace function public.draw_stage(p_draw uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  d public.lucky_draws;
  v jsonb;
begin
  select * into d from public.lucky_draws where id = p_draw;
  if d.id is null then raise exception 'Draw not found'; end if;
  if not public.is_event_crew(d.event_id) then raise exception 'Only the host or crew can open the stage screen'; end if;
  select jsonb_build_object(
    'id', d.id, 'event_id', d.event_id, 'title', d.title, 'status', d.status,
    'draw_at', d.draw_at, 'cutoff_at', d.cutoff_at, 'must_be_present', d.must_be_present, 'claim_minutes', d.claim_minutes,
    'drawn_at', d.drawn_at, 'seed_hash', d.seed_hash, 'seed_reveal', d.seed_reveal, 'entrants_hash', d.entrants_hash,
    'entrant_count', case when d.status = 'drawn' then d.entrant_count
                          else (select count(*) from public.lucky_draw_eligible(d.id)) end,
    'checked_in', (select count(*) from public.lucky_draw_audience(d.id)),
    'presence_minutes', d.presence_minutes,
    'presence_confirmed', (select count(*) from public.lucky_draw_presence pr where pr.draw_id = d.id),
    'names', coalesce((select jsonb_agg(n) from (
                 select coalesce(pr.display_name, pr.username::text) n
                   from public.profiles pr
                  where pr.id in (select en.user_id from public.lucky_draw_entrants en where en.draw_id = d.id
                                  union select x.user_id from public.lucky_draw_eligible(d.id) x where d.status <> 'drawn')
                  order by random() limit 120) t), '[]'::jsonb),
    'entry_nos', coalesce((select jsonb_agg(t.entry_no) from (
                 select c.entry_no
                   from public.checkins c
                  where c.event_id = d.event_id and c.entry_no is not null
                    and c.user_id in (select en.user_id from public.lucky_draw_entrants en where en.draw_id = d.id
                                      union select x.user_id from public.lucky_draw_eligible(d.id) x where d.status <> 'drawn')
                  order by random() limit 120) t), '[]'::jsonb),
    'prizes', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'quantity', p.quantity) order by p.sort)
                          from public.lucky_draw_prizes p where p.draw_id = d.id), '[]'::jsonb),
    'winners', coalesce((select jsonb_agg(jsonb_build_object(
                     'id', w.id, 'rank', w.rank, 'prize', p.name, 'prize_id', w.prize_id, 'prize_sort', p.sort,
                     'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url,
                     'user_id', w.user_id,
                     'entry_no', (select c.entry_no from public.checkins c where c.event_id = d.event_id and c.user_id = w.user_id),
                     'status', w.status, 'is_alternate', w.is_alternate, 'expires_at', w.expires_at, 'claimed_at', w.claimed_at,
                     'promoted_at', w.promoted_at) order by w.rank)
                   from public.lucky_draw_winners w
                   join public.profiles pr on pr.id = w.user_id
                   left join public.lucky_draw_prizes p on p.id = w.prize_id
                  where w.draw_id = d.id), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

-- =============================================================================
-- scheduler: the roll call push, and the existing reminders
-- =============================================================================
create or replace function public.due_lucky_draws() returns int
language plpgsql security definer set search_path = public as $$
declare
  d record;
  n int := 0;
begin
  -- Roll call opens (draw_at - presence_minutes): everyone checked in, plus
  -- people who left (the same push calls them back).
  for d in
    update public.lucky_draws set presence_asked_at = now()
     where status = 'scheduled' and presence_minutes is not null and presence_asked_at is null
       and draw_at - make_interval(mins => presence_minutes) <= now()
       and coalesce(cutoff_at, draw_at) > now()
    returning id, event_id, title, draw_at
  loop
    n := n + public.lucky_draw_notify(
      array(select a.user_id from public.lucky_draw_audience(d.id) a
             where not exists (select 1 from public.lucky_draw_presence pr where pr.draw_id = d.id and pr.user_id = a.user_id)),
      d.event_id,
      d.title || ' at ' || public.lucky_draw_time(d.draw_at) || '. Tap to confirm you''re here.');
  end loop;

  -- T-30 min (skipped when the draw is already inside 6 min). With a roll
  -- call: before it opens, say when it opens; once open, nudge only the
  -- people who have not confirmed; right after the roll call push, stay quiet.
  for d in
    update public.lucky_draws set reminded_30_at = now()
     where status = 'scheduled' and reminded_30_at is null
       and draw_at > now() + interval '6 minutes' and draw_at <= now() + interval '30 minutes'
    returning id, event_id, title, draw_at, presence_minutes, presence_asked_at
  loop
    if d.presence_minutes is null then
      n := n + public.lucky_draw_notify(array(select a.user_id from public.lucky_draw_audience(d.id) a), d.event_id,
        d.title || ' at ' || public.lucky_draw_time(d.draw_at) || '. Stay checked in to be in the draw. Free entry.');
    elsif d.presence_asked_at is null then
      n := n + public.lucky_draw_notify(array(select a.user_id from public.lucky_draw_audience(d.id) a), d.event_id,
        d.title || ' at ' || public.lucky_draw_time(d.draw_at) || '. Roll call opens at '
        || public.lucky_draw_time(d.draw_at - make_interval(mins => d.presence_minutes)) || '. Free entry.');
    elsif d.presence_asked_at <= now() - interval '10 minutes' then
      n := n + public.lucky_draw_notify(
        array(select a.user_id from public.lucky_draw_audience(d.id) a
               where not exists (select 1 from public.lucky_draw_presence pr where pr.draw_id = d.id and pr.user_id = a.user_id)),
        d.event_id, d.title || ' at ' || public.lucky_draw_time(d.draw_at) || '. Tap to confirm you''re here.');
    end if;
  end loop;

  -- T-5 min. With a roll call still open, people who have not confirmed get
  -- "tap to confirm" instead (unless the roll call push just went out).
  for d in
    update public.lucky_draws set reminded_5_at = now()
     where status = 'scheduled' and reminded_5_at is null
       and draw_at > now() and draw_at <= now() + interval '5 minutes'
    returning id, event_id, title, presence_minutes, presence_asked_at, cutoff_at, draw_at
  loop
    if d.presence_minutes is not null and coalesce(d.cutoff_at, d.draw_at) > now() then
      n := n + public.lucky_draw_notify(
        array(select a.user_id from public.lucky_draw_audience(d.id) a
               where exists (select 1 from public.lucky_draw_presence pr where pr.draw_id = d.id and pr.user_id = a.user_id)),
        d.event_id, d.title || ' in 5 minutes. Head to the stage.');
      if d.presence_asked_at is null or d.presence_asked_at <= now() - interval '2 minutes' then
        n := n + public.lucky_draw_notify(
          array(select a.user_id from public.lucky_draw_audience(d.id) a
                 where not exists (select 1 from public.lucky_draw_presence pr where pr.draw_id = d.id and pr.user_id = a.user_id)),
          d.event_id, d.title || ' in 5 minutes. Tap to confirm you''re here.');
      end if;
    else
      n := n + public.lucky_draw_notify(array(select a.user_id from public.lucky_draw_audience(d.id) a), d.event_id,
        d.title || ' in 5 minutes. Head to the stage.');
    end if;
  end loop;

  -- At draw_at: "starting now", then draw (if the host has not already).
  -- Only draws due in the last 2 hours, so an outage does not fire old ones.
  for d in
    update public.lucky_draws set start_notified_at = now()
     where status = 'scheduled' and start_notified_at is null
       and draw_at <= now() and draw_at > now() - interval '2 hours'
    returning id, event_id, title
  loop
    n := n + public.lucky_draw_notify(array(select a.user_id from public.lucky_draw_audience(d.id) a), d.event_id,
      d.title || ' is starting now. Winners are being picked.');
    begin
      perform public.lucky_draw_execute(d.id, null);
    exception when others then
      insert into public.lucky_draw_audit (draw_id, action, detail) values (d.id, 'auto_run_failed', jsonb_build_object('error', sqlerrm));
    end;
  end loop;

  n := n + public.lucky_draw_expire();
  return n;
end;
$$;

-- =============================================================================
-- grants
-- =============================================================================
revoke execute on function public.agenda_place(text, uuid) from public, anon, authenticated;
revoke execute on function public.due_agenda_reminders() from public, anon, authenticated;
revoke execute on function public.lucky_draw_presence_open(public.lucky_draws) from public, anon, authenticated;
revoke execute on function public.lucky_draw_eligible(uuid) from public, anon, authenticated;
revoke execute on function public.due_lucky_draws() from public, anon, authenticated;
revoke execute on function public.event_agenda_list(uuid) from public, anon;
revoke execute on function public.save_agenda_item(uuid, uuid, text, timestamptz, timestamptz, text, uuid, text) from public, anon;
revoke execute on function public.delete_agenda_item(uuid) from public, anon;
revoke execute on function public.toggle_agenda_reminder(uuid) from public, anon;
revoke execute on function public.save_lucky_draw(uuid, uuid, text, timestamptz, timestamptz, boolean, int, jsonb, int) from public, anon;
revoke execute on function public.confirm_draw_presence(uuid, float8, float8) from public, anon;
revoke execute on function public.draw_presence_count(uuid) from public, anon;
revoke execute on function public.my_draw_status(uuid) from public, anon;
revoke execute on function public.draw_results(uuid) from public, anon;
revoke execute on function public.draw_stage(uuid) from public, anon;

grant execute on function public.event_agenda_list(uuid) to authenticated;
grant execute on function public.save_agenda_item(uuid, uuid, text, timestamptz, timestamptz, text, uuid, text) to authenticated;
grant execute on function public.delete_agenda_item(uuid) to authenticated;
grant execute on function public.toggle_agenda_reminder(uuid) to authenticated;
grant execute on function public.save_lucky_draw(uuid, uuid, text, timestamptz, timestamptz, boolean, int, jsonb, int) to authenticated;
grant execute on function public.confirm_draw_presence(uuid, float8, float8) to authenticated;
grant execute on function public.draw_presence_count(uuid) to authenticated;
grant execute on function public.my_draw_status(uuid) to authenticated;
grant execute on function public.draw_results(uuid) to authenticated;
grant execute on function public.draw_stage(uuid) to authenticated;
