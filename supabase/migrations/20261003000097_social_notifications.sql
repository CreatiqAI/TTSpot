-- Social pings (0.3.52): nudge members when their circle does something,
-- without it turning into noise. All rows land in Activity; the existing push
-- hook sends them (notifications_push), except rows marked silent.
--
--   friend_post   a friend, or someone I follow, posted as themselves. Club and
--                 partner posts ping nobody here: the club / partner follow
--                 tables (same batch) are the right audience for those.
--   friend_tt     a friend planned a TT session for later. Sent about 1-2 min
--                 after it is made (tt_plan_pings + a 1-minute cron), so the
--                 invite cards the app sends right after creating it are
--                 already there and those friends are skipped. TT now gets
--                 nothing extra: tt_now() already pings every friend the host
--                 keeps ticked (all, by default) and sends them an invite card;
--                 the friends left are the ones they unticked on purpose.
--   club_member   someone joined a club I'm in (instant join, approved request,
--                 accepted invite). Fires at commit, so the owner (club_join
--                 from on_club_join) and an inviter (club_join from
--                 respond_club_invite) aren't told twice.
--   follow        someone started following me. The existing on_follow
--                 trigger, rewritten in place (no second trigger): now with a
--                 dedupe, blocks and its own switch.
--
-- Limits, per recipient:
--   * never the actor; never across a block either way; never to or from a
--     suspended account; "Fewer from this person" (post_hides scope 'author')
--     stops that person's post pings.
--   * friend_post: one per author per 6 hours. Later posts in the window make
--     no row at all (they're in the feed anyway).
--   * friend_tt: one push per host per 6 hours; club_member: one push per club
--     per 6 hours. Later ones still land in Activity, silently.
--   * follow: one row per follower, ever (follow, unfollow, follow again
--     makes no second row while the first is still in Activity); silent when
--     they're already friends.
--   * at most 8 pushes in any 24 hours across these four kinds; past that the
--     rows still land in Activity, silently.
--   * clubs over 300 members: no join pings to members (the owner still gets
--     club_join).
--   * a switch turned off in Settings › Push notifications makes the row
--     silent, like the older switches: it shows in Activity, it never buzzes.
--     The push function checks the same switches.

-- --------------------------------------------------------------- kinds ---
alter type public.notification_type add value if not exists 'friend_post';
alter type public.notification_type add value if not exists 'friend_tt';
alter type public.notification_type add value if not exists 'club_member';

-- -------------------------------------------------------------- silent ---
-- In Activity, not on the lock screen: the push hook skips these rows.
alter table public.notifications add column if not exists silent boolean not null default false;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push after insert on public.notifications
  for each row when (not new.silent) execute function public.push_hook();

-- Invite cards in chat carry the meet (messages.event_id); the TT ping looks them up.
create index if not exists messages_event_idx on public.messages (event_id) where event_id is not null;

-- ------------------------------------------------------------- switches ---
-- New switches start on, except where the member had already turned the
-- older, wider one off (Friends covered follows; TT now pings covered TTs).
update public.profiles
   set settings = jsonb_build_object('notif_friend_posts', false, 'notif_club_members', false, 'notif_followers', false) || settings
 where settings ->> 'notif_friends' = 'false';
update public.profiles
   set settings = jsonb_build_object('notif_friend_tt', false) || settings
 where settings ->> 'notif_tt' = 'false';

-- -------------------------------------------------------------- helpers ---

-- A switch in profiles.settings is off (missing = on).
create or replace function public.setting_off(p_settings jsonb, p_key text) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(p_settings ->> p_key, '') = 'false';
$$;

-- Either one blocked the other.
create or replace function public.blocked_between(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = p_a and blocked_id = p_b) or (blocker_id = p_b and blocked_id = p_a)
  );
$$;

