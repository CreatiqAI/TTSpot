-- Listed public events: real public car events TT Spot doesn't organise
-- (MIAPEX, MotoGP at Sepang, the Sepang 12 Hours), added from the official
-- TiTi account. TiTi lists them; TiTi is not the host.
--
-- 1. events.is_listing / organiser_name / source_url. The app shows
--    "Public event · by <organiser_name>", "Listed by TiTi" and an
--    "Official page" button (source_url), and hides the host tools.
-- 2. Only admins (or SQL / the service role, where auth.uid() is null) can
--    set or change those three columns, so a member can't pass a meet off as
--    someone else's public event.
-- 3. events_with_counts: the same view plus the three columns, at the end
--    (create or replace keeps its grants, security_invoker and anything that
--    selects from it: profile_meets reads it with to_json).
-- 4. A listing earns its lister nothing: no 'organiser' / 'convoy_captain'
--    badge on insert, no 'organizer' tier recompute, and badge_count's
--    'organizer' count skips listings (so the badge sweep can't pay for them
--    later either). Members going to or checking in at a listing still count.
--
-- Bodies of on_event_insert, on_badge_activity and badge_count are the live
-- ones (pg_get_functiondef, 2026-10-09) plus the listing checks.

-- 1. Columns ---------------------------------------------------------------

alter table public.events
  add column if not exists is_listing boolean not null default false,
  add column if not exists organiser_name text,
  add column if not exists source_url text;

alter table public.events drop constraint if exists events_organiser_name_len;
alter table public.events add constraint events_organiser_name_len
  check (organiser_name is null or char_length(organiser_name) between 1 and 120);

alter table public.events drop constraint if exists events_source_url_ok;
alter table public.events add constraint events_source_url_ok
  check (source_url is null or (char_length(source_url) <= 300 and source_url ~* '^https?://'));

comment on column public.events.is_listing is
  'A public event TT Spot lists but does not organise. organizer_id is the account that listed it (TiTi), not the host.';
comment on column public.events.organiser_name is
  'Who really runs a listed public event, shown as "Public event · by <name>".';
comment on column public.events.source_url is
  'The official page of a listed public event (http/https).';

-- 2. Only admins set the listing columns -------------------------------------

create or replace function public.guard_event_listing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- SQL editor, service role and admins may list.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.is_listing or new.organiser_name is not null or new.source_url is not null then
      raise exception 'Only TT Spot can list public events.';
    end if;
  elsif new.is_listing is distinct from old.is_listing
     or new.organiser_name is distinct from old.organiser_name
     or new.source_url is distinct from old.source_url then
    raise exception 'Only TT Spot can change a public listing.';
  end if;
  return new;
end;
$$;

drop trigger if exists events_guard_listing on public.events;
create trigger events_guard_listing
  before insert or update on public.events
  for each row execute function public.guard_event_listing();

-- 3. The view ----------------------------------------------------------------

create or replace view public.events_with_counts
with (security_invoker = true) as
 SELECT id,
    organizer_id,
    title,
    description,
    event_type,
    cover_url,
    starts_at,
    venue_name,
    lat,
    lng,
    max_attendees,
    status,
    created_at,
    place_id,
    club_id,
    is_instant,
    ends_at,
    visibility,
    address,
    vendor_id,
    (( SELECT count(*) AS count
           FROM event_attendees a
          WHERE (a.event_id = e.id)))::integer AS attendee_count,
    (( SELECT count(*) AS count
           FROM checkins c
          WHERE (c.event_id = e.id)))::integer AS checkin_count,
    ( SELECT v.name
           FROM vendors v
          WHERE (v.id = e.vendor_id)) AS vendor_name,
    ( SELECT v.logo_url
           FROM vendors v
          WHERE (v.id = e.vendor_id)) AS vendor_logo_url,
    ( SELECT c.name
           FROM clubs c
          WHERE (c.id = e.club_id)) AS club_name,
    ( SELECT c.tier
           FROM clubs c
          WHERE (c.id = e.club_id)) AS club_tier,
    ( SELECT c.avatar_url
           FROM clubs c
          WHERE (c.id = e.club_id)) AS club_avatar_url,
    COALESCE(( SELECT p.is_organizer
           FROM profiles p
          WHERE (p.id = e.organizer_id)), false) AS host_is_organizer,
    is_listing,
    organiser_name,
    source_url
   FROM events e;

