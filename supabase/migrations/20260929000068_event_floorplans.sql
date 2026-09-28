-- =============================================================================
-- Event floorplans: per-event levels (B2, L1, Rooftop…) with an organizer-uploaded
-- plan image each, typed pins placed on the image, and each member's own "I'm here"
-- spot. Phones cannot tell which deck of a car park they are on, so the member
-- says it: tap the plan, or scan a printed zone QR (`ttspot:zone:<pin_id>`).
--
-- Privacy: a member reads and writes only their own position. The host sees
-- counts per level (event_level_counts), never individual spots. Positions are
-- purged daily, one day after the event ends (cron job ttspot-purge-event-positions).
-- =============================================================================

-- levels ----------------------------------------------------------------------
create table if not exists public.event_floor_levels (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 24),
  sort        int not null default 0,
  image_path  text,                       -- storage path in bucket event-floorplans: <event_id>/<file>
  image_w     int check (image_w is null or image_w > 0),
  image_h     int check (image_h is null or image_h > 0),
  created_at  timestamptz not null default now()
);
create index if not exists event_floor_levels_event_idx on public.event_floor_levels (event_id, sort);

-- pins ------------------------------------------------------------------------
create table if not exists public.event_floor_pins (
  id                uuid primary key default gen_random_uuid(),
  level_id          uuid not null references public.event_floor_levels (id) on delete cascade,
  kind              text not null check (kind in ('zone','booth','stage','food','toilet','entrance','lift','ramp','parking','info','lucky_draw')),
  label             text not null default '' check (char_length(label) <= 60),
  x                 real not null check (x between 0 and 1),   -- fraction of image width
  y                 real not null check (y between 0 and 1),   -- fraction of image height
  partner_vendor_id uuid references public.vendors (id) on delete set null,
  created_at        timestamptz not null default now()
);
create index if not exists event_floor_pins_level_idx on public.event_floor_pins (level_id);

-- member positions ------------------------------------------------------------
create table if not exists public.event_positions (
  event_id     uuid not null references public.events (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  level_id     uuid not null references public.event_floor_levels (id) on delete cascade,
  x            real check (x is null or x between 0 and 1),
  y            real check (y is null or y between 0 and 1),
  zone_pin_id  uuid references public.event_floor_pins (id) on delete set null,
  updated_at   timestamptz not null default now(),
  primary key (event_id, user_id)
);
create index if not exists event_positions_level_idx on public.event_positions (level_id);

-- A position must point at a level (and zone) of the same event.
create or replace function public.event_positions_check() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.event_floor_levels l where l.id = new.level_id and l.event_id = new.event_id) then
    raise exception 'That level is not part of this meet';
  end if;
  if new.zone_pin_id is not null and not exists (select 1 from public.event_floor_pins p where p.id = new.zone_pin_id and p.level_id = new.level_id) then
    raise exception 'That zone is not on this level';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists event_positions_check on public.event_positions;
create trigger event_positions_check before insert or update on public.event_positions
  for each row execute function public.event_positions_check();

-- RLS -------------------------------------------------------------------------
alter table public.event_floor_levels enable row level security;
alter table public.event_floor_pins   enable row level security;
alter table public.event_positions    enable row level security;

-- Anyone who can see the event (events RLS applies inside the subquery) sees its plan.
drop policy if exists "floor_levels: read" on public.event_floor_levels;
create policy "floor_levels: read" on public.event_floor_levels for select to authenticated
  using (exists (select 1 from public.events e where e.id = event_id));
drop policy if exists "floor_levels: host insert" on public.event_floor_levels;
create policy "floor_levels: host insert" on public.event_floor_levels for insert to authenticated
  with check (public.is_meet_host(event_id));
drop policy if exists "floor_levels: host update" on public.event_floor_levels;
create policy "floor_levels: host update" on public.event_floor_levels for update to authenticated
  using (public.is_meet_host(event_id)) with check (public.is_meet_host(event_id));
drop policy if exists "floor_levels: host delete" on public.event_floor_levels;
create policy "floor_levels: host delete" on public.event_floor_levels for delete to authenticated
  using (public.is_meet_host(event_id));

