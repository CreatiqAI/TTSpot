-- =============================================================================
-- Spot stickers (打卡点) with photo proof
--   places.sticker_secret → printed QR `ttspot://spot/<placeId>/<code>` ·
--   spot_verifications (pending → approved / rejected / review) ·
--   AI check runs in the `verify-spot-photo` Edge Function ·
--   admins (profiles.is_admin) review the leftovers in-app
-- =============================================================================

alter table public.profiles add column is_admin boolean not null default false;
update public.profiles set is_admin = true where username = 'testing';

create or replace function public.is_admin(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = p_user), false);
$$;

-- -----------------------------------------------------------------------------
-- stickers: one static code per spot (printed once); rotate the secret if a
-- sticker leaks and reprint
-- -----------------------------------------------------------------------------
alter table public.places add column sticker_secret text not null default encode(extensions.gen_random_bytes(16), 'hex');

create or replace function public.spot_sticker_code(p_place uuid) returns text
language sql stable security definer set search_path = public as $$
  select substr(encode(extensions.hmac(p.id::text, p.sticker_secret, 'sha256'), 'hex'), 1, 12)
  from public.places p where p.id = p_place;
$$;
revoke execute on function public.spot_sticker_code(uuid) from public, anon, authenticated;

-- Admin-only: what to print on the sticker.
create or replace function public.admin_spot_sticker_payload(p_place uuid) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return 'ttspot://spot/' || p_place || '/' || public.spot_sticker_code(p_place);
end;
$$;

create or replace function public.admin_rotate_sticker(p_place uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  update public.places set sticker_secret = encode(extensions.gen_random_bytes(16), 'hex') where id = p_place;
end;
$$;

-- -----------------------------------------------------------------------------
-- verifications
-- -----------------------------------------------------------------------------
create table public.spot_verifications (
  id           uuid primary key default gen_random_uuid(),
  place_id     uuid not null references public.places (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  photo_url    text not null,
  lat          float8,
  lng          float8,
  distance_m   int,
  status       text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'review')),
  ai_result    jsonb,
  reason       text,
  story_id     uuid references public.stories (id) on delete set null,
  created_at   timestamptz not null default now(),
  day          date generated always as ((created_at at time zone 'Asia/Kuala_Lumpur')::date) stored,
  decided_at   timestamptz,
  decided_by   uuid references public.profiles (id) on delete set null,
  unique (place_id, user_id, day)
);
create index spot_verifications_user_idx on public.spot_verifications (user_id, created_at desc);
create index spot_verifications_status_idx on public.spot_verifications (status, created_at) where status in ('pending', 'review');

alter table public.spot_verifications enable row level security;
create policy "spot_verifications: read own or admin" on public.spot_verifications for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
-- all writes go through the RPCs below

-- Step 1 (app): sticker scanned, photo uploaded, GPS attached. Creates the pending row.
create or replace function public.submit_spot_verification(p_place uuid, p_code text, p_photo_url text, p_lat float8, p_lng float8)
returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  pl public.places;
  d  int;
  v_id uuid;
begin
  if me is null then raise exception 'Not signed in'; end if;
  select * into pl from public.places where id = p_place;
  if not found then raise exception 'This spot no longer exists'; end if;
  if p_code is null or p_code <> public.spot_sticker_code(p_place) then
    raise exception 'That sticker isn''t valid for this spot';
  end if;
  if p_photo_url is null or p_photo_url = '' then raise exception 'Add a photo of your car at the spot'; end if;
  if (select count(*) from public.spot_verifications where user_id = me and status in ('pending', 'review')) >= 5 then
    raise exception 'You have 5 check-ins waiting for review already. Try again later.';
  end if;
  if p_lat is not null and p_lng is not null then
    d := round(public.metres_between(p_lat, p_lng, pl.lat, pl.lng))::int;
  end if;
  insert into public.spot_verifications (place_id, user_id, photo_url, lat, lng, distance_m)
  values (p_place, me, p_photo_url, p_lat, p_lng, d)
  on conflict (place_id, user_id, day) do nothing
  returning id into v_id;
  if v_id is null then
    raise exception 'You already checked in here today';
  end if;
  return json_build_object('id', v_id, 'distance_m', d);
end;
$$;

