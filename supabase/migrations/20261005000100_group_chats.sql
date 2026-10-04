-- =============================================================================
-- Group chats (0.3.53).
--
--   * conversations.kind gains 'group' (a friends' group chat) and 'club'
--     (every club's members chat: one per club, club_id = the club, named
--     after it with its logo as the picture; it follows the club, so it has
--     no name or photo of its own).
--   * conversations.title / photo_url / created_by: a friends' group's name
--     (null = the app lists the members), picture and creator.
--   * conversation_members.is_admin: a friends' group's admins, the creator
--     first. In a club chat the club's officers (is_club_admin) moderate.
--   * Club chat membership follows club_members (triggers below; join_club,
--     approved requests and accepted invites all insert real rows). Every
--     existing club gets its chat, with its current members, at the end.
--     Nothing here writes a message or a notification, so no push goes out.
--   * Group membership changes only through the security-definer functions
--     here: there are no insert / update / delete policies on conversations
--     or conversation_members. Friends only, no blocks either way, 100 max.
--   * In group and club chats you read what was sent since you joined
--     (like WhatsApp); DMs and meet chats are unchanged.
--   * my_chat_summaries(): each of my chats' last message, unread count and
--     member count in one call, so a busy club chat can't push the other
--     chats' last messages out of the inbox's message window.
-- =============================================================================

-- ------------------------------------------------------------- columns ---
alter table public.conversations drop constraint if exists conversations_kind_check;
alter table public.conversations add constraint conversations_kind_check check (kind in ('dm', 'meet', 'group', 'club'));

alter table public.conversations
  add column if not exists title      text,
  add column if not exists photo_url  text,
  add column if not exists created_by uuid references public.profiles (id) on delete set null;
alter table public.conversations drop constraint if exists conversations_title_check;
alter table public.conversations add constraint conversations_title_check check (title is null or char_length(title) between 1 and 60);

-- One members chat per club.
create unique index if not exists conversations_club_chat_idx on public.conversations (club_id) where kind = 'club';

alter table public.conversation_members add column if not exists is_admin boolean not null default false;

-- ------------------------------------------------------------- reading ---
-- Members only; in group and club chats only what was sent since you joined.
create or replace function public.can_read_message(p_conversation uuid, p_sent timestamptz, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversation_members m
    join public.conversations c on c.id = m.conversation_id
    where m.conversation_id = p_conversation and m.user_id = p_user
      and (c.kind in ('dm', 'meet') or p_sent >= m.created_at)
  );
$$;
revoke execute on function public.can_read_message(uuid, timestamptz, uuid) from public, anon;
grant execute on function public.can_read_message(uuid, timestamptz, uuid) to authenticated;

drop policy if exists "messages: members read" on public.messages;
create policy "messages: members read" on public.messages for select to authenticated
  using (public.can_read_message(conversation_id, created_at, auth.uid()));

-- ----------------------------------------------------------- club chat ---
-- The club's members chat, made on first need.
create or replace function public.ensure_club_chat(p_club uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from public.conversations where kind = 'club' and club_id = p_club;
  if v_id is not null then return v_id; end if;
  insert into public.conversations (kind, club_id) values ('club', p_club)
  on conflict (club_id) where kind = 'club' do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.conversations where kind = 'club' and club_id = p_club;
  end if;
  return v_id;
end; $$;
revoke execute on function public.ensure_club_chat(uuid) from public, anon, authenticated;

-- A new club gets its chat at once, with the owner in it.
create or replace function public.on_club_created_chat() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.conversation_members (conversation_id, user_id)
  values (public.ensure_club_chat(new.id), new.owner_id)
  on conflict do nothing;
  return null;
exception when others then
  raise warning 'club chat for % not made: %', new.id, sqlerrm;
  return null; -- the chat must never block making a club
end; $$;
revoke execute on function public.on_club_created_chat() from public, anon, authenticated;
drop trigger if exists clubs_after_insert_chat on public.clubs;
create trigger clubs_after_insert_chat after insert on public.clubs
  for each row execute function public.on_club_created_chat();

-- clubs.id is "on delete set null" on conversations, so the chat goes first.
create or replace function public.on_club_deleted_chat() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.conversations where kind = 'club' and club_id = old.id;
  return old;
end; $$;
revoke execute on function public.on_club_deleted_chat() from public, anon, authenticated;
drop trigger if exists clubs_before_delete_chat on public.clubs;
create trigger clubs_before_delete_chat before delete on public.clubs
  for each row execute function public.on_club_deleted_chat();

-- Joining the club (any route: join_club, an approved request, an accepted
-- invite, the owner's own row) puts you in its chat.
create or replace function public.on_club_member_chat_join() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.conversation_members (conversation_id, user_id)
  values (public.ensure_club_chat(new.club_id), new.user_id)
  on conflict do nothing;
  return null;
exception when others then
  raise warning 'club chat join for % in % failed: %', new.user_id, new.club_id, sqlerrm;
  return null; -- the chat must never block joining a club; open_club_chat() heals it
end; $$;
revoke execute on function public.on_club_member_chat_join() from public, anon, authenticated;
drop trigger if exists club_members_chat_join on public.club_members;
create trigger club_members_chat_join after insert on public.club_members
  for each row execute function public.on_club_member_chat_join();

-- Leaving (or being removed from) the club takes you out of its chat. The
-- owner stays, like a meet's host in its chat.
create or replace function public.on_club_member_chat_leave() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.conversation_members m using public.conversations c
  where m.conversation_id = c.id and c.kind = 'club' and c.club_id = old.club_id and m.user_id = old.user_id
    and old.user_id is distinct from (select owner_id from public.clubs where id = old.club_id);
  return null;
end; $$;
revoke execute on function public.on_club_member_chat_leave() from public, anon, authenticated;
drop trigger if exists club_members_chat_leave on public.club_members;
create trigger club_members_chat_leave after delete on public.club_members
  for each row execute function public.on_club_member_chat_leave();

-- Open my club's chat (the club page's Club chat button). Members only.
create or replace function public.open_club_chat(p_club uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v_conv uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if not exists (select 1 from public.club_members where club_id = p_club and user_id = me)
     and not exists (select 1 from public.clubs where id = p_club and owner_id = me) then
    raise exception 'Join the club to chat with its members';
  end if;
  v_conv := public.ensure_club_chat(p_club);
  insert into public.conversation_members (conversation_id, user_id) values (v_conv, me) on conflict do nothing;
  return v_conv;
end; $$;
revoke execute on function public.open_club_chat(uuid) from public, anon;
grant execute on function public.open_club_chat(uuid) to authenticated;

-- -------------------------------------------------------- friend groups ---
-- A picture uploaded to chat-photos (the app puts it at <me>/group-<ts>.jpg).
create or replace function public.check_group_photo(p_url text) returns void
language plpgsql immutable set search_path = public as $$
begin
  if p_url is null or trim(p_url) = '' then return; end if;
  if p_url !~ '^https://' or position('/storage/v1/object/public/chat-photos/' in p_url) = 0 or char_length(p_url) > 500 then
    raise exception 'Pick a photo from your phone for the group';
  end if;
end; $$;
revoke execute on function public.check_group_photo(text) from public, anon, authenticated;

-- Can p_by put p_user in a group? Friends only, no block either way, not suspended.
create or replace function public.check_group_invitee(p_by uuid, p_user uuid) returns void
language plpgsql stable security definer set search_path = public as $$
declare v_name text; v_suspended boolean;
begin
  select coalesce(nullif(trim(p.display_name), ''), '@' || p.username, 'that member'), p.suspended_at is not null
    into v_name, v_suspended
  from public.profiles p where p.id = p_user;
  if not found then raise exception 'That member is no longer on TT Spot'; end if;
  if public.blocked_between(p_by, p_user) then raise exception 'You can''t add % to a group', v_name; end if;
  if not public.is_friend(p_by, p_user) then raise exception 'Only friends can be added. Add % as a friend first.', v_name; end if;
  if v_suspended then raise exception 'You can''t add % right now', v_name; end if;
end; $$;
revoke execute on function public.check_group_invitee(uuid, uuid) from public, anon, authenticated;

create or replace function public.check_group_name(p_title text) returns text
language plpgsql immutable set search_path = public as $$
declare v text := nullif(btrim(coalesce(p_title, '')), '');
begin
  if v is not null and char_length(v) > 60 then raise exception 'Group names can be up to 60 characters'; end if;
  return v;
end; $$;
revoke execute on function public.check_group_name(text) from public, anon, authenticated;

-- Start a group with 2+ friends. The creator is its first admin.
create or replace function public.create_group_chat(p_members uuid[], p_title text default null, p_photo_url text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_ids uuid[];
  v_id uuid;
  v_conv uuid;
  v_title text;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if exists (select 1 from public.profiles where id = me and suspended_at is not null) then raise exception 'Your account is suspended'; end if;
  select coalesce(array_agg(distinct u), '{}') into v_ids from unnest(coalesce(p_members, '{}'::uuid[])) as t(u) where u is not null and u <> me;
  if cardinality(v_ids) < 2 then raise exception 'Pick at least 2 friends for a group'; end if;
  if cardinality(v_ids) + 1 > 100 then raise exception 'A group holds up to 100 members'; end if;
  v_title := public.check_group_name(p_title);
  perform public.check_group_photo(p_photo_url);
  foreach v_id in array v_ids loop
    perform public.check_group_invitee(me, v_id);
  end loop;
  insert into public.conversations (kind, title, photo_url, created_by)
  values ('group', v_title, nullif(trim(coalesce(p_photo_url, '')), ''), me)
  returning id into v_conv;
  insert into public.conversation_members (conversation_id, user_id, is_admin) values (v_conv, me, true);
  insert into public.conversation_members (conversation_id, user_id) select v_conv, u from unnest(v_ids) as t(u);
  return v_conv;
end; $$;
revoke execute on function public.create_group_chat(uuid[], text, text) from public, anon;
grant execute on function public.create_group_chat(uuid[], text, text) to authenticated;

-- Any member can add their own friends, up to 100 in the group. Returns how many were added.
create or replace function public.add_group_members(p_conversation uuid, p_members uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_ids uuid[];
  v_id uuid;
  v_count int;
  v_n int;
begin
  if me is null then raise exception 'Sign in first'; end if;
  -- Locks the group so two people adding at once can't pass the cap.
  perform 1 from public.conversations where id = p_conversation and kind = 'group' for update;
  if not found then raise exception 'Group not found'; end if;
  if not exists (select 1 from public.conversation_members where conversation_id = p_conversation and user_id = me) then
    raise exception 'You''re not in this group';
  end if;
  if exists (select 1 from public.profiles where id = me and suspended_at is not null) then raise exception 'Your account is suspended'; end if;
  select coalesce(array_agg(distinct u), '{}') into v_ids from unnest(coalesce(p_members, '{}'::uuid[])) as t(u)
  where u is not null
    and not exists (select 1 from public.conversation_members m where m.conversation_id = p_conversation and m.user_id = u);
  if cardinality(v_ids) = 0 then return 0; end if;
  select count(*) into v_count from public.conversation_members where conversation_id = p_conversation;
  if v_count >= 100 then raise exception 'This group is full. A group holds up to 100 members.'; end if;
  if v_count + cardinality(v_ids) > 100 then raise exception 'Only % more can join this group (100 max)', 100 - v_count; end if;
  foreach v_id in array v_ids loop
    perform public.check_group_invitee(me, v_id);
  end loop;
  insert into public.conversation_members (conversation_id, user_id)
  select p_conversation, u from unnest(v_ids) as t(u)
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end; $$;
revoke execute on function public.add_group_members(uuid, uuid[]) from public, anon;
grant execute on function public.add_group_members(uuid, uuid[]) to authenticated;

-- Am I an admin of this friends' group?
create or replace function public.is_group_admin(p_conversation uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversation_members m join public.conversations c on c.id = m.conversation_id
    where m.conversation_id = p_conversation and m.user_id = p_user and m.is_admin and c.kind = 'group'
  );
$$;
revoke execute on function public.is_group_admin(uuid, uuid) from public, anon;
grant execute on function public.is_group_admin(uuid, uuid) to authenticated;

-- Admins remove members. Whoever made the group can't be removed by others.
create or replace function public.remove_group_member(p_conversation uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v_creator uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select created_by into v_creator from public.conversations where id = p_conversation and kind = 'group';
  if not found then raise exception 'Group not found'; end if;
  if p_user = me then raise exception 'Use Leave group instead'; end if;
  if not public.is_group_admin(p_conversation, me) then raise exception 'Only group admins can remove members'; end if;
  if p_user = v_creator then raise exception 'The person who made the group can''t be removed'; end if;
  delete from public.conversation_members where conversation_id = p_conversation and user_id = p_user;
end; $$;
revoke execute on function public.remove_group_member(uuid, uuid) from public, anon;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;

-- Admins make other members admins (or not). The creator stays an admin.
create or replace function public.set_group_admin(p_conversation uuid, p_user uuid, p_admin boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v_creator uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select created_by into v_creator from public.conversations where id = p_conversation and kind = 'group';
  if not found then raise exception 'Group not found'; end if;
  if not public.is_group_admin(p_conversation, me) then raise exception 'Only group admins can do that'; end if;
  if p_user = me then raise exception 'Ask another admin to change your role'; end if;
  if p_user = v_creator and not p_admin then raise exception 'The person who made the group stays an admin'; end if;
  update public.conversation_members set is_admin = coalesce(p_admin, false)
  where conversation_id = p_conversation and user_id = p_user;
  if not found then raise exception 'They''re not in this group'; end if;
end; $$;
revoke execute on function public.set_group_admin(uuid, uuid, boolean) from public, anon;
grant execute on function public.set_group_admin(uuid, uuid, boolean) to authenticated;

-- Admins rename the group (blank = list the members instead) ...
create or replace function public.rename_group_chat(p_conversation uuid, p_title text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not exists (select 1 from public.conversations where id = p_conversation and kind = 'group') then
    raise exception 'Only friends'' groups can be renamed. A club chat follows the club''s name.';
  end if;
  if not public.is_group_admin(p_conversation) then raise exception 'Only group admins can rename the group'; end if;
  update public.conversations set title = public.check_group_name(p_title) where id = p_conversation;
end; $$;
revoke execute on function public.rename_group_chat(uuid, text) from public, anon;
grant execute on function public.rename_group_chat(uuid, text) to authenticated;

-- ... and change its picture (null = no picture).
create or replace function public.set_group_chat_photo(p_conversation uuid, p_photo_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not exists (select 1 from public.conversations where id = p_conversation and kind = 'group') then
    raise exception 'Only friends'' groups have their own photo. A club chat uses the club logo.';
  end if;
  if not public.is_group_admin(p_conversation) then raise exception 'Only group admins can change the photo'; end if;
  perform public.check_group_photo(p_photo_url);
  update public.conversations set photo_url = nullif(trim(coalesce(p_photo_url, '')), '') where id = p_conversation;
end; $$;
revoke execute on function public.set_group_chat_photo(uuid, text) from public, anon;
grant execute on function public.set_group_chat_photo(uuid, text) to authenticated;

-- Leave a friends' group. The last admin out hands over to the longest
-- standing member; the last member out deletes it. A club chat is left by
-- leaving the club.
create or replace function public.leave_group_chat(p_conversation uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v_kind text;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select kind into v_kind from public.conversations where id = p_conversation for update;
  if v_kind is null then raise exception 'Group not found'; end if;
  if v_kind = 'club' then raise exception 'Leave the club to leave its chat'; end if;
  if v_kind <> 'group' then raise exception 'Only group chats can be left'; end if;
  delete from public.conversation_members where conversation_id = p_conversation and user_id = me;
  if not found then return; end if;
  if not exists (select 1 from public.conversation_members where conversation_id = p_conversation) then
    delete from public.conversations where id = p_conversation;
    return;
  end if;
  if not exists (select 1 from public.conversation_members where conversation_id = p_conversation and is_admin) then
    update public.conversation_members set is_admin = true
    where conversation_id = p_conversation
      and user_id = (select user_id from public.conversation_members where conversation_id = p_conversation order by created_at, user_id limit 1);
  end if;
end; $$;
revoke execute on function public.leave_group_chat(uuid) from public, anon;
grant execute on function public.leave_group_chat(uuid) to authenticated;

-- ------------------------------------------------- delete for everyone ---
-- Your own message anywhere; any message in a club chat for the club's
-- officers (president, VP, secretary); any message in a friends' group for
-- its admins.
create or replace function public.delete_chat_message(p_message uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m public.messages%rowtype; c public.conversations%rowtype;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into m from public.messages where id = p_message;
  if m.id is null then return; end if; -- already gone
  select * into c from public.conversations where id = m.conversation_id;
  if not public.is_conversation_member(c.id, me) then raise exception 'Message not found'; end if;
  if m.sender_id = me
     or (c.kind = 'club' and c.club_id is not null and public.is_club_admin(c.club_id, me))
     or (c.kind = 'group' and public.is_group_admin(c.id, me)) then
    delete from public.messages where id = p_message;
  else
    raise exception 'Only club officers and group admins can delete other people''s messages';
  end if;
end; $$;
revoke execute on function public.delete_chat_message(uuid) from public, anon;
grant execute on function public.delete_chat_message(uuid) to authenticated;

-- ------------------------------------------------------- inbox summary ---
-- Per chat I'm in: the last message I can see (with its sender), how many
-- are unread (capped at 99) and how many members it has. Messages from
-- people I blocked don't count.
create or replace function public.my_chat_summaries()
returns table (conversation_id uuid, last_message jsonb, unread int, member_count int)
language sql stable security definer set search_path = public as $$
  select m.conversation_id,
         (select to_jsonb(x) || jsonb_build_object('profiles', (
                   select jsonb_build_object('id', p.id, 'username', p.username, 'display_name', p.display_name, 'avatar_url', p.avatar_url, 'created_at', p.created_at)
                   from public.profiles p where p.id = x.sender_id))
            from public.messages x
           where x.conversation_id = m.conversation_id
             and (c.kind in ('dm', 'meet') or x.created_at >= m.created_at)
             and not exists (select 1 from public.blocks b where b.blocker_id = m.user_id and b.blocked_id = x.sender_id)
           order by x.created_at desc
           limit 1),
         (select count(*)::int from (
             select 1 from public.messages x
              where x.conversation_id = m.conversation_id
                and x.sender_id <> m.user_id
                and x.created_at > m.last_read_at
                and (c.kind in ('dm', 'meet') or x.created_at >= m.created_at)
                and not exists (select 1 from public.blocks b where b.blocker_id = m.user_id and b.blocked_id = x.sender_id)
              limit 99) t),
         (select count(*)::int from public.conversation_members o where o.conversation_id = m.conversation_id)
  from public.conversation_members m
  join public.conversations c on c.id = m.conversation_id
  where m.user_id = auth.uid();
$$;
revoke execute on function public.my_chat_summaries() from public, anon;
grant execute on function public.my_chat_summaries() to authenticated;

-- ------------------------------------------------------------- backfill ---
-- Every club gets its chat with its current members (and owner). No message,
-- no notification, so nobody is pinged.
do $$
declare r record; v_conv uuid;
begin
  for r in select id, owner_id from public.clubs loop
    v_conv := public.ensure_club_chat(r.id);
    insert into public.conversation_members (conversation_id, user_id)
    select v_conv, u from (
      select r.owner_id as u
      union
      select cm.user_id from public.club_members cm where cm.club_id = r.id
    ) t
    where u is not null
    on conflict do nothing;
  end loop;
end $$;
