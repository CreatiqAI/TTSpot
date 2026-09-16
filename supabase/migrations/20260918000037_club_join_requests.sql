-- Members can ask to join a club; the owner and admins approve or decline.

create table if not exists public.club_join_requests (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  message     text check (message is null or char_length(message) <= 200),
  status      text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'cancelled')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  decided_by  uuid references public.profiles (id) on delete set null
);
create unique index if not exists club_join_requests_one_pending on public.club_join_requests (club_id, user_id) where status = 'pending';
create index if not exists club_join_requests_club_idx on public.club_join_requests (club_id, status, created_at);
alter table public.club_join_requests enable row level security;
drop policy if exists "club requests: read own or admin" on public.club_join_requests;
create policy "club requests: read own or admin" on public.club_join_requests for select to authenticated
  using (user_id = auth.uid() or public.is_club_admin(club_id));

-- Ask to join. Owner and admins get a notification.
create or replace function public.request_club_join(p_club uuid, p_message text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_admin uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if exists (select 1 from public.club_members where club_id = p_club and user_id = auth.uid()) then
    raise exception 'You are already a member';
  end if;
  if exists (select 1 from public.club_join_requests where club_id = p_club and user_id = auth.uid() and status = 'pending') then
    raise exception 'You already asked. The club will get back to you.';
  end if;
  insert into public.club_join_requests (club_id, user_id, message) values (p_club, auth.uid(), nullif(trim(p_message), ''))
  returning id into v_id;
  for v_admin in
    select owner_id from public.clubs where id = p_club
    union
    select user_id from public.club_members where club_id = p_club and role in ('owner', 'admin')
  loop
    perform public.notify(v_admin, auth.uid(), 'club_request', p_club => p_club, p_body => 'new:' || coalesce(nullif(trim(p_message), ''), ''));
  end loop;
  return v_id;
end;
$$;

create or replace function public.cancel_club_request(p_club uuid) returns void
language sql security definer set search_path = public as $$
  update public.club_join_requests set status = 'cancelled', decided_at = now()
  where club_id = p_club and user_id = auth.uid() and status = 'pending';
$$;

-- 'pending' while waiting, 'declined' for a week after a no, else null.
create or replace function public.my_club_request(p_club uuid) returns text
language sql stable security definer set search_path = public as $$
  select status from public.club_join_requests
  where club_id = p_club and user_id = auth.uid()
    and (status = 'pending' or (status = 'declined' and decided_at > now() - interval '7 days'))
  order by created_at desc limit 1;
$$;

-- Pending requests on a club, for its owner and admins.
create or replace function public.club_join_requests_for(p_club uuid)
returns table (id uuid, user_id uuid, message text, created_at timestamptz, username text, display_name text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select r.id, r.user_id, r.message, r.created_at, p.username::text, p.display_name, p.avatar_url
  from public.club_join_requests r join public.profiles p on p.id = r.user_id
  where r.club_id = p_club and r.status = 'pending' and public.is_club_admin(p_club)
  order by r.created_at;
$$;

-- Approve (joins as a member) or decline. Owner and admins only.
create or replace function public.review_club_request(p_id uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.club_join_requests%rowtype;
begin
  select * into r from public.club_join_requests where id = p_id and status = 'pending' for update;
  if r.id is null then raise exception 'That request is gone'; end if;
  if not public.is_club_admin(r.club_id) then raise exception 'Only the club owner and admins can do that'; end if;
  update public.club_join_requests
     set status = case when p_approve then 'approved' else 'declined' end, decided_at = now(), decided_by = auth.uid()
   where id = p_id;
  if p_approve then
    insert into public.club_members (club_id, user_id) values (r.club_id, r.user_id) on conflict do nothing;
    perform public.notify(r.user_id, auth.uid(), 'club_request', p_club => r.club_id, p_body => 'approved');
  else
    perform public.notify(r.user_id, auth.uid(), 'club_request', p_club => r.club_id, p_body => 'declined');
  end if;
end;
$$;