-- Internal: approve → the photo becomes a moment at the spot (which also
-- creates the plain check-in + cover), then the verified bonus.
create or replace function public.decide_spot_verification(p_id uuid, p_approve boolean, p_reason text, p_by uuid, p_ai jsonb default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v public.spot_verifications;
  pl public.places;
  s_id uuid;
  pts int := public.rule_points('spot_verified');
begin
  select * into v from public.spot_verifications where id = p_id for update;
  if not found then raise exception 'No such verification'; end if;
  if v.status in ('approved', 'rejected') then return; end if;
  select * into pl from public.places where id = v.place_id;

  if p_approve then
    insert into public.stories (author_id, photo_url, caption, lat, lng, place_id)
    values (v.user_id, v.photo_url, 'Verified check-in', coalesce(v.lat, pl.lat), coalesce(v.lng, pl.lng), v.place_id)
    returning id into s_id;
    perform public.award_points(v.user_id, pts, 'spot_verified', 'place', v.place_id::text, pl.name,
      'spot_verified:' || v.place_id || ':' || v.user_id || ':' || v.day);
    update public.spot_verifications
      set status = 'approved', reason = p_reason, decided_at = now(), decided_by = p_by, story_id = s_id,
          ai_result = coalesce(p_ai, ai_result)
      where id = p_id;
    perform public.notify(v.user_id, null, 'points', p_body => '+' || pts || ' · verified check-in at ' || pl.name);
  else
    update public.spot_verifications
      set status = 'rejected', reason = p_reason, decided_at = now(), decided_by = p_by, ai_result = coalesce(p_ai, ai_result)
      where id = p_id;
    perform public.notify(v.user_id, null, 'points', p_body => 'Check-in at ' || pl.name || ' not approved: ' || coalesce(p_reason, 'no reason given'));
  end if;
end;
$$;
-- only the Edge Function (service role) and the admin RPC below may decide
revoke execute on function public.decide_spot_verification(uuid, boolean, text, uuid, jsonb) from public, anon, authenticated;

-- Internal: park it for a human.
create or replace function public.hold_spot_verification(p_id uuid, p_reason text, p_ai jsonb)
returns void
language sql security definer set search_path = public as $$
  update public.spot_verifications set status = 'review', reason = p_reason, ai_result = p_ai
  where id = p_id and status = 'pending';
$$;
revoke execute on function public.hold_spot_verification(uuid, text, jsonb) from public, anon, authenticated;

-- Admin-facing review.
create or replace function public.review_spot_verification(p_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  perform public.decide_spot_verification(p_id, p_approve, coalesce(p_note, case when p_approve then 'Approved by admin' else 'Rejected by admin' end), auth.uid());
end;
$$;

-- Lists for the UI.
create or replace function public.my_spot_verifications(p_limit int default 30)
returns table (id uuid, place_id uuid, place_name text, photo_url text, status text, reason text, distance_m int, created_at timestamptz, decided_at timestamptz)
language sql stable security definer set search_path = public as $$
  select v.id, v.place_id, p.name, v.photo_url, v.status, v.reason, v.distance_m, v.created_at, v.decided_at
  from public.spot_verifications v join public.places p on p.id = v.place_id
  where v.user_id = auth.uid()
  order by v.created_at desc
  limit p_limit;
$$;

create or replace function public.admin_review_queue(p_limit int default 100)
returns table (id uuid, place_id uuid, place_name text, place_lat float8, place_lng float8, user_id uuid, username text, avatar_url text,
               photo_url text, lat float8, lng float8, distance_m int, status text, reason text, ai_result jsonb, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select v.id, v.place_id, p.name, p.lat, p.lng, v.user_id, pr.username::text, pr.avatar_url,
           v.photo_url, v.lat, v.lng, v.distance_m, v.status, v.reason, v.ai_result, v.created_at
    from public.spot_verifications v
    join public.places p on p.id = v.place_id
    join public.profiles pr on pr.id = v.user_id
    where v.status in ('pending', 'review')
    order by v.created_at asc
    limit p_limit;
end;
$$;

-- Anything the AI never got to (app crashed mid-flow) gets a human after 24 h.
select cron.schedule('ttspot-stale-verifications', '*/30 * * * *',
  $$update public.spot_verifications set status = 'review', reason = 'Automatic check did not complete'
    where status = 'pending' and created_at < now() - interval '24 hours'$$);