-- The grants it had (Supabase's defaults: everything to these roles).
grant all on public.events_with_counts to anon, authenticated, service_role;

-- 4. No badges or points for listing ------------------------------------------

create or replace function public.on_event_insert()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  -- A listing is someone else's public event: no host badges for the lister.
  if not coalesce(new.is_listing, false) then
    perform public.award_badge(new.organizer_id, 'organiser');
    if new.event_type = 'convoy' then perform public.award_badge(new.organizer_id, 'convoy_captain'); end if;
  end if;
  if new.place_id is null and not coalesce(new.is_instant, false) then
    select id into new.place_id from public.places
    where lower(name) = lower(new.venue_name)
      and abs(lat - new.lat) < 0.0015 and abs(lng - new.lng) < 0.0015
    limit 1;
    if new.place_id is null then
      insert into public.places (name, kind, lat, lng, created_by)
      values (new.venue_name, case when new.event_type = 'trackday' then 'circuit' when new.event_type = 'tt' then 'mamak' else 'carpark' end, new.lat, new.lng, new.organizer_id)
      returning id into new.place_id;
    end if;
  end if;
  return new;
end; $function$;

create or replace function public.on_badge_activity()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  begin
    case tg_table_name
      when 'posts' then
        perform public.recompute_badges(new.author_id, 'posts');
      when 'follows' then
        perform public.recompute_badges(new.followee_id, 'popular');
      when 'place_checkins' then
        perform public.recompute_badges(new.user_id, 'explorer');
      when 'checkins' then
        perform public.recompute_badges(new.user_id, 'explorer');
        perform public.recompute_badges(new.user_id, 'joiner');
      when 'event_attendees' then
        perform public.recompute_badges(new.user_id, 'joiner');
      when 'event_crew' then
        perform public.recompute_badges(new.user_id, 'organizer');
      when 'events' then
        -- A listing is not hosted by its lister.
        if not coalesce(new.is_listing, false) then
          perform public.recompute_badges(new.organizer_id, 'organizer');
        end if;
      else null;
    end case;
  exception when others then
    raise warning 'badge recompute failed on %: %', tg_table_name, sqlerrm;
  end;
  return null;
end;
$function$;

create or replace function public.badge_count(p_user uuid, p_badge text)
 returns integer
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare n int := 0;
begin
  if p_badge = 'posts' then
    select count(*) into n from public.posts p
     where p.author_id = p_user and p.moderation = 'ok' and not p.as_club and not p.as_vendor;
  elsif p_badge = 'organizer' then
    -- Listings (public events TT Spot only lists) never count as hosted.
    select count(*) into n from public.events e
     where e.id in (select x.id from public.events x where x.organizer_id = p_user
                    union
                    select k.event_id from public.event_crew k where k.user_id = p_user and k.role = 'cohost')
       and e.status = 'active' and e.starts_at <= now()
       and not e.is_listing;
  elsif p_badge = 'joiner' then
    select count(*) into n from public.events e
     where e.id in (select a.event_id from public.event_attendees a where a.user_id = p_user
                    union
                    select c.event_id from public.checkins c where c.user_id = p_user)
       and e.status = 'active' and e.starts_at <= now()
       and e.organizer_id <> p_user
       and not exists (select 1 from public.event_crew k where k.event_id = e.id and k.user_id = p_user and k.role = 'cohost');
  elsif p_badge = 'explorer' then
    select count(distinct x.k) into n from (
      select 'p' || pc.place_id::text as k from public.place_checkins pc where pc.user_id = p_user
      union
      select coalesce('p' || e.place_id::text, 'e' || e.id::text)
        from public.checkins c join public.events e on e.id = c.event_id
       where c.user_id = p_user and e.event_type <> 'tt'
    ) x;
  elsif p_badge = 'popular' then
    select count(*) into n from public.follows f where f.followee_id = p_user;
  end if;
  return coalesce(n, 0);
end;
$function$;
