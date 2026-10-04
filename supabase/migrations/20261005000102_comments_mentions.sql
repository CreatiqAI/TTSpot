-- Comments v2 (0.3.53): Instagram-style replies and likes on post comments,
-- @mentions in comments and posts, and pings from clubs you follow. Built on
-- the social-ping framework of 20261003000097 (notifications.silent,
-- setting_off, blocked_between, social_pings_full): every row lands in
-- Activity, silent rows never reach the lock screen.
--
-- Replies (one level, like Instagram)
--   post_comments.parent_id is always a top-level comment: replying to a
--   reply attaches to that reply's parent. reply_to_id keeps the comment the
--   member actually tapped Reply on (that author is who gets the ping).
--   Deleting a comment deletes its replies (on delete cascade), as Instagram
--   does: replies read out of context without their parent, moderation takes
--   an abusive thread down whole, and there's no "deleted comment" state to
--   keep. The app says how many replies go with it before deleting.
--
-- Comment likes: post_comment_likes(comment_id, user_id), read by anyone
--   signed in, written only as yourself. user_id points at auth.users (not
--   profiles) on purpose: a table with foreign keys to both post_comments and
--   profiles would be a PostgREST many-to-many between them and make the
--   app's `post_comments?select=*,profiles(...)` embed ambiguous.
--
-- New kinds, with who gets them and the limits:
--   mention        "mentioned you in a comment: …" / "mentioned you in a post: …"
--                  @username (case-insensitive, 3-20 of a-z 0-9 _, not inside
--                  an email or a URL) in a new comment, or in a new post's
--                  title / caption. The first 10 different existing members
--                  per item; never the writer, never across a block either
--                  way, never to or from a suspended account. In a comment,
--                  not the post's author (they get post_comment) and not the
--                  person replied to (they get comment_reply). In a post, it
--                  replaces that person's friend_post / club_post row for the
--                  same post (so that post doesn't start their 6-hour
--                  friend_post window). Push: one per writer per person per
--                  10 minutes.
--   comment_reply  "replied to your comment: …" to the author of the comment
--                  replied to (leading @handles left off the preview). When
--                  that is the post's author, it replaces their post_comment.
--                  Push: one per replier per person per 10 minutes.
--   comment_like   "liked your comment: …" to the comment's author. One row per
--                  person per comment, ever (like, unlike, like again pings
--                  once). Push: one per comment per 6 hours, and it counts
--                  towards the 8-a-day social cap.
--   club_post      "<club> posted: …" when a club posts as the club, to the
--                  club's followers (club_follows).
--   club_meet      "<club> planned <meet>, <day time>" when an OFFICIAL club
--                  plans a meet (any type except TT now), to its followers who
--                  can see it (a friends-only meet: the host's friends only).
--                  Official only because meet pings are what official clubs
--                  pay for (their members get club_event); followers of an
--                  underground club still get its posts.
--     Both club kinds: never to members (members of an official club already
--     get club_event for its meets; club posts reach members through their
--     Following feed and the club page, and they don't get both), never the
--     poster, never across a block with the poster, never suspended. Push:
--     one per club per follower per 6 hours across both kinds, and they count
--     towards the 8-a-day social cap.
--
-- Settings › Push notifications (missing = on; off = the row is silent,
-- still in Activity, and the push function checks the same keys):
--   notif_mentions      mention
--   notif_replies       comment_reply, comment_like
--   notif_club_follows  club_post, club_meet
-- Members who had switched off the older Friends switch (likes, comments)
-- start with Mentions and Replies off too, the way 0097 seeded its switches.
--
-- Routing: notifications.comment_id (new) points at the comment, so a tap can
-- open the post scrolled to it; post_comment rows now carry it as well. A
-- deleted comment takes its pings out of Activity (on delete cascade).

-- --------------------------------------------------------------- kinds ---
-- (Added live in a separate request first: new values can't be used in the
-- transaction that adds them.)
alter type public.notification_type add value if not exists 'mention';
alter type public.notification_type add value if not exists 'comment_reply';
alter type public.notification_type add value if not exists 'comment_like';
alter type public.notification_type add value if not exists 'club_post';
alter type public.notification_type add value if not exists 'club_meet';

-- ------------------------------------------------------------- replies ---
alter table public.post_comments add column if not exists parent_id uuid references public.post_comments (id) on delete cascade;
-- Only read while the reply is written (who to ping), so not a foreign key.
alter table public.post_comments add column if not exists reply_to_id uuid;
create index if not exists post_comments_parent_idx on public.post_comments (parent_id) where parent_id is not null;

-- Replies to a reply attach to its top-level parent, on the same post.
create or replace function public.post_comment_thread() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_post uuid;
  v_top  uuid;
begin
  if new.parent_id is null then
    new.reply_to_id := null;
    return new;
  end if;
  select c.post_id, coalesce(c.parent_id, c.id) into v_post, v_top
  from public.post_comments c where c.id = new.parent_id;
  if v_post is null or v_post <> new.post_id then
    raise exception 'That comment is gone.' using errcode = 'P0001';
  end if;
  new.reply_to_id := new.parent_id;
  new.parent_id := v_top;
  return new;
end;
$$;

drop trigger if exists post_comments_before_insert_thread on public.post_comments;
create trigger post_comments_before_insert_thread before insert on public.post_comments
  for each row execute function public.post_comment_thread();

-- --------------------------------------------------------------- likes ---
create table if not exists public.post_comment_likes (
  comment_id uuid not null references public.post_comments (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create index if not exists post_comment_likes_user_idx on public.post_comment_likes (user_id, created_at desc);
alter table public.post_comment_likes enable row level security;

drop policy if exists "post_comment_likes: read" on public.post_comment_likes;
create policy "post_comment_likes: read" on public.post_comment_likes for select to authenticated using (true);
drop policy if exists "post_comment_likes: add own" on public.post_comment_likes;
create policy "post_comment_likes: add own" on public.post_comment_likes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "post_comment_likes: remove own" on public.post_comment_likes;
create policy "post_comment_likes: remove own" on public.post_comment_likes for delete to authenticated using (user_id = auth.uid());
revoke all on public.post_comment_likes from anon;
grant select, insert, delete on public.post_comment_likes to authenticated;

-- ------------------------------------------------------- notifications ---
alter table public.notifications add column if not exists comment_id uuid references public.post_comments (id) on delete cascade;
create index if not exists notifications_comment_idx on public.notifications (comment_id) where comment_id is not null;

-- ------------------------------------------------------------- switches ---
update public.profiles
   set settings = jsonb_build_object('notif_mentions', false, 'notif_replies', false) || settings
 where settings ->> 'notif_friends' = 'false';

-- -------------------------------------------------------------- helpers ---

-- The daily cap (0097) now also covers comment likes and club pings.
create or replace function public.social_pings_full(p_user uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return (
    select count(*) from public.notifications
    where user_id = p_user and not silent and created_at > now() - interval '24 hours'
      and type::text in ('friend_post', 'friend_tt', 'club_member', 'follow', 'comment_like', 'club_post', 'club_meet')
  ) >= 8;
end;
$$;

-- One line, at most [p_len] characters.
create or replace function public.ping_snippet(p_text text, p_len int default 80) returns text
language sql immutable set search_path = public as $$
  select case when char_length(t) > p_len then rtrim(left(t, p_len - 1)) || '…' else t end
  from (select regexp_replace(btrim(coalesce(p_text, '')), '\s+', ' ', 'g') as t) s;
$$;

-- The members @mentioned in [p_text] that [p_actor] may ping: the first 10
-- different existing usernames in order, minus the writer, blocks either
-- way and suspended accounts (nobody, when the writer is suspended).
create or replace function public.mentioned_user_ids(p_text text, p_actor uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  with handles as (
    select lower(m[1]) as handle, min(o) as first_at
    from regexp_matches(coalesce(p_text, ''), '(?:^|[^a-z0-9_@./])@([a-z0-9_]{3,20})(?![a-z0-9_])', 'gi') with ordinality as t(m, o)
    group by 1
  ), people as (
    select p.id, p.suspended_at
    from handles h
    join public.profiles p on p.username = h.handle
    where p.id <> p_actor
    order by h.first_at
    limit 10
  )
  select x.id from people x
  where x.suspended_at is null
    and not public.blocked_between(x.id, p_actor)
    and not exists (select 1 from public.profiles a where a.id = p_actor and a.suspended_at is not null);
$$;

revoke execute on function public.mentioned_user_ids(text, uuid) from public, anon, authenticated;
revoke execute on function public.social_pings_full(uuid) from public, anon, authenticated;

-- ------------------------------------------- comment: comment, reply, @ ---
create or replace function public.on_post_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_post_author   uuid;
  v_target_author uuid;   -- whoever wrote the comment they tapped Reply on
  v_reply         text;
begin
  select author_id into v_post_author from public.posts where id = new.post_id;
  if new.parent_id is not null then
    select user_id into v_target_author from public.post_comments where id = coalesce(new.reply_to_id, new.parent_id);
  end if;

  -- The post's author: "commented: …", as before, unless the reply ping
  -- below is theirs.
  if v_post_author is not null and v_post_author <> new.user_id and v_target_author is distinct from v_post_author then
    insert into public.notifications (user_id, actor_id, type, post_id, comment_id, body)
    values (v_post_author, new.user_id, 'post_comment', new.post_id, new.id, left(new.body, 80));
  end if;

  -- The person replied to.
  if v_target_author is not null and v_target_author <> new.user_id
     and not public.blocked_between(v_target_author, new.user_id)
     and not exists (select 1 from public.profiles where id in (v_target_author, new.user_id) and suspended_at is not null) then
    -- "@aiman thanks!" previews as "thanks!" (a bare "@aiman" stays as it is)
    v_reply := public.ping_snippet(coalesce(nullif(regexp_replace(btrim(new.body), '^(@[a-z0-9_]{1,20}[\s,:]*)+', '', 'i'), ''), new.body), 80);
    insert into public.notifications (user_id, actor_id, type, post_id, comment_id, body, silent)
    select p.id, new.user_id, 'comment_reply', new.post_id, new.id, v_reply,
           public.setting_off(p.settings, 'notif_replies')
           or exists (
             select 1 from public.notifications x
             where x.user_id = p.id and x.actor_id = new.user_id and x.type = 'comment_reply'
               and not x.silent and x.created_at > now() - interval '10 minutes'
           )
    from public.profiles p
    where p.id = v_target_author and p.username is not null;
  end if;

  -- Everyone else @mentioned in it.
  insert into public.notifications (user_id, actor_id, type, post_id, comment_id, body, silent)
  select p.id, new.user_id, 'mention', new.post_id, new.id, public.ping_snippet(new.body, 80),
         public.setting_off(p.settings, 'notif_mentions')
         or exists (
           select 1 from public.notifications x
           where x.user_id = p.id and x.actor_id = new.user_id and x.type = 'mention'
             and not x.silent and x.created_at > now() - interval '10 minutes'
         )
  from public.mentioned_user_ids(new.body, new.user_id) m
  join public.profiles p on p.id = m
  where m is distinct from v_post_author
    and m is distinct from v_target_author
    and p.username is not null;
  return new;
end;
$$;

-- (post_comments_after_insert already runs on_post_comment.)

-- ---------------------------------------------------------- comment_like ---
create or replace function public.on_post_comment_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  c public.post_comments;
begin
  select * into c from public.post_comments where id = new.comment_id;
  if c.id is null or c.user_id = new.user_id then return null; end if;
  if public.blocked_between(c.user_id, new.user_id) then return null; end if;
  if exists (select 1 from public.profiles where id in (c.user_id, new.user_id) and suspended_at is not null) then return null; end if;
  -- like, unlike, like again: one row per person per comment
  if exists (
    select 1 from public.notifications x
    where x.user_id = c.user_id and x.actor_id = new.user_id and x.type = 'comment_like' and x.comment_id = c.id
  ) then return null; end if;
  insert into public.notifications (user_id, actor_id, type, post_id, comment_id, body, silent)
  select p.id, new.user_id, 'comment_like', c.post_id, c.id, public.ping_snippet(c.body, 60),
         public.setting_off(p.settings, 'notif_replies')
         or public.social_pings_full(p.id)
         or exists (
           select 1 from public.notifications x
           where x.user_id = p.id and x.comment_id = c.id and x.type = 'comment_like'
             and not x.silent and x.created_at > now() - interval '6 hours'
         )
  from public.profiles p
  where p.id = c.user_id and p.username is not null;
  return null;
end;
$$;

drop trigger if exists post_comment_likes_after_insert on public.post_comment_likes;
create trigger post_comment_likes_after_insert after insert on public.post_comment_likes
  for each row execute function public.on_post_comment_like();

-- ------------------------------------------------- post: @ and club_post ---
-- Runs after posts_after_insert_ping (triggers fire in name order), so the
-- friend_post rows for this post are already there to swap out.
create or replace function public.on_post_social() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_text      text;
  v_mentioned uuid[];
begin
  if exists (select 1 from public.profiles where id = new.author_id and suspended_at is not null) then return null; end if;
  v_text := btrim(concat_ws(' ', nullif(btrim(new.title), ''), nullif(btrim(new.caption), '')));

  -- Mentions.
  with ins as (
    insert into public.notifications (user_id, actor_id, type, post_id, body, silent)
    select p.id, new.author_id, 'mention', new.id, public.ping_snippet(coalesce(nullif(btrim(new.caption), ''), v_text), 80),
           public.setting_off(p.settings, 'notif_mentions')
           or exists (
             select 1 from public.notifications x
             where x.user_id = p.id and x.actor_id = new.author_id and x.type = 'mention'
               and not x.silent and x.created_at > now() - interval '10 minutes'
           )
    from public.mentioned_user_ids(v_text, new.author_id) m
    join public.profiles p on p.id = m
    where p.username is not null
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}') into v_mentioned from ins;
  -- One ping per person per post: the mention replaces "posted: …". Its push
  -- was only queued in this transaction, so it never goes out.
  if cardinality(v_mentioned) > 0 then
    delete from public.notifications
    where post_id = new.id and type = 'friend_post' and user_id = any (v_mentioned);
  end if;

  -- The club's followers, when it posts as the club.
  if coalesce(new.as_club, false) and new.club_id is not null then
    insert into public.notifications (user_id, actor_id, type, post_id, club_id, body, silent)
    select f.user_id, new.author_id, 'club_post', new.id, new.club_id,
           -- "<what>:<first 60 characters>", the friend_post format
           case
             when new.kind = 'poll' then 'poll'
             when new.kind = 'guide' then 'guide'
             when new.kind = 'spotted' then 'spotted'
             when new.video_url is not null then 'video'
             else 'photo'
           end || ':' || public.ping_snippet(coalesce(nullif(btrim(new.caption), ''), new.title, ''), 60),
           public.setting_off(p.settings, 'notif_club_follows')
           or public.social_pings_full(f.user_id)
           or exists (
             select 1 from public.notifications x
             where x.user_id = f.user_id and x.club_id = new.club_id and x.type::text in ('club_post', 'club_meet')
               and not x.silent and x.created_at > now() - interval '6 hours'
           )
    from public.club_follows f
    join public.profiles p on p.id = f.user_id
    where f.club_id = new.club_id
      and f.user_id <> new.author_id
      and not (f.user_id = any (v_mentioned))
      and p.suspended_at is null
      and p.username is not null
      and not exists (select 1 from public.club_members cm where cm.club_id = new.club_id and cm.user_id = f.user_id)
      and not public.blocked_between(f.user_id, new.author_id);
  end if;
  return null;
end;
$$;

drop trigger if exists posts_after_insert_social on public.posts;
create trigger posts_after_insert_social after insert on public.posts
  for each row execute function public.on_post_social();

-- ------------------------------------------------------------ club_meet ---
create or replace function public.on_club_meet_ping() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_tier text;
begin
  if new.club_id is null or new.status <> 'active' or coalesce(new.is_instant, false) then return null; end if;
  if coalesce(new.ends_at, new.starts_at + interval '3 hours') < now() then return null; end if;
  select tier into v_tier from public.clubs where id = new.club_id;
  if v_tier is distinct from 'official' then return null; end if;
  if exists (select 1 from public.profiles where id = new.organizer_id and suspended_at is not null) then return null; end if;
  insert into public.notifications (user_id, actor_id, type, event_id, club_id, body, silent)
  select f.user_id, new.organizer_id, 'club_meet', new.id, new.club_id, new.title,
         public.setting_off(p.settings, 'notif_club_follows')
         or public.social_pings_full(f.user_id)
         or exists (
           select 1 from public.notifications x
           where x.user_id = f.user_id and x.club_id = new.club_id and x.type::text in ('club_post', 'club_meet')
             and not x.silent and x.created_at > now() - interval '6 hours'
         )
  from public.club_follows f
  join public.profiles p on p.id = f.user_id
  where f.club_id = new.club_id
    and f.user_id <> new.organizer_id
    and p.suspended_at is null
    and p.username is not null
    and not exists (select 1 from public.club_members cm where cm.club_id = new.club_id and cm.user_id = f.user_id)
    and not public.blocked_between(f.user_id, new.organizer_id)
    and (new.visibility = 'public' or public.is_friend(f.user_id, new.organizer_id))
    and not exists (select 1 from public.notifications x where x.user_id = f.user_id and x.event_id = new.id);
  return null;
end;
$$;

drop trigger if exists events_after_insert_club_meet on public.events;
create trigger events_after_insert_club_meet after insert on public.events
  for each row when (new.club_id is not null) execute function public.on_club_meet_ping();

