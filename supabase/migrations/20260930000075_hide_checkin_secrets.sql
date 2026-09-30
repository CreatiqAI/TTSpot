-- =============================================================================
-- Hide the check-in secrets.
--
-- events.qr_secret and places.sticker_secret were plain table columns, so
-- Supabase's default table grants let anon and authenticated read them, and
-- events_with_counts / places_with_counts passed them through too. Anyone with
-- a secret can compute valid meet QR codes (HMAC of the 30 s window) and spot
-- sticker codes (HMAC of the place id), i.e. forge verified check-ins.
-- On top of that, event_qr_code_at(event, window) was executable by anon and
-- authenticated, which handed out valid codes directly.
--
-- Now:
--   event_secrets(event_id, qr_secret) / place_secrets(place_id, sticker_secret)
--     RLS on, no policies, no grants to anon/authenticated: only security
--     definer functions (owner postgres) and the service role can read them.
--     Existing secrets are copied over unchanged, so printed stickers and the
--     QR screens keep working.
--   New events / places get a secret from an after-insert trigger; the
--   event_secret() / place_secret() helpers also create one on demand, so a
--   code is never computed from a null secret (a null code would compare as
--   unknown and let any code through).
--   event_qr_code_at, spot_sticker_code, admin_rotate_sticker read/write the new
--   tables. event_qr_code_at is no longer callable by clients (only
--   event_qr_payload for the host/crew and checkin_by_qr use it).
--   events_with_counts / places_with_counts are recreated without the secret
--   columns (every other column unchanged); my_saved_places / nearest_spots
--   return places_with_counts rows, so they are dropped and recreated with it.
--   The old columns are dropped, so no future grant or view can leak them.
--
-- The app (lib/) never read either column: codes are made and checked
-- server-side through event_qr_payload, checkin_by_qr and
-- submit_spot_verification, whose signatures are unchanged.
-- =============================================================================

begin;

-- ------------------------------------------------------------------ tables ---
create table if not exists public.event_secrets (
  event_id  uuid primary key references public.events (id) on delete cascade,
  qr_secret text not null default encode(extensions.gen_random_bytes(16), 'hex')
);
create table if not exists public.place_secrets (
  place_id       uuid primary key references public.places (id) on delete cascade,
  sticker_secret text not null default encode(extensions.gen_random_bytes(16), 'hex')
);
comment on table public.event_secrets is 'Meet check-in QR secret per event. No client access: read only by security definer functions.';
comment on table public.place_secrets is 'Spot sticker secret per place. No client access: read only by security definer functions.';

alter table public.event_secrets enable row level security;
alter table public.place_secrets enable row level security;
-- no policies on purpose; and no table grants either (Supabase grants new
-- public tables to anon/authenticated by default)
revoke all on table public.event_secrets from public, anon, authenticated;
revoke all on table public.place_secrets from public, anon, authenticated;

-- ---------------------------------------------------------------- backfill ---
-- Same secrets as before. Guarded so the block is a no-op once the columns are gone.
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'events' and column_name = 'qr_secret') then
    execute 'insert into public.event_secrets (event_id, qr_secret)
             select id, qr_secret from public.events where qr_secret is not null
             on conflict (event_id) do nothing';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'places' and column_name = 'sticker_secret') then
    execute 'insert into public.place_secrets (place_id, sticker_secret)
             select id, sticker_secret from public.places where sticker_secret is not null
             on conflict (place_id) do nothing';
  end if;
end;
$$;
-- anything still without a secret gets a fresh one
insert into public.event_secrets (event_id) select id from public.events on conflict (event_id) do nothing;
insert into public.place_secrets (place_id) select id from public.places on conflict (place_id) do nothing;

-- ----------------------------------------------------------------- helpers ---
-- The event's secret, created if missing. Null only when the event doesn't exist.
create or replace function public.event_secret(p_event uuid) returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  v text;
begin
  select qr_secret into v from public.event_secrets where event_id = p_event;
  if v is null then
    insert into public.event_secrets (event_id)
    select id from public.events where id = p_event
    on conflict (event_id) do nothing;
    select qr_secret into v from public.event_secrets where event_id = p_event;
  end if;
  return v;
