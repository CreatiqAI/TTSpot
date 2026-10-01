-- =============================================================================
-- "Share location when TT Spot is closed" (off by default, per phone).
--
-- The phone's native code (an Android foreground service, an iOS location
-- manager) keeps sending the member's position after the app is swiped away.
-- It must never hold or refresh the Supabase session (refresh-token rotation
-- would log the member out), so it signs each ping with a per-phone secret:
--
--   create_location_token(device)  signed in. Returns the secret once; only its
--                                   sha256 is stored. One live token per phone.
--   push_location_by_token(...)     anon. Validates the token, throttles, obeys
--                                   the member's map visibility and writes
--                                   user_locations like update_my_location.
--   revoke_location_tokens(device)  signed in. Log out / turn the switch off.
--   revoke_location_token(token)    anon. The notification's Stop button, and
--                                   cleanup after a different member signs in.
--
-- Visibility never widens here: share_mode, ghost and share_radius_m are never
-- touched, and a member on Nobody (ghost) gets nothing stored at all.
-- =============================================================================

create table if not exists public.location_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  token_hash   bytea not null unique,
  device       text not null default 'phone' check (length(device) between 1 and 120),
  created_at   timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at   timestamptz
);
create index if not exists location_tokens_live_idx on public.location_tokens (user_id, device) where revoked_at is null;

-- No policies: only the security-definer functions below read or write it.
alter table public.location_tokens enable row level security;
revoke all on public.location_tokens from public, anon, authenticated;

