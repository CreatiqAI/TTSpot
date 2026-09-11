-- =============================================================================
-- Malaysian Car Meet App — initial schema
-- Apply with:  supabase db push   (remote)   or   supabase db reset (local)
-- =============================================================================

-- Extensions ------------------------------------------------------------------
create extension if not exists citext;        -- case-insensitive usernames
create extension if not exists pgcrypto;      -- gen_random_uuid()

-- Enums -----------------------------------------------------------------------
create type public.event_type   as enum ('meet', 'tt', 'convoy', 'trackday', 'charity', 'official');
create type public.event_status as enum ('active', 'cancelled');
create type public.report_target as enum ('event', 'comment', 'profile');

-- =============================================================================
-- Tables
-- =============================================================================

-- profiles --------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  username      citext unique,                       -- null until onboarding done
  display_name  text,
  bio           text,
  avatar_url    text,
  home_state    text,                                -- e.g. 'Selangor'
  created_at    timestamptz not null default now(),
  constraint username_format check (
    username is null or username ~ '^[a-z0-9_]{3,20}$'
  ),
  constraint bio_length check (bio is null or char_length(bio) <= 300)
);

-- cars ------------------------------------------------------------------------
create table public.cars (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.profiles (id) on delete cascade,
  make          text not null,
  model         text not null,
  year          int  check (year is null or (year >= 1950 and year <= 2100)),
  description   text check (description is null or char_length(description) <= 500),
  photo_urls    text[] not null default '{}' check (cardinality(photo_urls) <= 5),
  created_at    timestamptz not null default now()
);
create index cars_owner_idx on public.cars (owner_id);

-- events ----------------------------------------------------------------------
create table public.events (
  id             uuid primary key default gen_random_uuid(),
  organizer_id   uuid not null references public.profiles (id) on delete cascade,
  title          text not null check (char_length(title) between 3 and 80),
  description    text check (description is null or char_length(description) <= 2000),
  event_type     public.event_type not null default 'meet',
  cover_url      text,
  starts_at      timestamptz not null,
  venue_name     text not null,
  lat            float8 not null check (lat between -90 and 90),
  lng            float8 not null check (lng between -180 and 180),
  max_attendees  int check (max_attendees is null or max_attendees > 0),
  status         public.event_status not null default 'active',
  created_at     timestamptz not null default now()
);
create index events_starts_at_idx on public.events (starts_at);
create index events_lat_lng_idx   on public.events (lat, lng);   -- bounding-box queries
create index events_organizer_idx on public.events (organizer_id);

-- event_attendees -------------------------------------------------------------
create table public.event_attendees (
  event_id    uuid not null references public.events (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (event_id, user_id)
);
create index event_attendees_user_idx on public.event_attendees (user_id);

-- event_comments --------------------------------------------------------------
create table public.event_comments (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 1000),
  created_at  timestamptz not null default now()
);
create index event_comments_event_idx on public.event_comments (event_id, created_at);

-- reports ---------------------------------------------------------------------
create table public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references public.profiles (id) on delete cascade,
  target_type  public.report_target not null,
  target_id    uuid not null,
  reason       text not null check (char_length(reason) between 1 and 500),
  created_at   timestamptz not null default now()
);

-- blocks ----------------------------------------------------------------------
create table public.blocks (
  blocker_id  uuid not null references public.profiles (id) on delete cascade,
  blocked_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);

-- =============================================================================
-- Auto-create a profile row when a user signs up (email or Google)
-- =============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =============================================================================
-- View: events + attendee count (keeps client queries to one round trip)
-- security_invoker means the caller's RLS on `events` still applies.
-- =============================================================================
create or replace view public.events_with_counts
with (security_invoker = true) as
select
  e.*,
  (select count(*) from public.event_attendees a where a.event_id = e.id)::int as attendee_count
from public.events e;