end;
$$;

-- The place's sticker secret, created if missing. Null only when the place doesn't exist.
create or replace function public.place_secret(p_place uuid) returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  v text;
begin
  select sticker_secret into v from public.place_secrets where place_id = p_place;
  if v is null then
    insert into public.place_secrets (place_id)
    select id from public.places where id = p_place
    on conflict (place_id) do nothing;
    select sticker_secret into v from public.place_secrets where place_id = p_place;
  end if;
  return v;
end;
$$;

revoke all on function public.event_secret(uuid) from public, anon, authenticated;
revoke all on function public.place_secret(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- triggers ---
create or replace function public.make_event_secret() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.event_secrets (event_id) values (new.id) on conflict (event_id) do nothing;
  return null;
end;
$$;

create or replace function public.make_place_secret() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.place_secrets (place_id) values (new.id) on conflict (place_id) do nothing;
  return null;
end;
$$;

revoke all on function public.make_event_secret() from public, anon, authenticated;
revoke all on function public.make_place_secret() from public, anon, authenticated;

drop trigger if exists events_make_secret on public.events;
create trigger events_make_secret after insert on public.events
  for each row execute function public.make_event_secret();
drop trigger if exists places_make_secret on public.places;
create trigger places_make_secret after insert on public.places
  for each row execute function public.make_place_secret();

-- -------------------------------------------------------------- code makers ---
-- Meet check-in code for a 30 s window. Same HMAC as before (first 10 hex chars
-- of HMAC-SHA256(window, secret)). Volatile now: it may create the secret.
create or replace function public.event_qr_code_at(p_event uuid, p_window bigint) returns text
language sql volatile security definer set search_path = public as $$
  select substr(encode(extensions.hmac(p_window::text, public.event_secret(p_event), 'sha256'), 'hex'), 1, 10);
$$;
-- Only event_qr_payload (host / crew) and checkin_by_qr call this; both are
-- security definer, so clients never need it directly.
revoke all on function public.event_qr_code_at(uuid, bigint) from public, anon, authenticated;

-- Spot sticker code. Same HMAC as before (first 12 hex chars of
-- HMAC-SHA256(place id, secret)); null when the place doesn't exist.
create or replace function public.spot_sticker_code(p_place uuid) returns text
language sql volatile security definer set search_path = public as $$
  select substr(encode(extensions.hmac(p_place::text, public.place_secret(p_place), 'sha256'), 'hex'), 1, 12);
$$;
revoke all on function public.spot_sticker_code(uuid) from public, anon, authenticated;

-- Admin: new sticker secret for a spot (the old sticker stops working; reprint).
create or replace function public.admin_rotate_sticker(p_place uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  insert into public.place_secrets (place_id)
  select id from public.places where id = p_place
  on conflict (place_id) do update set sticker_secret = encode(extensions.gen_random_bytes(16), 'hex');
end;
$$;

-- -------------------------------------------------------------------- views ---
-- my_saved_places / nearest_spots return setof places_with_counts, so they go
-- first and come back after the view (same bodies and grants as 0070).
drop function if exists public.my_saved_places();
drop function if exists public.nearest_spots(float8, float8, int);
drop view if exists public.events_with_counts;
drop view if exists public.places_with_counts;

-- As live before this migration, minus e.qr_secret.
create view public.events_with_counts
with (security_invoker = true) as
select e.id, e.organizer_id, e.title, e.description, e.event_type, e.cover_url, e.starts_at, e.venue_name, e.lat, e.lng, e.max_attendees,
       e.status, e.created_at, e.place_id, e.club_id, e.is_instant, e.ends_at, e.visibility, e.address, e.vendor_id,
       (select count(*) from public.event_attendees a where a.event_id = e.id)::int as attendee_count,
       (select count(*) from public.checkins c where c.event_id = e.id)::int as checkin_count,
       (select v.name from public.vendors v where v.id = e.vendor_id) as vendor_name,
       (select v.logo_url from public.vendors v where v.id = e.vendor_id) as vendor_logo_url,
       (select c.name from public.clubs c where c.id = e.club_id) as club_name,
       (select c.tier from public.clubs c where c.id = e.club_id) as club_tier
from public.events e;

-- As live before this migration (0071), minus p.sticker_secret. The p.* of
-- earlier versions is spelled out so the column list stays exactly the same.
create view public.places_with_counts
with (security_invoker = true) as
with act as (
  select p.id,
         (select count(*) from public.place_checkins pc where pc.place_id = p.id and pc.checked_in_at > now() - interval '90 days')::int as checkins_90d,
         (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.event_type <> 'tt'
                 and e.starts_at >= now() - interval '90 days' and e.starts_at <= now())::int as meets_90d
  from public.places p
)
select
  p.id, p.name, p.kind, p.lat, p.lng, p.created_by, p.created_at, p.cover_url, p.description, p.tags, p.recommended,
  p.top_override, p.vendor_id,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now())::int  as past_meets,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at >= now())::int as upcoming_meets,
  (select max(e.starts_at) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now()) as last_meet_at,
  (select count(*) from public.checkins c join public.events e on e.id = c.event_id where e.place_id = p.id)::int      as checkins_total,
  (select count(*) from public.place_checkins pc where pc.place_id = p.id)::int                                          as spot_checkins,
  (select count(*) from public.posts po where po.place_id = p.id)::int                                                  as post_count,
  (select count(*) from public.stories s where s.place_id = p.id)::int                                                  as moment_count,
  a.checkins_90d,
  a.meets_90d,
  (
    (case when p.recommended then 100 else 0 end)
    + 3 * (select count(*) from public.place_checkins pc where pc.place_id = p.id)
    + 5 * (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now())
    + 2 * (select count(*) from public.posts po where po.place_id = p.id)
    + 1 * (select count(*) from public.stories s where s.place_id = p.id)
  )::int as score,
  (
    not exists (select 1 from public.archived_places ar where ar.place_id = p.id)
    and (
    p.recommended
    or p.vendor_id is not null
    or p.cover_url is not null
    or exists (select 1 from public.place_checkins pc where pc.place_id = p.id)
    or exists (select 1 from public.posts po where po.place_id = p.id)
    or exists (select 1 from public.stories s where s.place_id = p.id)
    or exists (select 1 from public.place_suggestions sg where sg.place_id = p.id and sg.status = 'approved')
    )
  ) as is_spot,
  (not exists (select 1 from public.archived_places ar where ar.place_id = p.id) and case p.top_override
     when 'top' then true
     when 'never' then false
     else (p.recommended or a.checkins_90d >= 20 or a.meets_90d >= 3)
   end) as is_top,
  (select vd.logo_url from public.vendors vd where vd.id = p.vendor_id) as vendor_logo,
  (select vd.name from public.vendors vd where vd.id = p.vendor_id) as vendor_name
