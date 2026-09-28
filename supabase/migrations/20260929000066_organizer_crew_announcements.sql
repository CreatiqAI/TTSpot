-- =============================================================================
-- Organizer tools, part one: the verified Organizer role, event crew and
-- scheduled announcements. The lucky draw is in 0067.
--
-- * Organizer: a third application kind next to 'vendor' and 'club'. An admin
--   approves it (or grants it from the members list) and profiles.is_organizer
--   is set. Only meets hosted by an organizer (or an admin) get the tools.
-- * Crew: per-event helpers. 'cohost' = everything the host can do at the door
--   plus announcements and the draw; 'crew' = check-in QR, confirm arrivals,
--   scan prize claims. is_meet_host() now includes co-hosts; is_event_crew()
--   is host, co-host or crew.
-- * Announcements: host / co-host writes a title + message for an audience
--   (checked in / going / linked / everyone). Sent now or at a time inside the
--   event period (start - 1 day .. end + 1 day). pg_cron sends the due ones
--   every minute as 'announcement' notifications, which the push hook turns
--   into phone pushes (same path as the meet-start push, 0058).
-- =============================================================================

-- =============================================================================
-- organizer role
-- =============================================================================
alter table public.profiles add column if not exists is_organizer boolean not null default false;

-- Role flags are only ever changed by security-definer RPCs (admin approve,
-- admin_set_role, admin_set_organizer). A member updating their own profile
-- row directly cannot flip them.
create or replace function public.guard_profile_roles() returns trigger
language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.is_organizer := old.is_organizer;
    new.is_admin     := old.is_admin;
    new.club_owner   := old.club_owner;
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_guard_roles on public.profiles;
create trigger profiles_guard_roles before update on public.profiles
  for each row execute function public.guard_profile_roles();

create or replace function public.is_organizer(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select p_user is not null
     and coalesce((select p.is_organizer or p.is_admin from public.profiles p where p.id = p_user), false);
$$;

-- Organizer tools are on for a meet when its host is a verified organizer.
create or replace function public.event_has_organizer_tools(p_event uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select public.is_organizer(e.organizer_id) from public.events e where e.id = p_event), false);
$$;

-- ------------------------------------------------------ the application ---
alter table public.partner_applications drop constraint if exists partner_applications_kind_check;
alter table public.partner_applications
  add constraint partner_applications_kind_check check (kind in ('vendor', 'club', 'organizer'));
alter table public.partner_applications
  add column if not exists website text,       -- organizer: Instagram / website
  add column if not exists event_size text;    -- organizer: typical turnout ('<30', '30-100', '100-300', '300+')

