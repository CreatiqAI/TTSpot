-- =============================================================================
-- Phase 5: simpler app, club accounts, friend suggestions.
--
-- * A club is an account you can switch into. Posts made while acting as the
--   club carry `as_club = true` and render with the club as the author. Only
--   the owner and the club's admins can post as the club.
-- * Owners invite members to help run the club (`club_invites.role = 'admin'`).
--   Accepting makes them an admin; the owner can demote or remove them.
-- * Meets have a visibility: everyone, or friends (and club members) only.
-- * `suggest_friends()` for the Friends page: mutual friends, same club,
--   same car make, same state, else newest members.
-- =============================================================================

-- ------------------------------------------------------------ post as club ---
alter table public.posts add column as_club boolean not null default false;
drop policy "posts: insert own" on public.posts;
create policy "posts: insert own" on public.posts for insert to authenticated
  with check (author_id = auth.uid() and (not as_club or (club_id is not null and public.is_club_admin(club_id))));

-- --------------------------------------------------------- meet visibility ---
alter table public.events add column visibility text not null default 'public' check (visibility in ('public', 'friends'));

create or replace function public.is_event_attendee(p_event uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.event_attendees where event_id = p_event and user_id = p_user);
$$;

create or replace function public.is_club_member(p_club uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.club_members where club_id = p_club and user_id = p_user);
$$;

drop policy "events: authenticated can read" on public.events;
create policy "events: read visible" on public.events for select to authenticated
  using (visibility = 'public'
     or organizer_id = auth.uid()
     or public.is_friend(auth.uid(), organizer_id)
     or (club_id is not null and public.is_club_member(club_id))
     or public.is_event_attendee(id));

-- Meets tagged to a club must come from someone in it.
drop policy "events: organizer can insert" on public.events;
create policy "events: organizer can insert" on public.events for insert to authenticated
  with check (organizer_id = auth.uid() and (club_id is null or public.is_club_member(club_id)));

-- ------------------------------------------------------- club admin invites ---
alter table public.club_invites add column role text not null default 'member' check (role in ('member', 'admin'));

drop function if exists public.invite_to_club(uuid, uuid);
create or replace function public.invite_to_club(p_club uuid, p_user uuid, p_role text default 'member') returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_name text;
  v_role text := coalesce(p_role, 'member');
  v_owner uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if v_role not in ('member', 'admin') then raise exception 'Unknown role'; end if;
  select owner_id, name into v_owner, v_name from public.clubs where id = p_club;
  if v_name is null then raise exception 'Club not found'; end if;
  if v_role = 'admin' and v_owner <> auth.uid() then raise exception 'Only the club owner can add admins'; end if;
  if v_role = 'member' and not public.is_club_admin(p_club) then raise exception 'Only the club owner or an admin can invite'; end if;
  if p_user = auth.uid() then raise exception 'That is you'; end if;
  if v_role = 'member' and exists (select 1 from public.club_members where club_id = p_club and user_id = p_user) then
    raise exception 'Already a member';
  end if;
  if v_role = 'admin' and exists (select 1 from public.club_members where club_id = p_club and user_id = p_user and role in ('owner', 'admin')) then
    raise exception 'Already an admin';
  end if;
  if exists (select 1 from public.club_invites where club_id = p_club and invitee_id = p_user and status = 'pending') then
    raise exception 'Already invited';
  end if;
  insert into public.club_invites (club_id, inviter_id, invitee_id, role) values (p_club, auth.uid(), p_user, v_role) returning id into v_id;
  perform public.notify(p_user, auth.uid(), 'club_invite', p_club => p_club,
    p_body => case when v_role = 'admin' then 'admin:' else '' end || v_name);
  return v_id;
end;
$$;