from public.places p
join act a on a.id = p.id;

-- Same grants as before (what Supabase's default privileges gave the old views).
grant all on public.events_with_counts to anon, authenticated, service_role;
grant all on public.places_with_counts to anon, authenticated, service_role;

create or replace function public.my_saved_places() returns setof public.places_with_counts
language sql stable security invoker set search_path = public as $$
  select v.*
  from public.place_saves s
  join public.places_with_counts v on v.id = s.place_id
  where s.user_id = auth.uid()
  order by s.created_at desc
  limit 200;
$$;

create or replace function public.nearest_spots(p_lat float8, p_lng float8, p_limit int default 5) returns setof public.places_with_counts
language sql stable security invoker set search_path = public as $$
  select v.*
  from public.places_with_counts v
  where v.is_spot
  order by public.metres_between(p_lat, p_lng, v.lat, v.lng)
  limit greatest(1, least(coalesce(p_limit, 5), 50));
$$;

revoke all on function public.my_saved_places() from public, anon;
revoke all on function public.nearest_spots(float8, float8, int) from public, anon;
grant execute on function public.my_saved_places() to authenticated;
grant execute on function public.nearest_spots(float8, float8, int) to authenticated;

-- ------------------------------------------------------------ drop columns ---
alter table public.events drop column if exists qr_secret;
alter table public.places drop column if exists sticker_secret;

notify pgrst, 'reload schema';

commit;
