-- =============================================================================
-- TT Spot — social layer
-- follows, places, clubs, posts (post / spotted / poll / guide), likes, saves,
-- comments, poll votes, stories, notifications, badges, car mods (build log),
-- car of the week, conversations (DM + meet chat), messages, scheduled jobs.
-- =============================================================================

create extension if not exists pg_cron;

create type public.post_kind as enum ('post', 'spotted', 'poll', 'guide');
create type public.notification_type as enum (
  'follow', 'post_like', 'post_comment', 'event_join', 'event_comment',
  'event_reminder', 'event_cancelled', 'spotted_claim', 'badge', 'car_of_week', 'club_join'
);

-- =============================================================================
-- follows
-- =============================================================================
create table public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint no_self_follow check (follower_id <> followee_id)
);
create index follows_followee_idx on public.follows (followee_id);

-- =============================================================================
-- places (venues): mamak, carpark, circuit …
-- =============================================================================
create table public.places (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 2 and 80),
  kind        text not null default 'other',       -- mamak | carpark | circuit | mall | route | other
  lat         float8 not null check (lat between -90 and 90),
  lng         float8 not null check (lng between -180 and 180),
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index places_lat_lng_idx on public.places (lat, lng);
create index places_name_idx on public.places (lower(name));

-- =============================================================================
-- clubs
-- =============================================================================
create table public.clubs (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 2 and 60),
  handle       citext unique not null check (handle ~ '^[a-z0-9_]{3,24}$'),
  description  text check (description is null or char_length(description) <= 500),
  avatar_url   text,
  home_state   text,
  owner_id     uuid not null references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now()
);

