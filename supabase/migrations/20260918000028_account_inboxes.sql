-- Each account has its own inbox.
--   * conversations.club_id / vendor_id = the account a chat belongs to
--     (null = personal). Meet chats inherit it from the event; "message the
--     club / partner" DMs carry it too.
--   * messages.as_club / as_vendor = sent while acting as that account; the
--     bubble shows the club or partner, not the person behind it.
--   * conversation_members.muted_at = muted (no badge counts).

alter table public.conversations
  add column if not exists club_id   uuid references public.clubs (id) on delete set null,
  add column if not exists vendor_id uuid references public.vendors (id) on delete set null;
create index if not exists conversations_club_idx on public.conversations (club_id) where club_id is not null;
create index if not exists conversations_vendor_idx on public.conversations (vendor_id) where vendor_id is not null;

alter table public.messages
  add column if not exists as_club   uuid references public.clubs (id) on delete set null,
  add column if not exists as_vendor uuid references public.vendors (id) on delete set null;

alter table public.conversation_members add column if not exists muted_at timestamptz;

-- Meet chats belong to whoever hosts the meet.
update public.conversations c set club_id = e.club_id, vendor_id = e.vendor_id
from public.events e where e.id = c.event_id and (c.club_id is distinct from e.club_id or c.vendor_id is distinct from e.vendor_id);

create or replace function public.get_or_create_meet_chat(p_event uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  conv uuid;
  allowed boolean;
  ev public.events;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into ev from public.events where id = p_event;
  select (ev.organizer_id = me) or exists (select 1 from public.event_attendees a where a.event_id = ev.id and a.user_id = me)
    into allowed;
  if not coalesce(allowed, false) then raise exception 'Join the meet to open its chat'; end if;

  select id into conv from public.conversations where event_id = p_event;
  if conv is null then
    insert into public.conversations (kind, event_id, club_id, vendor_id) values ('meet', p_event, ev.club_id, ev.vendor_id) returning id into conv;
  end if;
  insert into public.conversation_members (conversation_id, user_id) values (conv, me) on conflict do nothing;
  return conv;
end;
$$;

-- Can I speak for this club / partner?
create or replace function public.can_act_as_club(p_club uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.club_members m where m.club_id = p_club and m.user_id = p_user and m.role in ('owner', 'admin'))
      or exists (select 1 from public.clubs c where c.id = p_club and c.owner_id = p_user);
$$;
create or replace function public.can_act_as_vendor(p_vendor uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.vendors v where v.id = p_vendor and v.owner_id = p_user and v.active);
$$;

-- Only managers may send as the club / partner, and only inside its chats.
create or replace function public.check_message_actor() returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.conversations;
begin
  if new.as_club is null and new.as_vendor is null then return new; end if;
  select * into c from public.conversations where id = new.conversation_id;
  if new.as_club is not null and (c.club_id is distinct from new.as_club or not public.can_act_as_club(new.as_club, new.sender_id)) then
    raise exception 'You cannot send as this club here';
  end if;
  if new.as_vendor is not null and (c.vendor_id is distinct from new.as_vendor or not public.can_act_as_vendor(new.as_vendor, new.sender_id)) then
    raise exception 'You cannot send as this partner here';
  end if;
  return new;
end; $$;
drop trigger if exists messages_check_actor on public.messages;
create trigger messages_check_actor before insert on public.messages for each row execute function public.check_message_actor();

-- "Message the club": one DM per (person, club); the club's managers are in it.
create or replace function public.get_or_create_club_dm(p_club uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); conv uuid; owner uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select owner_id into owner from public.clubs where id = p_club;
  if owner is null then raise exception 'No such club'; end if;
  if public.can_act_as_club(p_club, me) then raise exception 'You run this club. Open its inbox instead.'; end if;
  select c.id into conv from public.conversations c
  where c.kind = 'dm' and c.club_id = p_club
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = me)
  limit 1;
  if conv is null then
    insert into public.conversations (kind, club_id) values ('dm', p_club) returning id into conv;
    insert into public.conversation_members (conversation_id, user_id) values (conv, me) on conflict do nothing;
  end if;
  -- (re)add every current manager so the whole club team sees it
  insert into public.conversation_members (conversation_id, user_id)
  select conv, u from (
    select owner as u
    union select m.user_id from public.club_members m where m.club_id = p_club and m.role in ('owner', 'admin')
  ) t on conflict do nothing;
  return conv;
end; $$;

create or replace function public.get_or_create_vendor_dm(p_vendor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); conv uuid; owner uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select owner_id into owner from public.vendors where id = p_vendor and active;
  if owner is null then raise exception 'No such partner'; end if;
  if owner = me then raise exception 'This is your own partner account.'; end if;
  select c.id into conv from public.conversations c
  where c.kind = 'dm' and c.vendor_id = p_vendor
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = me)
  limit 1;
  if conv is null then
    insert into public.conversations (kind, vendor_id) values ('dm', p_vendor) returning id into conv;
    insert into public.conversation_members (conversation_id, user_id) values (conv, me), (conv, owner) on conflict do nothing;
  end if;
  return conv;
end; $$;

create or replace function public.set_conversation_mute(p_conversation uuid, p_muted boolean)
returns void language sql security definer set search_path = public as $$
  update public.conversation_members set muted_at = case when p_muted then now() else null end
  where conversation_id = p_conversation and user_id = auth.uid();
$$;

-- Admin members list: partner flag + search-friendly columns.
drop function if exists public.admin_recent_users(int);
create function public.admin_recent_users(p_limit int default 200)
returns table (id uuid, username text, display_name text, avatar_url text, created_at timestamptz, home_state text,
               is_admin boolean, club_owner boolean, cars int, last_seen timestamptz, phone text, is_partner boolean, email text)
language sql stable security definer set search_path = public, auth as $$
  select p.id, p.username::text, p.display_name, p.avatar_url, p.created_at, p.home_state,
         p.is_admin, p.club_owner,
         (select count(*)::int from public.cars c where c.owner_id = p.id),
         (select max(l.updated_at) from public.user_locations l where l.user_id = p.id),
         pp.phone,
         exists (select 1 from public.vendors v where v.owner_id = p.id and v.active),
         u.email::text
  from public.profiles p
  left join public.profile_private pp on pp.user_id = p.id
  left join auth.users u on u.id = p.id
  where public.is_admin()
  order by p.created_at desc
  limit greatest(1, least(p_limit, 1000));
$$;
