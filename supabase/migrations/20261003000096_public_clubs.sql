-- Public clubs: anyone can join right away. Private clubs keep the ask-to-join
-- flow (the president, VP and secretary approve). New clubs start public, and
-- every club that already exists becomes public too (owner's call): adding the
-- column with its default fills them in, and a re-run leaves a club's choice
-- alone.

alter table public.clubs
  add column if not exists join_policy text not null default 'public' check (join_policy in ('public', 'private'));

-- Joining goes through join_club(), an approved request or an accepted invite
-- (all security definer). The only direct insert left is the owner's own row
-- when the club is created. Before this, anyone could insert themselves into
-- any club with any role, officer roles included.
drop policy if exists "club_members: join self" on public.club_members;
drop policy if exists "club_members: owner adds self" on public.club_members;
create policy "club_members: owner adds self" on public.club_members for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.clubs c where c.id = club_members.club_id and c.owner_id = auth.uid()));

-- Join a public club now, as a member. 'joined', or 'member' when already in.
-- A real insert, so the club_members triggers (member cap, join notifications)
-- run as usual.
create or replace function public.join_club(p_club uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  c public.clubs%rowtype;
  v_n int;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into c from public.clubs where id = p_club;
  if c.id is null then raise exception 'Club not found'; end if;
  if exists (select 1 from public.club_members where club_id = p_club and user_id = auth.uid()) then return 'member'; end if;
  if exists (select 1 from public.profiles where id = auth.uid() and suspended_at is not null) then
    raise exception 'Your account is suspended';
  end if;
  if exists (select 1 from public.blocks b
             where (b.blocker_id = c.owner_id and b.blocked_id = auth.uid()) or (b.blocker_id = auth.uid() and b.blocked_id = c.owner_id)) then
    raise exception 'You can''t join this club';
  end if;
  if c.join_policy <> 'public' then raise exception 'This club is private now. Ask to join instead.'; end if;
  insert into public.club_members (club_id, user_id, role) values (p_club, auth.uid(), 'member')
  on conflict (club_id, user_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then return 'member'; end if;
  -- Anything still waiting is settled: they are in.
  update public.club_join_requests set status = 'approved', decided_at = now()
   where club_id = p_club and user_id = auth.uid() and status = 'pending';
  update public.club_invites set status = 'accepted', decided_at = now()
   where club_id = p_club and invitee_id = auth.uid() and status = 'pending' and role = 'member';
  return 'joined';
end;
$$;
revoke execute on function public.join_club(uuid) from public, anon;
grant execute on function public.join_club(uuid) to authenticated;

-- Who can join: 'public' or 'private'. The president, VP and secretary.
create or replace function public.set_club_join_policy(p_club uuid, p_policy text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_policy, '') not in ('public', 'private') then raise exception 'Pick public or private'; end if;
  if not public.is_club_admin(p_club) then raise exception 'Only the president, VP or secretary can change this'; end if;
  update public.clubs set join_policy = p_policy where id = p_club;
end;
$$;
revoke execute on function public.set_club_join_policy(uuid, text) from public, anon;
grant execute on function public.set_club_join_policy(uuid, text) to authenticated;

-- Ask to join (private clubs; older app versions also use it on public ones,
-- and the officers can still approve those). Now also refuses suspended
-- members and anyone blocked with the owner, and tells the VP and secretary
-- too ('admin' was renamed to them in 0041).
create or replace function public.request_club_join(p_club uuid, p_message text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_owner uuid;
  v_admin uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select owner_id into v_owner from public.clubs where id = p_club;
  if v_owner is null then raise exception 'Club not found'; end if;
  if exists (select 1 from public.club_members where club_id = p_club and user_id = auth.uid()) then
    raise exception 'You are already a member';
  end if;
  if exists (select 1 from public.profiles where id = auth.uid() and suspended_at is not null) then
    raise exception 'Your account is suspended';
  end if;
  if exists (select 1 from public.blocks b
             where (b.blocker_id = v_owner and b.blocked_id = auth.uid()) or (b.blocker_id = auth.uid() and b.blocked_id = v_owner)) then
    raise exception 'You can''t join this club';
  end if;
  if exists (select 1 from public.club_join_requests where club_id = p_club and user_id = auth.uid() and status = 'pending') then
    raise exception 'You already asked. The club will get back to you.';
  end if;
  insert into public.club_join_requests (club_id, user_id, message) values (p_club, auth.uid(), nullif(trim(p_message), ''))
  returning id into v_id;
  for v_admin in
    select v_owner
    union
    select user_id from public.club_members where club_id = p_club and role in ('owner', 'vp', 'secretary')
  loop
    perform public.notify(v_admin, auth.uid(), 'club_request', p_club => p_club, p_body => 'new:' || coalesce(nullif(trim(p_message), ''), ''));
  end loop;
  return v_id;
end;
$$;