create or replace function public.respond_club_invite(p_club uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  inv public.club_invites%rowtype;
begin
  select * into inv from public.club_invites where club_id = p_club and invitee_id = auth.uid() and status = 'pending'
  order by created_at desc limit 1 for update;
  if inv.id is null then raise exception 'No invite found'; end if;
  update public.club_invites set status = case when p_accept then 'accepted' else 'declined' end, decided_at = now() where id = inv.id;
  if p_accept then
    insert into public.club_members (club_id, user_id, role) values (p_club, auth.uid(), inv.role)
    on conflict (club_id, user_id) do update
      set role = case when excluded.role = 'admin' then 'admin' else public.club_members.role end;
    perform public.notify(inv.inviter_id, auth.uid(), 'club_join', p_club => p_club,
      p_body => case when inv.role = 'admin' then 'admin' else null end);
  end if;
end;
$$;

-- The pending invite for me on this club, with its role (null if none).
create or replace function public.my_club_invite_role(p_club uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.club_invites where club_id = p_club and invitee_id = auth.uid() and status = 'pending' order by created_at desc limit 1;
$$;

-- Owner demotes an admin back to member.
create or replace function public.set_club_role(p_club uuid, p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.clubs where id = p_club and owner_id = auth.uid()) then
    raise exception 'Only the club owner can change roles';
  end if;
  if p_role not in ('member', 'admin') then raise exception 'Unknown role'; end if;
  if p_user = auth.uid() then raise exception 'The owner stays the owner'; end if;
  update public.club_members set role = p_role where club_id = p_club and user_id = p_user;
end;
$$;

-- Owner or admin removes a member (never the owner).
create or replace function public.remove_club_member(p_club uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_club_admin(p_club) then raise exception 'Only the club owner or an admin can remove members'; end if;
  if exists (select 1 from public.clubs where id = p_club and owner_id = p_user) then raise exception 'The owner cannot be removed'; end if;
  delete from public.club_members where club_id = p_club and user_id = p_user;
end;
$$;

-- Who does what in a club (for the members list and the account switcher).
create or replace function public.club_member_roles(p_club uuid) returns table (user_id uuid, role text)
language sql stable security definer set search_path = public as $$
  select user_id, role from public.club_members where club_id = p_club;
$$;

create or replace function public.my_club_roles() returns table (club_id uuid, role text)
language sql stable security definer set search_path = public as $$
  select m.club_id, case when c.owner_id = auth.uid() then 'owner' else m.role end
  from public.club_members m join public.clubs c on c.id = m.club_id
  where m.user_id = auth.uid();
$$;

-- ------------------------------------------------------- friend suggestions ---
create or replace function public.suggest_friends(p_limit int default 12)
returns table (id uuid, username text, display_name text, bio text, avatar_url text, home_state text, created_at timestamptz, reason text, score int)
language sql stable security definer set search_path = public as $$
  with me as (select * from public.profiles where profiles.id = auth.uid()),
  my_makes as (select distinct lower(c.make) mk from public.cars c where c.owner_id = auth.uid()),
  my_clubs as (select m.club_id from public.club_members m where m.user_id = auth.uid()),
  my_friends as (
    select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end fid
    from public.friendships f where f.status = 'accepted' and auth.uid() in (f.requester_id, f.addressee_id)),
  excluded as (
    select auth.uid() uid
    union select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
          from public.friendships f where auth.uid() in (f.requester_id, f.addressee_id)
    union select b.blocked_id from public.blocks b where b.blocker_id = auth.uid()
    union select b.blocker_id from public.blocks b where b.blocked_id = auth.uid()),
  scored as (
    select p.id, p.username::text as username, p.display_name, p.bio, p.avatar_url, p.home_state, p.created_at,
      (select count(*) from my_friends mf join public.friendships x
         on x.status = 'accepted' and ((x.requester_id = mf.fid and x.addressee_id = p.id) or (x.addressee_id = mf.fid and x.requester_id = p.id)))::int as mutual,
      (select c.name from public.club_members m join public.clubs c on c.id = m.club_id
         where m.user_id = p.id and m.club_id in (select club_id from my_clubs) limit 1) as club_name,
      (select initcap(c.make) from public.cars c where c.owner_id = p.id and lower(c.make) in (select mk from my_makes) limit 1) as same_make,
      (p.home_state is not null and p.home_state = (select home_state from me)) as same_state
    from public.profiles p
    where p.id not in (select uid from excluded where uid is not null) and p.username is not null)
  select s.id, s.username, s.display_name, s.bio, s.avatar_url, s.home_state, s.created_at,
    case when s.mutual > 0 then s.mutual || ' mutual friend' || case when s.mutual = 1 then '' else 's' end
         when s.club_name is not null then 'In ' || s.club_name
         when s.same_make is not null then 'Drives a ' || s.same_make || ' too'
         when s.same_state then 'Also in ' || s.home_state
         else 'New on TT Spot' end as reason,
    (s.mutual * 3 + case when s.club_name is not null then 4 else 0 end + case when s.same_make is not null then 3 else 0 end
       + case when s.same_state then 2 else 0 end)::int as score
  from scored s
  order by score desc, s.created_at desc
  limit p_limit;
$$;