-- ------------------------------------------------------------ create ---
create or replace function public.create_location_token(p_device text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  me       uuid := auth.uid();
  v_device text := left(coalesce(nullif(btrim(p_device), ''), 'phone'), 120);
  v_secret text;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if exists (select 1 from public.profiles where id = me and suspended_at is not null) then
    raise exception 'Account suspended';
  end if;

  -- One live token per phone: a new one replaces the old.
  update public.location_tokens set revoked_at = now()
   where user_id = me and device = v_device and revoked_at is null;
  -- And at most five phones per member (oldest go first).
  update public.location_tokens set revoked_at = now()
   where id in (select id from public.location_tokens
                 where user_id = me and revoked_at is null
                 order by created_at desc offset 4);

  v_secret := encode(extensions.gen_random_bytes(32), 'hex');   -- 64 hex chars, 256 bits
  insert into public.location_tokens (user_id, token_hash, device)
  values (me, extensions.digest(v_secret, 'sha256'), v_device);
  return v_secret;
end;
$$;

-- ------------------------------------------------------------ revoke ---
create or replace function public.revoke_location_tokens(p_device text default null)
returns int
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  n  int;
begin
  if me is null then raise exception 'Not signed in'; end if;
  update public.location_tokens set revoked_at = now()
   where user_id = me and revoked_at is null
     and (p_device is null or device = left(btrim(p_device), 120));
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Knowing the secret is proof enough to switch it off.
create or replace function public.revoke_location_token(p_token text)
returns void
language sql security definer set search_path = public as $$
  update public.location_tokens set revoked_at = now()
   where p_token is not null and length(p_token) = 64
     and token_hash = extensions.digest(p_token, 'sha256') and revoked_at is null;
$$;

-- -------------------------------------------------------------- push ---
-- Returns {"status": ...}:
--   ok         stored
--   throttled  last update < 20 s ago and moved < 50 m (or < 5 s ago at all)
--   hidden     the member is on Nobody (ghost): nothing stored
--   inaccurate the fix is worse than 1 km: nothing stored
--   bad_fix    lat/lng missing or out of range
--   invalid    unknown, revoked, idle for 30 days, or the account is suspended;
--              the phone stops and forgets the token
-- Unlike update_my_location it never creates check-ins or meet presence: the
-- member agreed to be seen on the map, not to be checked in while the app is shut.
-- p_speed (m/s) is accepted for the phones' sake and not stored.
create or replace function public.push_location_by_token(
  p_token    text,
  p_lat      float8,
  p_lng      float8,
  p_heading  float8 default null,
  p_accuracy float8 default null,
  p_speed    float8 default null)
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_tok   public.location_tokens;
  v_loc   public.user_locations;
  v_has   boolean;
  v_place public.places;
  v_event uuid;
begin
  if p_token is null or length(p_token) <> 64 then
    return json_build_object('status', 'invalid');
  end if;

  select * into v_tok from public.location_tokens
   where token_hash = extensions.digest(p_token, 'sha256') and revoked_at is null;
  if not found then
    return json_build_object('status', 'invalid');
  end if;

  -- A phone that has been silent for 30 days, or a suspended member: switch it off.
  if coalesce(v_tok.last_used_at, v_tok.created_at) < now() - interval '30 days'
     or exists (select 1 from public.profiles where id = v_tok.user_id and suspended_at is not null) then
    update public.location_tokens set revoked_at = now() where id = v_tok.id;
    return json_build_object('status', 'invalid');
  end if;

  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    return json_build_object('status', 'bad_fix');
  end if;

  select * into v_loc from public.user_locations where user_id = v_tok.user_id for update;
  v_has := found;

  -- Nobody (ghost): keep nothing, not even an invisible position.
  if v_has and (v_loc.ghost or v_loc.share_mode = 'ghost') then
    if v_tok.last_used_at is null or v_tok.last_used_at < now() - interval '10 minutes' then
      update public.location_tokens set last_used_at = now() where id = v_tok.id;
    end if;
    return json_build_object('status', 'hidden');
  end if;

  if p_accuracy is not null and p_accuracy > 1000 then
    return json_build_object('status', 'inaccurate');
  end if;

  -- Throttle: the app in the foreground (or a chatty phone) already said this.
  if v_has and v_loc.updated_at > now() - interval '20 seconds'
     and (v_loc.updated_at > now() - interval '5 seconds'
          or public.metres_between(v_loc.lat, v_loc.lng, p_lat, p_lng) < 50) then
    return json_build_object('status', 'throttled');
  end if;

  -- Snap to the nearest place within 150 m, as update_my_location does.
  select * into v_place from public.places p
   where abs(p.lat - p_lat) < 0.01 and abs(p.lng - p_lng) < 0.01
   order by public.metres_between(p_lat, p_lng, p.lat, p.lng)
   limit 1;
  if found and public.metres_between(p_lat, p_lng, v_place.lat, v_place.lng) > 150 then
    v_place := null;
  end if;

  -- Still at a live meet the member already checked in to: keep showing it.
  select e.id into v_event
    from public.events e
    join public.checkins c on c.event_id = e.id and c.user_id = v_tok.user_id
   where e.status = 'active'
     and now() between e.starts_at - interval '1 hour' and coalesce(e.ends_at, e.starts_at + interval '6 hours')
     and abs(e.lat - p_lat) < 0.01 and abs(e.lng - p_lng) < 0.01
     and public.metres_between(p_lat, p_lng, e.lat, e.lng) <= 500
   order by public.metres_between(p_lat, p_lng, e.lat, e.lng)
   limit 1;

  -- Same row, same columns and the same 24 h expiry as update_my_location:
  -- the map already labels a pin's age ("12 min ago"), and a shorter expiry
  -- would hide a parked friend sooner than when their app is open.
  insert into public.user_locations (user_id, lat, lng, heading, accuracy, place_id, event_id, updated_at, expires_at)
  values (v_tok.user_id, p_lat, p_lng, p_heading, p_accuracy, v_place.id, v_event, now(), now() + interval '24 hours')
  on conflict (user_id) do update
    set lat = excluded.lat, lng = excluded.lng, heading = excluded.heading, accuracy = excluded.accuracy,
        place_id = excluded.place_id, event_id = excluded.event_id,
        updated_at = now(), expires_at = now() + interval '24 hours';

  update public.location_tokens set last_used_at = now() where id = v_tok.id;
  return json_build_object('status', 'ok');
end;
$$;

-- ------------------------------------------------------------ grants ---
revoke execute on function public.create_location_token(text) from public, anon, authenticated;
revoke execute on function public.revoke_location_tokens(text) from public, anon, authenticated;
revoke execute on function public.revoke_location_token(text) from public, anon, authenticated;
revoke execute on function public.push_location_by_token(text, float8, float8, float8, float8, float8) from public, anon, authenticated;
grant execute on function public.create_location_token(text) to authenticated;
grant execute on function public.revoke_location_tokens(text) to authenticated;
grant execute on function public.revoke_location_token(text) to anon, authenticated;
grant execute on function public.push_location_by_token(text, float8, float8, float8, float8, float8) to anon, authenticated;