create or replace function public.apply_organizer(p_name text, p_links text default null, p_size text default null, p_description text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_admin uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if char_length(trim(coalesce(p_name, ''))) < 2 then raise exception 'Enter your organisation or crew name'; end if;
  if exists (select 1 from public.profiles where id = auth.uid() and is_organizer) then
    raise exception 'You are already a verified organizer';
  end if;
  if exists (select 1 from public.partner_applications where user_id = auth.uid() and kind = 'organizer' and status = 'pending') then
    raise exception 'You already have an application waiting for review';
  end if;
  insert into public.partner_applications (user_id, kind, business_name, business_type, website, event_size, description)
  values (auth.uid(), 'organizer', left(trim(p_name), 80), 'organizer', nullif(trim(coalesce(p_links, '')), ''),
          nullif(trim(coalesce(p_size, '')), ''), nullif(trim(coalesce(p_description, '')), ''))
  returning id into v_id;
  for v_admin in select id from public.profiles where is_admin loop
    perform public.notify(v_admin, auth.uid(), 'partner', p_body => 'applied-organizer:' || trim(p_name));
  end loop;
  return v_id;
end;
$$;

-- Same as 0041 plus the organizer branch.
create or replace function public.admin_review_partner(p_id uuid, p_approve boolean, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  a public.partner_applications%rowtype;
  v_vendor uuid;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select * into a from public.partner_applications where id = p_id for update;
  if a.id is null then raise exception 'Application not found'; end if;
  if a.status <> 'pending' then raise exception 'Already decided'; end if;
  update public.partner_applications
     set status = case when p_approve then 'approved' else 'rejected' end,
         reason = p_note, decided_at = now(), decided_by = auth.uid()
   where id = p_id;
  if p_approve then
    if a.kind = 'organizer' then
      update public.profiles set is_organizer = true where id = a.user_id;
      perform public.notify(a.user_id, null, 'partner', p_body => 'approved-organizer:' || a.business_name);
    elsif a.kind = 'club' then
      update public.profiles set club_owner = true where id = a.user_id;
      perform public.notify(a.user_id, null, 'partner', p_body => 'approved-club:' || a.business_name);
    else
      insert into public.vendors (owner_id, name, type, address, place_id, phone, description, logo_url, application_id, lat, lng, state, plan_until)
      values (a.user_id, a.business_name, a.business_type, a.address, a.place_id, a.phone, a.description, a.logo_url, a.id, a.lat, a.lng, a.state, now() + interval '30 days')
      on conflict (owner_id) do update
        set name = excluded.name, type = excluded.type, address = excluded.address,
            phone = excluded.phone, description = excluded.description, logo_url = excluded.logo_url, active = true,
            application_id = excluded.application_id, lat = coalesce(excluded.lat, vendors.lat), lng = coalesce(excluded.lng, vendors.lng),
            state = coalesce(excluded.state, vendors.state), plan_until = greatest(coalesce(vendors.plan_until, now()), now()) + interval '30 days'
      returning id into v_vendor;
      perform public.sync_vendor_place(v_vendor);
      perform public.notify(a.user_id, null, 'partner', p_body => 'approved:' || a.business_name);
    end if;
  else
    perform public.notify(a.user_id, null, 'partner',
      p_body => case a.kind when 'club' then 'rejected-club:' when 'organizer' then 'rejected-organizer:' else 'rejected:' end
                || coalesce(p_note, 'no reason given'));
  end if;
end;
$$;

-- Queue now carries the organizer fields (and the partner state / shop photo).
drop function if exists public.admin_partner_queue(int);
create function public.admin_partner_queue(p_limit int default 100)
returns table (id uuid, kind text, user_id uuid, username text, avatar_url text, business_name text, business_type text, address text, place_id uuid,
               place_name text, phone text, ssm_no text, description text, logo_url text, status text, created_at timestamptz,
               state text, shop_photo_url text, website text, event_size text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select a.id, a.kind, a.user_id, pr.username::text, pr.avatar_url, a.business_name, a.business_type, a.address, a.place_id, p.name,
           a.phone, a.ssm_no, a.description, a.logo_url, a.status, a.created_at,
           a.state, a.shop_photo_url, a.website, a.event_size
    from public.partner_applications a
    join public.profiles pr on pr.id = a.user_id
    left join public.places p on p.id = a.place_id
    where a.status = 'pending'
    order by a.created_at asc
    limit p_limit;
end;
$$;

-- Admins can also grant or remove the role from the members list.
create or replace function public.admin_set_organizer(p_user uuid, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_was boolean;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select is_organizer into v_was from public.profiles where id = p_user;
  if v_was is null then raise exception 'Member not found'; end if;
  update public.profiles set is_organizer = p_on where id = p_user;
  if p_on and not v_was then
    perform public.notify(p_user, null, 'partner', p_body => 'approved-organizer:TT Spot');
  end if;
end;
$$;

-- Admin members list: + is_organizer (last column).
drop function if exists public.admin_recent_users(int);
create function public.admin_recent_users(p_limit int default 200)
returns table (id uuid, username text, display_name text, avatar_url text, created_at timestamptz, home_state text,
               is_admin boolean, club_owner boolean, cars int, last_seen timestamptz, phone text, is_partner boolean, email text,
               is_organizer boolean)
language sql stable security definer set search_path = public, auth as $$
  select p.id, p.username::text, p.display_name, p.avatar_url, p.created_at, p.home_state,
         p.is_admin, p.club_owner,
         (select count(*)::int from public.cars c where c.owner_id = p.id),
         (select max(l.updated_at) from public.user_locations l where l.user_id = p.id),
         pp.phone,
         exists (select 1 from public.vendors v where v.owner_id = p.id and v.active),
         u.email::text,
         p.is_organizer
  from public.profiles p
  left join public.profile_private pp on pp.user_id = p.id
  left join auth.users u on u.id = p.id
  where public.is_admin()
  order by p.created_at desc
  limit greatest(1, least(p_limit, 1000));
$$;

-- =============================================================================
-- crew
-- =============================================================================
create table if not exists public.event_crew (
  event_id    uuid not null references public.events (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        text not null default 'crew' check (role in ('cohost', 'crew')),
  added_by    uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  primary key (event_id, user_id)
);
create index if not exists event_crew_user_idx on public.event_crew (user_id);
alter table public.event_crew enable row level security;
-- writes only through the RPCs below

-- Host, admins, officers of the hosting club (as before) and now co-hosts.
create or replace function public.is_meet_host(p_event uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select p_user is not null and exists (
    select 1 from public.events e
    where e.id = p_event
      and (e.organizer_id = p_user or public.is_admin(p_user)
           or exists (select 1 from public.event_crew k where k.event_id = e.id and k.user_id = p_user and k.role = 'cohost')
           or (e.club_id is not null and exists (select 1 from public.club_members m
                 where m.club_id = e.club_id and m.user_id = p_user and m.role in ('owner', 'vp', 'secretary'))))
  );
$$;

-- Anyone working the meet: host circle or crew.
create or replace function public.is_event_crew(p_event uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select p_user is not null and (
    public.is_meet_host(p_event, p_user)
    or exists (select 1 from public.event_crew k where k.event_id = p_event and k.user_id = p_user)
  );
$$;

create policy "event_crew: read if on the crew" on public.event_crew for select to authenticated
  using (user_id = auth.uid() or public.is_event_crew(event_id));

-- What I am at this meet, for the app: role ('host' | 'cohost' | 'crew' |
-- 'admin' | null) and whether the organizer tools are on for it.
create or replace function public.my_event_role(p_event uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  e public.events;
  v_role text;
begin
  select * into e from public.events where id = p_event;
  if e.id is null or me is null then return null; end if;
  if e.organizer_id = me then v_role := 'host';
  else
    select k.role into v_role from public.event_crew k where k.event_id = p_event and k.user_id = me;
    if v_role is null and public.is_meet_host(p_event, me) then
      v_role := case when public.is_admin(me) then 'admin' else 'cohost' end;   -- club officers act as co-hosts
    end if;
  end if;
  return jsonb_build_object(
    'role', v_role,
    'tools', public.is_organizer(e.organizer_id),
    'host_verified', coalesce((select p.is_organizer from public.profiles p where p.id = e.organizer_id), false),
    'i_am_organizer', public.is_organizer(me)
  );
end;
$$;

create or replace function public.event_crew_list(p_event uuid)
returns table (user_id uuid, username text, display_name text, avatar_url text, role text, added_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_event_crew(p_event) then raise exception 'Only the crew can see this'; end if;
  return query
    select x.uid, x.uname, x.dname, x.avatar, x.r, x.at
    from (
      select p.id as uid, p.username::text as uname, p.display_name as dname, p.avatar_url as avatar,
             'host'::text as r, e.created_at as at, 0 as ord
        from public.events e join public.profiles p on p.id = e.organizer_id
       where e.id = p_event
      union all
      select p.id, p.username::text, p.display_name, p.avatar_url, k.role, k.created_at,
             case k.role when 'cohost' then 1 else 2 end
        from public.event_crew k join public.profiles p on p.id = k.user_id
       where k.event_id = p_event
    ) x
    order by x.ord, x.at;
end;
$$;

-- Add someone or change their role. The host (or an admin) manages everyone;
-- a co-host can add and remove crew but not co-hosts.
create or replace function public.event_crew_set(p_event uuid, p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  e public.events;
  v_full boolean;
  v_old text;
begin
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  if p_role not in ('cohost', 'crew') then raise exception 'Unknown role'; end if;
  if not public.is_organizer(e.organizer_id) then raise exception 'Crew is for verified organizers. Apply in Me > Apply to be an organizer.'; end if;
  v_full := e.organizer_id = me or public.is_admin(me);
  if not (v_full or public.is_meet_host(p_event, me)) then raise exception 'Only the host can manage the crew'; end if;
  if p_user = e.organizer_id then raise exception 'The host is already running this meet'; end if;
  select role into v_old from public.event_crew where event_id = p_event and user_id = p_user;
  if not v_full and (p_role = 'cohost' or v_old = 'cohost') then raise exception 'Only the host can add or change co-hosts'; end if;
  if v_old is null and (select count(*) from public.event_crew where event_id = p_event) >= 30 then
    raise exception 'A meet can have up to 30 crew';
  end if;
  insert into public.event_crew (event_id, user_id, role, added_by) values (p_event, p_user, p_role, me)
  on conflict (event_id, user_id) do update set role = excluded.role;
  if v_old is distinct from p_role then
    perform public.notify(p_user, me, 'announcement', p_event => p_event,
      p_body => case p_role when 'cohost' then 'You''re a co-host' else 'You''re on the crew' end
                || E'\n' || 'Open the meet and tap Organizer tools.');
  end if;
end;
$$;

create or replace function public.event_crew_remove(p_event uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  e public.events;
  v_old text;
begin
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  select role into v_old from public.event_crew where event_id = p_event and user_id = p_user;
  if v_old is null then return; end if;
  if not (p_user = me or e.organizer_id = me or public.is_admin(me)
          or (v_old = 'crew' and public.is_meet_host(p_event, me))) then
    raise exception 'Only the host can remove co-hosts';
  end if;
  delete from public.event_crew where event_id = p_event and user_id = p_user;
end;
$$;

-- ------------------------------------------- crew at the door (0058/0060) ---
-- Crew may show the check-in QR, see the door list and confirm arrivals.
create or replace function public.event_qr_payload(p_event uuid) returns text
language plpgsql security definer set search_path = public as $$
declare e public.events;
begin
  select * into e from public.events where id = p_event;
  if not found then raise exception 'No such meet'; end if;
  if e.organizer_id <> auth.uid() and not public.is_event_crew(p_event) then
    raise exception 'Only the organiser can show the check-in code';
  end if;
  return 'ttspot://checkin/' || p_event || '/' || public.event_qr_code_at(p_event, floor(extract(epoch from now()) / 30)::bigint);
end;
$$;

create or replace function public.host_confirm_checkin(p_event uuid, p_user uuid, p_confirmed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_event_crew(p_event) then raise exception 'Only the host or crew can confirm arrivals'; end if;
  update public.checkins
     set confirmed_at = case when p_confirmed then now() end,
         confirmed_by = auth.uid()
   where event_id = p_event and user_id = p_user;
end;
$$;

create or replace function public.host_confirm_all(p_event uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_event_crew(p_event) then raise exception 'Only the host or crew can confirm arrivals'; end if;
  update public.checkins
     set confirmed_at = now(), confirmed_by = auth.uid()
   where event_id = p_event and confirmed_at is null and confirmed_by is null;
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.auto_confirm_stayed(p_event uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; v_org uuid;
begin
  if not public.is_event_crew(p_event) then return 0; end if;
  if public.meet_mode(p_event) <> 'big' then return 0; end if;
  select organizer_id into v_org from public.events where id = p_event;
  update public.checkins c
     set confirmed_at = now(), confirmed_by = coalesce(v_org, auth.uid())
   where c.event_id = p_event and c.confirmed_at is null and c.confirmed_by is null
     and public.has_stayed(p_event, c.user_id);
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.event_checkin_list(p_event uuid)
returns table (
  user_id        uuid,
  username       text,
  display_name   text,
  avatar_url     text,
  car            text,
  checked_in_at  timestamptz,
  source         text,
  stayed_min     int,
  stayed         boolean,
  confirmed      boolean,
  rejected       boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_event_crew(p_event) then raise exception 'Only the host or crew can see who is here'; end if;
  return query
    select c.user_id, p.username::text, p.display_name, p.avatar_url,
           (select nullif(trim(concat_ws(' ', k.make, k.model)), '')
              from public.cars k where k.owner_id = c.user_id
             order by k.is_default desc, k.created_at desc limit 1),
           c.checked_in_at, c.source,
           coalesce(public.stayed_min(p_event, c.user_id), 0),
           public.has_stayed(p_event, c.user_id),
           c.confirmed_at is not null,
           c.confirmed_at is null and c.confirmed_by is not null
      from public.checkins c
      join public.profiles p on p.id = c.user_id
      join public.events e on e.id = c.event_id
     where c.event_id = p_event and c.user_id <> e.organizer_id
     order by c.checked_in_at desc;
end;
$$;

-- =============================================================================
-- announcements
-- =============================================================================
create table if not exists public.event_announcements (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references public.events (id) on delete cascade,
  author_id     uuid references public.profiles (id) on delete set null,
  title         text not null check (char_length(title) between 1 and 80),
  body          text not null check (char_length(body) between 1 and 500),
  send_at       timestamptz not null default now(),
  audience      text not null default 'linked' check (audience in ('checked_in', 'going', 'linked', 'everyone')),
  sent_at       timestamptz,
  recipients    int,
  cancelled_at  timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists event_announcements_event_idx on public.event_announcements (event_id, send_at desc);
create index if not exists event_announcements_due_idx on public.event_announcements (send_at) where sent_at is null and cancelled_at is null;
alter table public.event_announcements enable row level security;
create policy "announcements: host circle reads" on public.event_announcements for select to authenticated
  using (public.is_meet_host(event_id));
-- writes only through the RPCs below

-- The event period: announcements may go out from a day before the start
-- until a day after the end (end = ends_at, else start + 6 h).
create or replace function public.event_period(p_event uuid, out opens_at timestamptz, out closes_at timestamptz)
language sql stable security definer set search_path = public as $$
  select e.starts_at - interval '1 day', coalesce(e.ends_at, e.starts_at + interval '6 hours') + interval '1 day'
  from public.events e where e.id = p_event;
$$;

-- Who an audience reaches. 'linked' = checked in + RSVP'd + joined through the
-- event's invite code (public.event_referrals, when that table exists).
-- 'everyone' adds people who saved the meet and the crew.
create or replace function public.announcement_recipients(p_event uuid, p_audience text)
returns table (user_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  return query select c.user_id from public.checkins c where c.event_id = p_event;
  if p_audience in ('going', 'linked', 'everyone') then
    return query select a.user_id from public.event_attendees a where a.event_id = p_event;
  end if;
  if p_audience in ('linked', 'everyone') and to_regclass('public.event_referrals') is not null then
    return query execute 'select r.user_id from public.event_referrals r where r.event_id = $1' using p_event;
  end if;
  if p_audience = 'everyone' then
    return query select b.user_id from public.event_bookmarks b where b.event_id = p_event;
    return query select k.user_id from public.event_crew k where k.event_id = p_event;
  end if;
end;
$$;

-- 'going' means RSVP'd, not checked in: drop the check-ins again for it.
create or replace function public.announcement_audience(p_event uuid, p_audience text)
returns table (user_id uuid)
language sql stable security definer set search_path = public as $$
  select distinct r.user_id
  from public.announcement_recipients(p_event, p_audience) r
  where p_audience <> 'going'
     or exists (select 1 from public.event_attendees a where a.event_id = p_event and a.user_id = r.user_id);
$$;

create or replace function public.announcement_audience_count(p_event uuid, p_audience text) returns int
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can see this'; end if;
  return (select count(*)::int from public.announcement_audience(p_event, p_audience) a
          where a.user_id is distinct from auth.uid());
end;
$$;

-- Sends one announcement now. Internal: called by create (send now) and cron.
create or replace function public.send_event_announcement(p_id uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  a public.event_announcements;
  n int;
begin
  update public.event_announcements set sent_at = now()
   where id = p_id and sent_at is null and cancelled_at is null
  returning * into a;
  if a.id is null then return 0; end if;
  insert into public.notifications (user_id, actor_id, type, event_id, body)
  select r.user_id, a.author_id, 'announcement'::public.notification_type, a.event_id, a.title || E'\n' || a.body
    from public.announcement_audience(a.event_id, a.audience) r
   where r.user_id is distinct from a.author_id;
  get diagnostics n = row_count;
  update public.event_announcements set recipients = n where id = a.id;
  return n;
end;
$$;

create or replace function public.create_event_announcement(
  p_event uuid, p_title text, p_body text, p_audience text default 'linked', p_send_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e public.events;
  v_send timestamptz := coalesce(p_send_at, now());
  v_open timestamptz;
  v_close timestamptz;
  v_id uuid;
begin
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  if e.status = 'cancelled' then raise exception 'This meet was cancelled'; end if;
  if not public.is_meet_host(p_event) then raise exception 'Only the host or a co-host can send announcements'; end if;
  if not public.is_organizer(e.organizer_id) then raise exception 'Announcements are for verified organizers. Apply in Me > Apply to be an organizer.'; end if;
  if p_audience not in ('checked_in', 'going', 'linked', 'everyone') then raise exception 'Pick who it goes to'; end if;
  if char_length(trim(coalesce(p_title, ''))) = 0 then raise exception 'Add a title'; end if;
  if char_length(trim(coalesce(p_body, ''))) = 0 then raise exception 'Write the message'; end if;
  select opens_at, closes_at into v_open, v_close from public.event_period(p_event);
  if v_send < now() then v_send := now(); end if;
  if v_send < v_open or v_send > v_close then
    raise exception 'Announcements can go out from a day before the meet until a day after it ends';
  end if;
  if (select count(*) from public.event_announcements where event_id = p_event and cancelled_at is null) >= 30 then
    raise exception 'That''s the limit of 30 announcements for this meet';
  end if;
  insert into public.event_announcements (event_id, author_id, title, body, send_at, audience)
  values (p_event, auth.uid(), left(trim(p_title), 80), left(trim(p_body), 500), v_send, p_audience)
  returning id into v_id;
  if v_send <= now() + interval '30 seconds' then
    perform public.send_event_announcement(v_id);
  end if;
  return v_id;
end;
$$;

create or replace function public.cancel_event_announcement(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  select event_id into v_event from public.event_announcements where id = p_id;
  if v_event is null then raise exception 'Announcement not found'; end if;
  if not public.is_meet_host(v_event) then raise exception 'Only the host or a co-host can cancel it'; end if;
  update public.event_announcements set cancelled_at = now() where id = p_id and sent_at is null;
  if not found then raise exception 'It has already gone out'; end if;
end;
$$;

create or replace function public.event_announcement_list(p_event uuid)
returns table (id uuid, title text, body text, audience text, send_at timestamptz, sent_at timestamptz, cancelled_at timestamptz,
               recipients int, author_username text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host or a co-host can see announcements'; end if;
  return query
    select a.id, a.title, a.body, a.audience, a.send_at, a.sent_at, a.cancelled_at, a.recipients, p.username::text, a.created_at
      from public.event_announcements a left join public.profiles p on p.id = a.author_id
     where a.event_id = p_event
     order by (a.sent_at is null and a.cancelled_at is null) desc, a.send_at desc;
end;
$$;

-- Every minute: send what is due. Only the last hour counts, so a long cron
-- outage does not fire stale messages; anything older is marked cancelled.
-- Meets that were cancelled, or that left their event period, are skipped.
create or replace function public.due_event_announcements() returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  n int := 0;
begin
  update public.event_announcements a set cancelled_at = now()
   where a.sent_at is null and a.cancelled_at is null
     and (a.send_at < now() - interval '1 hour'
          or exists (select 1 from public.events e where e.id = a.event_id and e.status = 'cancelled'));
  for r in
    select a.id from public.event_announcements a
     where a.sent_at is null and a.cancelled_at is null and a.send_at <= now()
     order by a.send_at
     limit 200
  loop
    n := n + public.send_event_announcement(r.id);
  end loop;
  return n;
end;
$$;

do $outer$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron could not be created: %', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'ttspot-event-announcements') then
      perform cron.unschedule('ttspot-event-announcements');
    end if;
    perform cron.schedule('ttspot-event-announcements', '* * * * *', 'select public.due_event_announcements()');
  else
    raise notice 'pg_cron not available: schedule public.due_event_announcements() every minute some other way';
  end if;
end;
$outer$;

-- =============================================================================
-- grants
-- =============================================================================
revoke execute on function public.guard_profile_roles() from public, anon, authenticated;
revoke execute on function public.is_organizer(uuid) from public, anon;
revoke execute on function public.event_has_organizer_tools(uuid) from public, anon;
revoke execute on function public.apply_organizer(text, text, text, text) from public, anon;
revoke execute on function public.admin_review_partner(uuid, boolean, text) from public, anon;
revoke execute on function public.admin_partner_queue(int) from public, anon;
revoke execute on function public.admin_set_organizer(uuid, boolean) from public, anon;
revoke execute on function public.admin_recent_users(int) from public, anon;
revoke execute on function public.is_meet_host(uuid, uuid) from public, anon;
revoke execute on function public.is_event_crew(uuid, uuid) from public, anon;
revoke execute on function public.my_event_role(uuid) from public, anon;
revoke execute on function public.event_crew_list(uuid) from public, anon;
revoke execute on function public.event_crew_set(uuid, uuid, text) from public, anon;
revoke execute on function public.event_crew_remove(uuid, uuid) from public, anon;
revoke execute on function public.event_qr_payload(uuid) from public, anon;
revoke execute on function public.host_confirm_checkin(uuid, uuid, boolean) from public, anon;
revoke execute on function public.host_confirm_all(uuid) from public, anon;
revoke execute on function public.auto_confirm_stayed(uuid) from public, anon;
revoke execute on function public.event_checkin_list(uuid) from public, anon;
revoke execute on function public.event_period(uuid) from public, anon;
revoke execute on function public.announcement_recipients(uuid, text) from public, anon, authenticated;
revoke execute on function public.announcement_audience(uuid, text) from public, anon, authenticated;
revoke execute on function public.announcement_audience_count(uuid, text) from public, anon;
revoke execute on function public.send_event_announcement(uuid) from public, anon, authenticated;
revoke execute on function public.create_event_announcement(uuid, text, text, text, timestamptz) from public, anon;
revoke execute on function public.cancel_event_announcement(uuid) from public, anon;
revoke execute on function public.event_announcement_list(uuid) from public, anon;
revoke execute on function public.due_event_announcements() from public, anon, authenticated;

grant execute on function public.is_organizer(uuid) to authenticated;
grant execute on function public.event_has_organizer_tools(uuid) to authenticated;
grant execute on function public.apply_organizer(text, text, text, text) to authenticated;
grant execute on function public.admin_review_partner(uuid, boolean, text) to authenticated;
grant execute on function public.admin_partner_queue(int) to authenticated;
grant execute on function public.admin_set_organizer(uuid, boolean) to authenticated;
grant execute on function public.admin_recent_users(int) to authenticated;
grant execute on function public.is_meet_host(uuid, uuid) to authenticated;
grant execute on function public.is_event_crew(uuid, uuid) to authenticated;
grant execute on function public.my_event_role(uuid) to authenticated;
grant execute on function public.event_crew_list(uuid) to authenticated;
grant execute on function public.event_crew_set(uuid, uuid, text) to authenticated;
grant execute on function public.event_crew_remove(uuid, uuid) to authenticated;
grant execute on function public.event_qr_payload(uuid) to authenticated;
grant execute on function public.host_confirm_checkin(uuid, uuid, boolean) to authenticated;
grant execute on function public.host_confirm_all(uuid) to authenticated;
grant execute on function public.auto_confirm_stayed(uuid) to authenticated;
grant execute on function public.event_checkin_list(uuid) to authenticated;
grant execute on function public.event_period(uuid) to authenticated;
grant execute on function public.announcement_audience_count(uuid, text) to authenticated;
grant execute on function public.create_event_announcement(uuid, text, text, text, timestamptz) to authenticated;
grant execute on function public.cancel_event_announcement(uuid) to authenticated;
grant execute on function public.event_announcement_list(uuid) to authenticated;