create or replace function public.floor_level_event(p_level uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select event_id from public.event_floor_levels where id = p_level;
$$;

drop policy if exists "floor_pins: read" on public.event_floor_pins;
create policy "floor_pins: read" on public.event_floor_pins for select to authenticated
  using (exists (select 1 from public.event_floor_levels l where l.id = level_id));
drop policy if exists "floor_pins: host insert" on public.event_floor_pins;
create policy "floor_pins: host insert" on public.event_floor_pins for insert to authenticated
  with check (public.is_meet_host(public.floor_level_event(level_id)));
drop policy if exists "floor_pins: host update" on public.event_floor_pins;
create policy "floor_pins: host update" on public.event_floor_pins for update to authenticated
  using (public.is_meet_host(public.floor_level_event(level_id)))
  with check (public.is_meet_host(public.floor_level_event(level_id)));
drop policy if exists "floor_pins: host delete" on public.event_floor_pins;
create policy "floor_pins: host delete" on public.event_floor_pins for delete to authenticated
  using (public.is_meet_host(public.floor_level_event(level_id)));

-- Only you see your spot. No host or admin read policy on purpose.
drop policy if exists "event_positions: own read" on public.event_positions;
create policy "event_positions: own read" on public.event_positions for select to authenticated
  using (user_id = auth.uid());
drop policy if exists "event_positions: own insert" on public.event_positions;
create policy "event_positions: own insert" on public.event_positions for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists "event_positions: own update" on public.event_positions;
create policy "event_positions: own update" on public.event_positions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "event_positions: own delete" on public.event_positions;
create policy "event_positions: own delete" on public.event_positions for delete to authenticated
  using (user_id = auth.uid());

-- RPCs ------------------------------------------------------------------------

-- Host only: how many members have set their spot on each level. Counts, never positions.
create or replace function public.event_level_counts(p_event uuid)
returns table (level_id uuid, members int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_meet_host(p_event) then
    raise exception 'Only the host can see level counts';
  end if;
  return query
    select l.id, count(p.user_id)::int
    from public.event_floor_levels l
    left join public.event_positions p on p.level_id = l.id and p.event_id = p_event
    where l.event_id = p_event
    group by l.id;
end;
$$;

-- Scanning a printed zone QR (`ttspot:zone:<pin_id>`) puts me on that pin.
-- Returns the event and level so the app can open the plan there.
create or replace function public.set_position_from_zone(p_pin uuid)
returns table (event_id uuid, level_id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_pin public.event_floor_pins;
  v_event uuid;
begin
  if v_me is null then raise exception 'Sign in first'; end if;
  select * into v_pin from public.event_floor_pins where id = p_pin;
  if not found then raise exception 'That zone code is no longer on the plan'; end if;
  select l.event_id into v_event from public.event_floor_levels l where l.id = v_pin.level_id;
  insert into public.event_positions as ep (event_id, user_id, level_id, x, y, zone_pin_id)
  values (v_event, v_me, v_pin.level_id, v_pin.x, v_pin.y, v_pin.id)
  on conflict on constraint event_positions_pkey do update
    set level_id = excluded.level_id, x = excluded.x, y = excluded.y, zone_pin_id = excluded.zone_pin_id;
  return query select v_event, v_pin.level_id;
end;
$$;

-- Daily purge: spots are deleted one day after the event ends
-- (ends_at, or starts_at + 6 h like the rest of the app).
create or replace function public.purge_event_positions() returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  delete from public.event_positions p
  using public.events e
  where e.id = p.event_id
    and coalesce(e.ends_at, e.starts_at + interval '6 hours') < now() - interval '1 day';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke execute on function public.event_positions_check() from public, anon, authenticated;
revoke execute on function public.floor_level_event(uuid) from public, anon;
revoke execute on function public.event_level_counts(uuid) from public, anon;
revoke execute on function public.set_position_from_zone(uuid) from public, anon;
revoke execute on function public.purge_event_positions() from public, anon, authenticated;
grant execute on function public.floor_level_event(uuid) to authenticated;
grant execute on function public.event_level_counts(uuid) to authenticated;
grant execute on function public.set_position_from_zone(uuid) to authenticated;

do $outer$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron could not be created: %', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'ttspot-purge-event-positions') then
      perform cron.unschedule('ttspot-purge-event-positions');
    end if;
    perform cron.schedule('ttspot-purge-event-positions', '25 0 * * *', 'select public.purge_event_positions()');
  else
    raise notice 'pg_cron not available: run public.purge_event_positions() daily some other way';
  end if;
end;
$outer$;

-- storage: plan images ----------------------------------------------------------
-- Public read; the event's host writes under <event_id>/…
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('event-floorplans', 'event-floorplans', true, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- True when the first folder of a storage path is an event the caller hosts.
create or replace function public.floorplan_path_host(p_name text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v_folder text := (storage.foldername(p_name))[1];
begin
  if v_folder is null or v_folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return public.is_meet_host(v_folder::uuid);
end;
$$;
revoke execute on function public.floorplan_path_host(text) from public, anon;
grant execute on function public.floorplan_path_host(text) to authenticated;

drop policy if exists "event-floorplans: public read" on storage.objects;
create policy "event-floorplans: public read"
  on storage.objects for select using (bucket_id = 'event-floorplans');
drop policy if exists "event-floorplans: host upload" on storage.objects;
create policy "event-floorplans: host upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'event-floorplans' and public.floorplan_path_host(name));
drop policy if exists "event-floorplans: host update" on storage.objects;
create policy "event-floorplans: host update"
  on storage.objects for update to authenticated
  using (bucket_id = 'event-floorplans' and public.floorplan_path_host(name));
drop policy if exists "event-floorplans: host delete" on storage.objects;
create policy "event-floorplans: host delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'event-floorplans' and public.floorplan_path_host(name));