create table public.club_members (
  club_id     uuid not null references public.clubs (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        text not null default 'member',       -- owner | admin | member
  created_at  timestamptz not null default now(),
  primary key (club_id, user_id)
);
create index club_members_user_idx on public.club_members (user_id);

alter table public.events add column place_id uuid references public.places (id) on delete set null;
alter table public.events add column club_id  uuid references public.clubs (id) on delete set null;
create index events_place_idx on public.events (place_id);
create index events_club_idx on public.events (club_id);

-- =============================================================================
-- posts (one table, four kinds)
-- =============================================================================
create table public.posts (
  id            uuid primary key default gen_random_uuid(),
  author_id     uuid not null references public.profiles (id) on delete cascade,
  kind          public.post_kind not null default 'post',
  title         text check (title is null or char_length(title) <= 100),           -- guides, polls (question)
  caption       text check (caption is null or char_length(caption) <= 2200),
  photo_urls    text[] not null default '{}' check (cardinality(photo_urls) <= 10),
  cover_aspect  float8 not null default 1.0,                                          -- w/h of first photo, for masonry
  car_id        uuid references public.cars (id) on delete set null,
  event_id      uuid references public.events (id) on delete set null,
  place_id      uuid references public.places (id) on delete set null,
  club_id       uuid references public.clubs (id) on delete set null,
  lat           float8, lng float8,                                                   -- spotted location
  claimed_by    uuid references public.profiles (id) on delete set null,             -- spotted: the owner
  poll_options  jsonb,                                                                -- [{"text":"…","photo_url":null}]
  poll_ends_at  timestamptz,
  guide_stops   jsonb,                                                                -- [{"name":"…","lat":..,"lng":..}]
  created_at    timestamptz not null default now()
);
create index posts_created_idx on public.posts (created_at desc);
create index posts_author_idx  on public.posts (author_id, created_at desc);
create index posts_kind_idx    on public.posts (kind, created_at desc);
create index posts_event_idx   on public.posts (event_id);
create index posts_place_idx   on public.posts (place_id);
create index posts_car_idx     on public.posts (car_id);
create index posts_club_idx    on public.posts (club_id);

create table public.post_likes (
  post_id     uuid not null references public.posts (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index post_likes_user_idx on public.post_likes (user_id);

create table public.post_saves (
  post_id     uuid not null references public.posts (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index post_saves_user_idx on public.post_saves (user_id, created_at desc);

create table public.post_comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.posts (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 1000),
  created_at  timestamptz not null default now()
);
create index post_comments_post_idx on public.post_comments (post_id, created_at);

create table public.poll_votes (
  post_id       uuid not null references public.posts (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  option_index  int not null check (option_index between 0 and 3),
  created_at    timestamptz not null default now(),
  primary key (post_id, user_id)
);

create or replace view public.posts_with_counts
with (security_invoker = true) as
select
  p.*,
  (select count(*) from public.post_likes l where l.post_id = p.id)::int    as like_count,
  (select count(*) from public.post_comments c where c.post_id = p.id)::int as comment_count,
  (select count(*) from public.poll_votes v where v.post_id = p.id)::int    as vote_count
from public.posts p;

-- =============================================================================
-- stories (24h)
-- =============================================================================
create table public.stories (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references public.profiles (id) on delete cascade,
  photo_url   text not null,
  caption     text check (caption is null or char_length(caption) <= 200),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '24 hours'
);
create index stories_author_idx on public.stories (author_id, expires_at desc);
create index stories_expires_idx on public.stories (expires_at);

create table public.story_views (
  story_id    uuid not null references public.stories (id) on delete cascade,
  viewer_id   uuid not null references public.profiles (id) on delete cascade,
  viewed_at   timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

-- =============================================================================
-- notifications (written only by triggers / functions)
-- =============================================================================
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,   -- recipient
  actor_id    uuid references public.profiles (id) on delete cascade,
  type        public.notification_type not null,
  post_id     uuid references public.posts (id) on delete cascade,
  event_id    uuid references public.events (id) on delete cascade,
  club_id     uuid references public.clubs (id) on delete cascade,
  badge_id    text,
  body        text,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;

create or replace function public.notify(
  p_user uuid, p_actor uuid, p_type public.notification_type,
  p_post uuid default null, p_event uuid default null, p_club uuid default null,
  p_badge text default null, p_body text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_user = p_actor then return; end if;
  insert into public.notifications (user_id, actor_id, type, post_id, event_id, club_id, badge_id, body)
  values (p_user, p_actor, p_type, p_post, p_event, p_club, p_badge, p_body);
end;
$$;

-- =============================================================================
-- badges
-- =============================================================================
create table public.badges (
  id           text primary key,
  name         text not null,
  description  text not null,
  emoji        text not null,
  sort         int not null default 100
);

create table public.user_badges (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  badge_id    text not null references public.badges (id) on delete cascade,
  awarded_at  timestamptz not null default now(),
  primary key (user_id, badge_id)
);

insert into public.badges (id, name, description, emoji, sort) values
  ('first_meet',     'First Meet',      'Joined your first meet.',                     '🏁', 10),
  ('regular',        'Regular',         'Joined 10 meets.',                            '🔁', 20),
  ('tt_regular',     'TT Regular',      'Joined 5 teh tarik sessions.',                '☕', 30),
  ('organiser',      'Organiser',       'Hosted your first meet.',                     '📣', 40),
  ('convoy_captain', 'Convoy Captain',  'Led a convoy.',                               '🛣️', 50),
  ('garage_open',    'Garage Open',     'Added your first car.',                       '🚗', 60),
  ('first_post',     'First Post',      'Shared your first post.',                     '📸', 70),
  ('spotter',        'Spotter',         'Spotted 5 cars in the wild.',                 '👀', 80),
  ('guide_writer',   'Guide Writer',    'Wrote a guide for the community.',            '🗺️', 90),
  ('car_of_week',    'Car of the Week', 'Won Car of the Week.',                        '🏆', 5),
  ('popular',        'Popular',         '50 people follow you.',                       '⭐', 15);

create or replace function public.award_badge(p_user uuid, p_badge text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare inserted boolean;
begin
  insert into public.user_badges (user_id, badge_id) values (p_user, p_badge)
  on conflict do nothing;
  inserted := found;
  if inserted then
    insert into public.notifications (user_id, type, badge_id) values (p_user, 'badge', p_badge);
  end if;
  return inserted;
end;
$$;

-- Consecutive ISO weeks (ending this week or last week) with a TT session attended.
create or replace function public.tt_streak_weeks(p_user uuid)
returns int
language plpgsql stable security definer set search_path = public as $$
declare
  wk date := date_trunc('week', now())::date;
  streak int := 0;
begin
  -- allow the streak to still count if this week hasn't had one yet
  if not exists (
    select 1 from public.event_attendees a join public.events e on e.id = a.event_id
    where a.user_id = p_user and e.event_type = 'tt' and e.starts_at < now()
      and date_trunc('week', e.starts_at)::date = wk
  ) then
    wk := wk - 7;
  end if;
  loop
    exit when not exists (
      select 1 from public.event_attendees a join public.events e on e.id = a.event_id
      where a.user_id = p_user and e.event_type = 'tt' and e.starts_at < now()
        and date_trunc('week', e.starts_at)::date = wk
    );
    streak := streak + 1;
    wk := wk - 7;
  end loop;
  return streak;
end;
$$;

-- =============================================================================
-- car mods (build timeline)
-- =============================================================================
alter table public.cars add column show_spend boolean not null default true;

create table public.car_mods (
  id           uuid primary key default gen_random_uuid(),
  car_id       uuid not null references public.cars (id) on delete cascade,
  title        text not null check (char_length(title) between 2 and 80),
  description  text check (description is null or char_length(description) <= 500),
  cost         numeric(10,2) check (cost is null or cost >= 0),
  done_on      date not null default current_date,
  photo_urls   text[] not null default '{}' check (cardinality(photo_urls) <= 5),
  created_at   timestamptz not null default now()
);
create index car_mods_car_idx on public.car_mods (car_id, done_on desc);

-- =============================================================================
-- car of the week
-- =============================================================================
create table public.weekly_winners (
  week_start  date primary key,                      -- Monday
  post_id     uuid references public.posts (id) on delete set null,
  car_id      uuid references public.cars (id) on delete set null,
  user_id     uuid references public.profiles (id) on delete set null,
  like_count  int not null default 0,
  created_at  timestamptz not null default now()
);

-- Leader for the current week (most-liked car-tagged post since Monday).
create or replace function public.current_week_leader()
returns table (post_id uuid, car_id uuid, user_id uuid, like_count int)
language sql stable security invoker as $$
  select p.id, p.car_id, p.author_id,
         (select count(*) from public.post_likes l where l.post_id = p.id)::int as like_count
  from public.posts p
  where p.kind = 'post' and p.car_id is not null
    and p.created_at >= date_trunc('week', now())
  order by like_count desc, p.created_at asc
  limit 1;
$$;

-- Runs Monday 00:05 UTC (08:05 MYT): crowns last week's winner.
create or replace function public.pick_car_of_week()
returns void
language plpgsql security definer set search_path = public as $$
declare
  ws date := (date_trunc('week', now()) - interval '7 days')::date;
  we date := date_trunc('week', now())::date;
  w record;
begin
  if exists (select 1 from public.weekly_winners where week_start = ws) then return; end if;
  select p.id as post_id, p.car_id, p.author_id as user_id,
         (select count(*) from public.post_likes l where l.post_id = p.id)::int as like_count
    into w
  from public.posts p
  where p.kind = 'post' and p.car_id is not null
    and p.created_at >= ws and p.created_at < we
  order by like_count desc, p.created_at asc
  limit 1;
  if w.post_id is null then return; end if;
  insert into public.weekly_winners (week_start, post_id, car_id, user_id, like_count)
  values (ws, w.post_id, w.car_id, w.user_id, w.like_count);
  perform public.award_badge(w.user_id, 'car_of_week');
  insert into public.notifications (user_id, type, post_id, body)
  values (w.user_id, 'car_of_week', w.post_id, 'Your build is Car of the Week!');
end;
$$;

-- =============================================================================
-- conversations (DM + meet group chat) and messages
-- =============================================================================
create table public.conversations (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('dm', 'meet')),
  event_id    uuid unique references public.events (id) on delete cascade,      -- meet chats
  created_at  timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  last_read_at     timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index conversation_members_user_idx on public.conversation_members (user_id);

create table public.messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  sender_id        uuid not null references public.profiles (id) on delete cascade,
  body             text not null check (char_length(body) between 1 and 2000),
  created_at       timestamptz not null default now()
);
create index messages_conversation_idx on public.messages (conversation_id, created_at desc);

create or replace function public.is_conversation_member(p_conversation uuid, p_user uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = p_conversation and user_id = p_user
  );
$$;

-- Find or create the 1:1 conversation between the caller and p_other.
create or replace function public.get_or_create_dm(p_other uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  conv uuid;
begin
  if me is null or p_other is null or me = p_other then
    raise exception 'invalid participants';
  end if;
  select c.id into conv
  from public.conversations c
  where c.kind = 'dm'
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = me)
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = p_other)
  limit 1;
  if conv is null then
    insert into public.conversations (kind) values ('dm') returning id into conv;
    insert into public.conversation_members (conversation_id, user_id) values (conv, me), (conv, p_other);
  end if;
  return conv;
end;
$$;

-- Group chat for a meet; only attendees / organizer can enter. Ensures membership.
create or replace function public.get_or_create_meet_chat(p_event uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  conv uuid;
  allowed boolean;
begin
  if me is null then raise exception 'not signed in'; end if;
  select (e.organizer_id = me) or exists (select 1 from public.event_attendees a where a.event_id = e.id and a.user_id = me)
    into allowed
  from public.events e where e.id = p_event;
  if not coalesce(allowed, false) then raise exception 'Join the meet to open its chat'; end if;

  select id into conv from public.conversations where event_id = p_event;
  if conv is null then
    insert into public.conversations (kind, event_id) values ('meet', p_event) returning id into conv;
  end if;
  insert into public.conversation_members (conversation_id, user_id) values (conv, me) on conflict do nothing;
  return conv;
end;
$$;

create or replace function public.mark_conversation_read(p_conversation uuid)
returns void
language sql security definer set search_path = public as $$
  update public.conversation_members set last_read_at = now()
  where conversation_id = p_conversation and user_id = auth.uid();
$$;

-- Spotted: the owner claims the photo.
create or replace function public.claim_spotted(p_post uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  author uuid;
begin
  update public.posts set claimed_by = me
  where id = p_post and kind = 'spotted' and claimed_by is null and author_id <> me
  returning author_id into author;
  if author is not null then
    perform public.notify(author, me, 'spotted_claim', p_post);
  end if;
end;
$$;

-- =============================================================================
-- triggers: notifications + badges
-- =============================================================================
create or replace function public.on_follow() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  perform public.notify(new.followee_id, new.follower_id, 'follow');
  select count(*) into n from public.follows where followee_id = new.followee_id;
  if n >= 50 then perform public.award_badge(new.followee_id, 'popular'); end if;
  return new;
end; $$;
create trigger follows_after_insert after insert on public.follows
  for each row execute function public.on_follow();

create or replace function public.on_post_like() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify((select author_id from public.posts where id = new.post_id), new.user_id, 'post_like', new.post_id);
  return new;
end; $$;
create trigger post_likes_after_insert after insert on public.post_likes
  for each row execute function public.on_post_like();

create or replace function public.on_post_comment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify((select author_id from public.posts where id = new.post_id), new.user_id, 'post_comment', new.post_id, null, null, null, left(new.body, 80));
  return new;
end; $$;
create trigger post_comments_after_insert after insert on public.post_comments
  for each row execute function public.on_post_comment();

create or replace function public.on_post_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  perform public.award_badge(new.author_id, 'first_post');
  if new.kind = 'spotted' then
    select count(*) into n from public.posts where author_id = new.author_id and kind = 'spotted';
    if n >= 5 then perform public.award_badge(new.author_id, 'spotter'); end if;
  elsif new.kind = 'guide' then
    perform public.award_badge(new.author_id, 'guide_writer');
  end if;
  return new;
end; $$;
create trigger posts_after_insert after insert on public.posts
  for each row execute function public.on_post_insert();

create or replace function public.on_event_join() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int; org uuid; et public.event_type;
begin
  select organizer_id, event_type into org, et from public.events where id = new.event_id;
  perform public.notify(org, new.user_id, 'event_join', null, new.event_id);
  perform public.award_badge(new.user_id, 'first_meet');
  select count(*) into n from public.event_attendees where user_id = new.user_id;
  if n >= 10 then perform public.award_badge(new.user_id, 'regular'); end if;
  if et = 'tt' then
    select count(*) into n from public.event_attendees a join public.events e on e.id = a.event_id
    where a.user_id = new.user_id and e.event_type = 'tt';
    if n >= 5 then perform public.award_badge(new.user_id, 'tt_regular'); end if;
  end if;
  -- meet chat membership, if the chat already exists
  insert into public.conversation_members (conversation_id, user_id)
  select c.id, new.user_id from public.conversations c where c.event_id = new.event_id
  on conflict do nothing;
  return new;
end; $$;
create trigger event_attendees_after_insert after insert on public.event_attendees
  for each row execute function public.on_event_join();

create or replace function public.on_event_leave() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.conversation_members m using public.conversations c
  where m.conversation_id = c.id and c.event_id = old.event_id and m.user_id = old.user_id
    and old.user_id <> (select organizer_id from public.events where id = old.event_id);
  return old;
end; $$;
create trigger event_attendees_after_delete after delete on public.event_attendees
  for each row execute function public.on_event_leave();

create or replace function public.on_event_comment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify((select organizer_id from public.events where id = new.event_id), new.user_id, 'event_comment', null, new.event_id, null, null, left(new.body, 80));
  return new;
end; $$;
create trigger event_comments_after_insert after insert on public.event_comments
  for each row execute function public.on_event_comment();

create or replace function public.on_event_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.award_badge(new.organizer_id, 'organiser');
  if new.event_type = 'convoy' then perform public.award_badge(new.organizer_id, 'convoy_captain'); end if;
  -- attach / create a place for the venue (same name within ~150 m)
  if new.place_id is null then
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
end; $$;
create trigger events_before_insert before insert on public.events
  for each row execute function public.on_event_insert();

create or replace function public.on_event_cancel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' then
    insert into public.notifications (user_id, actor_id, type, event_id)
    select a.user_id, new.organizer_id, 'event_cancelled', new.id
    from public.event_attendees a where a.event_id = new.id and a.user_id <> new.organizer_id;
  end if;
  return new;
end; $$;
create trigger events_after_update after update on public.events
  for each row execute function public.on_event_cancel();

create or replace function public.on_car_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.award_badge(new.owner_id, 'garage_open');
  return new;
end; $$;
create trigger cars_after_insert after insert on public.cars
  for each row execute function public.on_car_insert();

create or replace function public.on_club_join() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify((select owner_id from public.clubs where id = new.club_id), new.user_id, 'club_join', null, null, new.club_id);
  return new;
end; $$;
create trigger club_members_after_insert after insert on public.club_members
  for each row execute function public.on_club_join();

-- Daily 01:00 UTC (09:00 MYT): remind attendees of meets in the next 24h.
create or replace function public.send_event_reminders()
returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, type, event_id)
  select a.user_id, 'event_reminder', e.id
  from public.event_attendees a
  join public.events e on e.id = a.event_id
  where e.status = 'active'
    and e.starts_at between now() and now() + interval '24 hours'
    and not exists (
      select 1 from public.notifications n
      where n.user_id = a.user_id and n.event_id = e.id and n.type = 'event_reminder'
    );
end;
$$;

-- Attach existing seed events to places.
insert into public.places (name, kind, lat, lng, created_by)
select distinct on (lower(venue_name)) venue_name,
  case when event_type = 'trackday' then 'circuit' when event_type = 'tt' then 'mamak' else 'carpark' end,
  lat, lng, organizer_id
from public.events
where place_id is null
order by lower(venue_name), created_at;
update public.events e set place_id = p.id
from public.places p
where e.place_id is null and lower(p.name) = lower(e.venue_name);

-- =============================================================================
-- scheduled jobs
-- =============================================================================
select cron.schedule('ttspot-car-of-week', '5 0 * * 1', $$select public.pick_car_of_week()$$);
select cron.schedule('ttspot-event-reminders', '0 1 * * *', $$select public.send_event_reminders()$$);
select cron.schedule('ttspot-expire-stories', '15 * * * *', $$delete from public.stories where expires_at < now() - interval '1 day'$$);

-- =============================================================================
-- realtime
-- =============================================================================
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.notifications;

-- =============================================================================
-- storage: post photos (posts, stories, mods, club avatars)
-- =============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('post-photos', 'post-photos', true, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "post-photos: public read"
  on storage.objects for select using (bucket_id = 'post-photos');
create policy "post-photos: owner upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'post-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "post-photos: owner update"
  on storage.objects for update to authenticated
  using (bucket_id = 'post-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "post-photos: owner delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'post-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- =============================================================================
-- RLS
-- =============================================================================
alter table public.follows              enable row level security;
alter table public.places               enable row level security;
alter table public.clubs                enable row level security;
alter table public.club_members         enable row level security;
alter table public.posts                enable row level security;
alter table public.post_likes           enable row level security;
alter table public.post_saves           enable row level security;
alter table public.post_comments        enable row level security;
alter table public.poll_votes           enable row level security;
alter table public.stories              enable row level security;
alter table public.story_views          enable row level security;
alter table public.notifications        enable row level security;
alter table public.badges               enable row level security;
alter table public.user_badges          enable row level security;
alter table public.car_mods             enable row level security;
alter table public.weekly_winners       enable row level security;
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages             enable row level security;

-- follows
create policy "follows: read" on public.follows for select to authenticated using (true);
create policy "follows: insert own" on public.follows for insert to authenticated with check (follower_id = auth.uid());
create policy "follows: delete own" on public.follows for delete to authenticated using (follower_id = auth.uid());

-- places
create policy "places: read" on public.places for select to authenticated using (true);
create policy "places: insert" on public.places for insert to authenticated with check (created_by = auth.uid());
create policy "places: update own" on public.places for update to authenticated using (created_by = auth.uid());

-- clubs
create policy "clubs: read" on public.clubs for select to authenticated using (true);
create policy "clubs: insert own" on public.clubs for insert to authenticated with check (owner_id = auth.uid());
create policy "clubs: update own" on public.clubs for update to authenticated using (owner_id = auth.uid());
create policy "clubs: delete own" on public.clubs for delete to authenticated using (owner_id = auth.uid());
create policy "club_members: read" on public.club_members for select to authenticated using (true);
create policy "club_members: join self" on public.club_members for insert to authenticated with check (user_id = auth.uid());
create policy "club_members: leave self or owner removes" on public.club_members for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.clubs c where c.id = club_id and c.owner_id = auth.uid()));

-- posts
create policy "posts: read" on public.posts for select to authenticated using (true);
create policy "posts: insert own" on public.posts for insert to authenticated with check (author_id = auth.uid());
create policy "posts: update own" on public.posts for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "posts: delete own" on public.posts for delete to authenticated using (author_id = auth.uid());

create policy "post_likes: read" on public.post_likes for select to authenticated using (true);
create policy "post_likes: insert own" on public.post_likes for insert to authenticated with check (user_id = auth.uid());
create policy "post_likes: delete own" on public.post_likes for delete to authenticated using (user_id = auth.uid());

create policy "post_saves: read own" on public.post_saves for select to authenticated using (user_id = auth.uid());
create policy "post_saves: insert own" on public.post_saves for insert to authenticated with check (user_id = auth.uid());
create policy "post_saves: delete own" on public.post_saves for delete to authenticated using (user_id = auth.uid());

create policy "post_comments: read" on public.post_comments for select to authenticated using (true);
create policy "post_comments: insert own" on public.post_comments for insert to authenticated with check (user_id = auth.uid());
create policy "post_comments: delete own" on public.post_comments for delete to authenticated using (user_id = auth.uid());

create policy "poll_votes: read" on public.poll_votes for select to authenticated using (true);
create policy "poll_votes: insert own" on public.poll_votes for insert to authenticated with check (user_id = auth.uid());
create policy "poll_votes: update own" on public.poll_votes for update to authenticated using (user_id = auth.uid());

-- stories
create policy "stories: read live" on public.stories for select to authenticated using (expires_at > now());
create policy "stories: insert own" on public.stories for insert to authenticated with check (author_id = auth.uid());
create policy "stories: delete own" on public.stories for delete to authenticated using (author_id = auth.uid());
create policy "story_views: read own" on public.story_views for select to authenticated using (viewer_id = auth.uid());
create policy "story_views: insert own" on public.story_views for insert to authenticated with check (viewer_id = auth.uid());

-- notifications (inserted by security-definer functions only)
create policy "notifications: read own" on public.notifications for select to authenticated using (user_id = auth.uid());
create policy "notifications: update own" on public.notifications for update to authenticated using (user_id = auth.uid());
create policy "notifications: delete own" on public.notifications for delete to authenticated using (user_id = auth.uid());

-- badges
create policy "badges: read" on public.badges for select to authenticated using (true);
create policy "user_badges: read" on public.user_badges for select to authenticated using (true);

-- car mods
create policy "car_mods: read" on public.car_mods for select to authenticated using (true);
create policy "car_mods: owner insert" on public.car_mods for insert to authenticated
  with check (exists (select 1 from public.cars c where c.id = car_id and c.owner_id = auth.uid()));
create policy "car_mods: owner update" on public.car_mods for update to authenticated
  using (exists (select 1 from public.cars c where c.id = car_id and c.owner_id = auth.uid()));
create policy "car_mods: owner delete" on public.car_mods for delete to authenticated
  using (exists (select 1 from public.cars c where c.id = car_id and c.owner_id = auth.uid()));

-- car of the week
create policy "weekly_winners: read" on public.weekly_winners for select to authenticated using (true);

-- chat
create policy "conversations: members read" on public.conversations for select to authenticated
  using (public.is_conversation_member(id, auth.uid()));
create policy "conversation_members: members read" on public.conversation_members for select to authenticated
  using (public.is_conversation_member(conversation_id, auth.uid()));
create policy "messages: members read" on public.messages for select to authenticated
  using (public.is_conversation_member(conversation_id, auth.uid()));
create policy "messages: members send" on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()));
create policy "messages: sender delete" on public.messages for delete to authenticated using (sender_id = auth.uid());