-- =============================================================================
-- Enforce max_attendees at the database level (RLS can't count rows)
-- =============================================================================
create or replace function public.check_event_capacity()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  cap int;
  cnt int;
begin
  select max_attendees into cap from public.events where id = new.event_id;
  if cap is not null then
    select count(*) into cnt from public.event_attendees where event_id = new.event_id;
    if cnt >= cap then
      raise exception 'Event is full' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger event_attendees_capacity
  before insert on public.event_attendees
  for each row execute function public.check_event_capacity();

-- =============================================================================
-- Row Level Security
-- =============================================================================
alter table public.profiles        enable row level security;
alter table public.cars            enable row level security;
alter table public.events          enable row level security;
alter table public.event_attendees enable row level security;
alter table public.event_comments  enable row level security;
alter table public.reports         enable row level security;
alter table public.blocks          enable row level security;

-- profiles --------------------------------------------------------------------
create policy "profiles: authenticated can read"
  on public.profiles for select to authenticated using (true);

create policy "profiles: owner can insert"
  on public.profiles for insert to authenticated with check (id = auth.uid());

create policy "profiles: owner can update"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
-- (no delete policy: deleting the auth user cascades the profile)

-- cars ------------------------------------------------------------------------
create policy "cars: authenticated can read"
  on public.cars for select to authenticated using (true);

create policy "cars: owner can insert"
  on public.cars for insert to authenticated with check (owner_id = auth.uid());

create policy "cars: owner can update"
  on public.cars for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "cars: owner can delete"
  on public.cars for delete to authenticated using (owner_id = auth.uid());

-- events ----------------------------------------------------------------------
create policy "events: authenticated can read"
  on public.events for select to authenticated using (true);

create policy "events: organizer can insert"
  on public.events for insert to authenticated with check (organizer_id = auth.uid());

create policy "events: organizer can update"           -- includes status -> cancelled
  on public.events for update to authenticated
  using (organizer_id = auth.uid()) with check (organizer_id = auth.uid());

create policy "events: organizer can delete"
  on public.events for delete to authenticated using (organizer_id = auth.uid());

-- event_attendees -------------------------------------------------------------
create policy "attendees: authenticated can read"
  on public.event_attendees for select to authenticated using (true);

create policy "attendees: user can join"
  on public.event_attendees for insert to authenticated with check (user_id = auth.uid());

create policy "attendees: user can leave"
  on public.event_attendees for delete to authenticated using (user_id = auth.uid());

-- event_comments --------------------------------------------------------------
create policy "comments: authenticated can read"
  on public.event_comments for select to authenticated using (true);

create policy "comments: author can insert"
  on public.event_comments for insert to authenticated with check (user_id = auth.uid());

create policy "comments: author can update"
  on public.event_comments for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "comments: author can delete"
  on public.event_comments for delete to authenticated using (user_id = auth.uid());

-- reports (users write; you read them in the Supabase dashboard) --------------
create policy "reports: reporter can insert"
  on public.reports for insert to authenticated with check (reporter_id = auth.uid());

create policy "reports: reporter can read own"
  on public.reports for select to authenticated using (reporter_id = auth.uid());

-- blocks (private to the blocker) ---------------------------------------------
create policy "blocks: blocker can read own"
  on public.blocks for select to authenticated using (blocker_id = auth.uid());

create policy "blocks: blocker can insert"
  on public.blocks for insert to authenticated with check (blocker_id = auth.uid());

create policy "blocks: blocker can delete"
  on public.blocks for delete to authenticated using (blocker_id = auth.uid());

-- =============================================================================
-- Storage buckets (public-read; writes restricted to the uploader's folder)
-- Object path convention:  <bucket>/<user_id>/<filename>
-- =============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',      'avatars',      true, 2097152, array['image/jpeg','image/png','image/webp']),
  ('event-covers', 'event-covers', true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('car-photos',   'car-photos',   true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "storage: public read"
  on storage.objects for select
  using (bucket_id in ('avatars', 'event-covers', 'car-photos'));

create policy "storage: owner can upload to own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('avatars', 'event-covers', 'car-photos')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "storage: owner can update own files"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('avatars', 'event-covers', 'car-photos')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "storage: owner can delete own files"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('avatars', 'event-covers', 'car-photos')
    and (storage.foldername(name))[1] = auth.uid()::text
  );