-- This member has had their 8 social pushes in the last 24 hours.
create or replace function public.social_pings_full(p_user uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return (
    select count(*) from public.notifications
    where user_id = p_user and not silent and created_at > now() - interval '24 hours'
      and type::text in ('friend_post', 'friend_tt', 'club_member', 'follow')
  ) >= 8;
end;
$$;

revoke execute on function public.blocked_between(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.social_pings_full(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------- friend_post ---
create or replace function public.on_post_ping() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_text text;
  v_body text;
begin
  if coalesce(new.as_club, false) or coalesce(new.as_vendor, false) then return null; end if;
  if exists (select 1 from public.profiles where id = new.author_id and suspended_at is not null) then return null; end if;
  v_text := regexp_replace(btrim(coalesce(nullif(btrim(new.caption), ''), new.title, '')), '\s+', ' ', 'g');
  if char_length(v_text) > 60 then v_text := rtrim(left(v_text, 59)) || '…'; end if;
  -- "<what>:<first 60 characters>"; the app and the push function word it.
  v_body := case
      when new.kind = 'poll' then 'poll'
      when new.kind = 'guide' then 'guide'
      when new.kind = 'spotted' then 'spotted'
      when new.video_url is not null then 'video'
      else 'photo'
    end || ':' || v_text;
  insert into public.notifications (user_id, actor_id, type, post_id, body, silent)
  select r.id, new.author_id, 'friend_post', new.id, v_body,
         public.setting_off(p.settings, 'notif_friend_posts') or public.social_pings_full(r.id)
  from (
    select id from public.friend_ids(new.author_id) id
    union
    select follower_id from public.follows where followee_id = new.author_id
  ) r
  join public.profiles p on p.id = r.id
  where r.id <> new.author_id
    and p.suspended_at is null
    and p.username is not null
    and not public.blocked_between(r.id, new.author_id)
    and not exists (select 1 from public.post_hides h where h.user_id = r.id and h.author_id = new.author_id and h.scope = 'author')
    and not exists (
      select 1 from public.notifications n
      where n.user_id = r.id and n.actor_id = new.author_id and n.type = 'friend_post'
        and n.created_at > now() - interval '6 hours'
    );
  return null;
end;
$$;

drop trigger if exists posts_after_insert_ping on public.posts;
create trigger posts_after_insert_ping after insert on public.posts
  for each row execute function public.on_post_ping();

-- ---------------------------------------------------------- club_member ---
create or replace function public.on_club_member_ping() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
  v_count int;
  v_by    uuid := auth.uid();   -- whoever let them in (an approving admin) knows already
begin
  select owner_id into v_owner from public.clubs where id = new.club_id;
  -- The owner's own row when the club is made.
  if v_owner is null or new.user_id = v_owner then return null; end if;
  -- Gone again before commit.
  if not exists (select 1 from public.club_members where club_id = new.club_id and user_id = new.user_id) then return null; end if;
  if exists (select 1 from public.profiles where id = new.user_id and suspended_at is not null) then return null; end if;
  select count(*) into v_count from public.club_members where club_id = new.club_id;
  if v_count > 300 then return null; end if;
  insert into public.notifications (user_id, actor_id, type, club_id, silent)
  select m.user_id, new.user_id, 'club_member', new.club_id,
         public.setting_off(p.settings, 'notif_club_members')
         or public.social_pings_full(m.user_id)
         or exists (
           select 1 from public.notifications n
           where n.user_id = m.user_id and n.club_id = new.club_id and n.type = 'club_member'
             and not n.silent and n.created_at > now() - interval '6 hours'
         )
  from public.club_members m
  join public.profiles p on p.id = m.user_id
  where m.club_id = new.club_id
    and m.user_id <> new.user_id
    and m.user_id is distinct from v_by
    and p.suspended_at is null
    and not public.blocked_between(m.user_id, new.user_id)
    and not exists (
      select 1 from public.notifications n
      where n.user_id = m.user_id and n.actor_id = new.user_id and n.club_id = new.club_id
        and n.type = 'club_join' and n.created_at > now() - interval '10 minutes'
    );
  return null;
end;
$$;

-- At commit: by then the owner's and the inviter's club_join rows exist.
drop trigger if exists club_members_after_insert_ping on public.club_members;
create constraint trigger club_members_after_insert_ping after insert on public.club_members
  deferrable initially deferred
  for each row execute function public.on_club_member_ping();

-- ------------------------------------------------------------ friend_tt ---
-- Planned TT sessions wait here until their invite cards are out.
create table if not exists public.tt_plan_pings (
  event_id uuid primary key references public.events (id) on delete cascade,
  due_at   timestamptz not null default now() + interval '90 seconds'
);
alter table public.tt_plan_pings enable row level security;
revoke all on public.tt_plan_pings from anon, authenticated;

create or replace function public.on_tt_planned() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'active' and new.vendor_id is null then
    insert into public.tt_plan_pings (event_id) values (new.id) on conflict do nothing;
  end if;
  return null;
end;
$$;

drop trigger if exists events_after_insert_tt_ping on public.events;
create trigger events_after_insert_tt_ping after insert on public.events
  for each row when (new.event_type = 'tt' and not coalesce(new.is_instant, false))
  execute function public.on_tt_planned();

-- The host's friends who can see the session and haven't heard about it yet.
-- Returns how many rows it wrote.
create or replace function public.ping_friends_tt(p_event uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  e public.events;
  n int;
begin
  select * into e from public.events where id = p_event;
  if e.id is null or e.status <> 'active' or e.event_type <> 'tt' or e.vendor_id is not null then return 0; end if;
  if coalesce(e.ends_at, e.starts_at + interval '3 hours') < now() then return 0; end if;
  -- public and friends sessions are both open to the host's friends
  if e.visibility not in ('public', 'friends') then return 0; end if;
  if exists (select 1 from public.profiles where id = e.organizer_id and suspended_at is not null) then return 0; end if;
  insert into public.notifications (user_id, actor_id, type, event_id, body, silent)
  select f.id, e.organizer_id, 'friend_tt', e.id, e.venue_name,
         public.setting_off(p.settings, 'notif_friend_tt')
         or public.social_pings_full(f.id)
         or exists (
           select 1 from public.notifications x
           where x.user_id = f.id and x.actor_id = e.organizer_id and x.type = 'friend_tt'
             and not x.silent and x.created_at > now() - interval '6 hours'
         )
  from (select id from public.friend_ids(e.organizer_id) id) f
  join public.profiles p on p.id = f.id
  where f.id <> e.organizer_id
    and p.suspended_at is null
    and not public.blocked_between(f.id, e.organizer_id)
    -- Heard already: on the attendee list (TT now invitees), any ping about
    -- this session (tt_now, club_event…), or its invite card in a chat.
    and not exists (select 1 from public.event_attendees a where a.event_id = e.id and a.user_id = f.id)
    and not exists (select 1 from public.notifications x where x.user_id = f.id and x.event_id = e.id)
    and not exists (
      select 1 from public.messages m
      join public.conversation_members cm on cm.conversation_id = m.conversation_id
      where m.event_id = e.id and m.sender_id = e.organizer_id and cm.user_id = f.id
    );
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.flush_tt_plan_pings() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_event uuid;
  v_total int := 0;
begin
  for v_event in delete from public.tt_plan_pings where due_at <= now() returning event_id loop
    v_total := v_total + public.ping_friends_tt(v_event);
  end loop;
  return v_total;
end;
$$;

revoke execute on function public.ping_friends_tt(uuid) from public, anon, authenticated;
revoke execute on function public.flush_tt_plan_pings() from public, anon, authenticated;

select cron.schedule('ttspot-tt-plan-pings', '* * * * *', $$select public.flush_tt_plan_pings()$$);

-- --------------------------------------------------------------- follow ---
create or replace function public.on_follow() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.blocked_between(new.followee_id, new.follower_id)
     and not exists (select 1 from public.profiles where id in (new.followee_id, new.follower_id) and suspended_at is not null)
     -- follow, unfollow, follow again: never a second ping while the first is still in Activity
     and not exists (
       select 1 from public.notifications x
       where x.user_id = new.followee_id and x.actor_id = new.follower_id and x.type = 'follow'
     ) then
    insert into public.notifications (user_id, actor_id, type, silent)
    select p.id, new.follower_id, 'follow',
           public.setting_off(p.settings, 'notif_followers')
           or public.social_pings_full(p.id)
           or public.is_friend(p.id, new.follower_id)
    from public.profiles p
    where p.id = new.followee_id and p.id <> new.follower_id;
  end if;
  select count(*) into n from public.follows where followee_id = new.followee_id;
  if n >= 50 then perform public.award_badge(new.followee_id, 'popular'); end if;
  return new;
end;
$$;
