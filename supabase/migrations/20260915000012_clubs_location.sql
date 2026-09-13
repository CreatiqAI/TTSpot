-- =============================================================================
-- Phase 4: car-club owners, club invites, club location sharing, and
-- location-verified QR check-ins.
--
-- * Partner applications now carry a `kind`: 'vendor' (parts / accessories /
--   workshop) or 'club'. Approving a club application flags the member as a
--   club owner; only club owners (and admins) can create clubs.
-- * Owners invite members (friends) to the club; invitees accept in Activity.
-- * Club members see each other on the map, unless a member switches off
--   "share my location" for that club.
-- * A meet's QR can only be redeemed within `checkin_radius_m` of the meet.
-- =============================================================================

-- ------------------------------------------------------- application kind ---
alter table public.partner_applications
  add column kind text not null default 'vendor' check (kind in ('vendor', 'club'));
drop index if exists public.partner_applications_one_pending;
create unique index partner_applications_one_pending on public.partner_applications (user_id, kind) where status = 'pending';

alter table public.profiles add column club_owner boolean not null default false;

create or replace function public.apply_partner(
  p_name text, p_type text, p_address text default null, p_place uuid default null, p_phone text default null,
  p_description text default null, p_logo_url text default null, p_ssm text default null, p_kind text default 'vendor'
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_admin uuid;
  v_kind text := coalesce(p_kind, 'vendor');
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if v_kind not in ('vendor', 'club') then raise exception 'Unknown application kind'; end if;
  if v_kind = 'vendor' and exists (select 1 from public.vendors where owner_id = auth.uid()) then
    raise exception 'You are already a partner';
  end if;
  if v_kind = 'club' and exists (select 1 from public.profiles where id = auth.uid() and club_owner) then
    raise exception 'You are already a club owner';
  end if;
  if exists (select 1 from public.partner_applications where user_id = auth.uid() and kind = v_kind and status = 'pending') then
    raise exception 'You already have an application waiting for review';
  end if;
  insert into public.partner_applications (user_id, kind, business_name, business_type, address, place_id, phone, description, logo_url, ssm_no)
  values (auth.uid(), v_kind, trim(p_name), coalesce(p_type, case when v_kind = 'club' then 'club' else 'other' end),
          nullif(trim(p_address), ''), p_place, nullif(trim(p_phone), ''), nullif(trim(p_description), ''), p_logo_url, nullif(trim(p_ssm), ''))
  returning id into v_id;
  for v_admin in select id from public.profiles where is_admin loop
    perform public.notify(v_admin, auth.uid(), 'partner',
      p_body => case when v_kind = 'club' then 'applied-club:' else 'applied:' end || trim(p_name));
  end loop;
  return v_id;
end;
$$;

drop function if exists public.my_partner_application();
create or replace function public.my_partner_application(p_kind text default 'vendor')
returns table (id uuid, kind text, business_name text, business_type text, address text, place_id uuid, phone text, ssm_no text, description text,
               logo_url text, status text, reason text, created_at timestamptz, decided_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, a.kind, a.business_name, a.business_type, a.address, a.place_id, a.phone, a.ssm_no, a.description, a.logo_url,
         a.status, a.reason, a.created_at, a.decided_at
  from public.partner_applications a where a.user_id = auth.uid() and a.kind = coalesce(p_kind, 'vendor')
  order by a.created_at desc limit 1;
$$;

drop function if exists public.admin_partner_queue(int);
create or replace function public.admin_partner_queue(p_limit int default 100)
returns table (id uuid, kind text, user_id uuid, username text, avatar_url text, business_name text, business_type text, address text, place_id uuid,
               place_name text, phone text, ssm_no text, description text, logo_url text, status text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select a.id, a.kind, a.user_id, pr.username::text, pr.avatar_url, a.business_name, a.business_type, a.address, a.place_id, p.name,
           a.phone, a.ssm_no, a.description, a.logo_url, a.status, a.created_at
    from public.partner_applications a
    join public.profiles pr on pr.id = a.user_id
    left join public.places p on p.id = a.place_id
    where a.status = 'pending'
    order by a.created_at asc
    limit p_limit;
end;
$$;

create or replace function public.admin_review_partner(p_id uuid, p_approve boolean, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  a public.partner_applications%rowtype;
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
    if a.kind = 'club' then
      update public.profiles set club_owner = true where id = a.user_id;
      perform public.notify(a.user_id, null, 'partner', p_body => 'approved-club:' || a.business_name);
    else
      insert into public.vendors (owner_id, name, type, address, place_id, phone, description, logo_url, application_id)
      values (a.user_id, a.business_name, a.business_type, a.address, a.place_id, a.phone, a.description, a.logo_url, a.id)
      on conflict (owner_id) do update
        set name = excluded.name, type = excluded.type, address = excluded.address, place_id = excluded.place_id,
            phone = excluded.phone, description = excluded.description, logo_url = excluded.logo_url, active = true,
            application_id = excluded.application_id;
      perform public.notify(a.user_id, null, 'partner', p_body => 'approved:' || a.business_name);
    end if;
  else
    perform public.notify(a.user_id, null, 'partner',
      p_body => case when a.kind = 'club' then 'rejected-club:' else 'rejected:' end || coalesce(p_note, 'no reason given'));
  end if;
end;
$$;

-- Only approved club owners (and admins) start clubs from now on.
drop policy "clubs: insert own" on public.clubs;
create policy "clubs: insert own" on public.clubs for insert to authenticated
  with check (owner_id = auth.uid() and (public.is_admin() or coalesce((select club_owner from public.profiles where id = auth.uid()), false)));

-- ---------------------------------------------------------- club invites ---
create table public.club_invites (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs (id) on delete cascade,
  inviter_id  uuid not null references public.profiles (id) on delete cascade,
  invitee_id  uuid not null references public.profiles (id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);
create unique index club_invites_one_pending on public.club_invites (club_id, invitee_id) where status = 'pending';
create index club_invites_invitee_idx on public.club_invites (invitee_id, created_at desc);
alter table public.club_invites enable row level security;
create policy "club invites: read involved" on public.club_invites for select to authenticated
  using (invitee_id = auth.uid() or inviter_id = auth.uid());

create or replace function public.is_club_admin(p_club uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.club_members where club_id = p_club and user_id = p_user and role in ('owner', 'admin'))
      or exists (select 1 from public.clubs where id = p_club and owner_id = p_user);
$$;

create or replace function public.invite_to_club(p_club uuid, p_user uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_name text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not public.is_club_admin(p_club) then raise exception 'Only the club owner can invite'; end if;
  if p_user = auth.uid() then raise exception 'That is you'; end if;
  if exists (select 1 from public.club_members where club_id = p_club and user_id = p_user) then
    raise exception 'Already a member';
  end if;
  if exists (select 1 from public.club_invites where club_id = p_club and invitee_id = p_user and status = 'pending') then
    raise exception 'Already invited';
  end if;
  insert into public.club_invites (club_id, inviter_id, invitee_id) values (p_club, auth.uid(), p_user) returning id into v_id;
  select name into v_name from public.clubs where id = p_club;
  perform public.notify(p_user, auth.uid(), 'club_invite', p_club => p_club, p_body => v_name);
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
    insert into public.club_members (club_id, user_id) values (p_club, auth.uid()) on conflict do nothing;
    perform public.notify(inv.inviter_id, auth.uid(), 'club_join', p_club => p_club);
  end if;
end;
$$;

-- Pending invite for me on this club (null if none).
create or replace function public.my_club_invite(p_club uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.club_invites where club_id = p_club and invitee_id = auth.uid() and status = 'pending' limit 1;
$$;

-- ----------------------------------------------- club location sharing ---
alter table public.club_members add column share_location boolean not null default true;

create or replace function public.set_club_share(p_club uuid, p_share boolean) returns void
language sql security definer set search_path = public as $$
  update public.club_members set share_location = p_share where club_id = p_club and user_id = auth.uid();
$$;

-- Viewer and target share a club, and the target shares their location with it.
create or replace function public.is_clubmate_sharing(p_viewer uuid, p_target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.club_members a
    join public.club_members b on b.club_id = a.club_id
    where a.user_id = p_viewer and b.user_id = p_target and b.share_location
  );
$$;

drop policy "locations: read self or friends" on public.user_locations;
create policy "locations: read self, friends, clubmates" on public.user_locations for select to authenticated
  using (user_id = auth.uid()
     or (not ghost and expires_at > now() and (public.is_friend(auth.uid(), user_id) or public.is_clubmate_sharing(auth.uid(), user_id))));

-- Live pins with how I know the person: 'friend' or 'club' (+ the club's name).
create or replace function public.visible_pins()
returns table (user_id uuid, lat float8, lng float8, heading float8, accuracy float8, ghost boolean, place_id uuid, event_id uuid,
               updated_at timestamptz, profiles json, places json, events json, via text, club_name text)
language sql stable security definer set search_path = public as $$
  select l.user_id, l.lat, l.lng, l.heading, l.accuracy, l.ghost, l.place_id, l.event_id, l.updated_at,
         json_build_object('id', pr.id, 'username', pr.username, 'display_name', pr.display_name, 'bio', pr.bio,
                           'avatar_url', pr.avatar_url, 'home_state', pr.home_state, 'created_at', pr.created_at),
         case when p.id is null then null else json_build_object('name', p.name) end,
         case when e.id is null then null else json_build_object('title', e.title) end,
         case when public.is_friend(auth.uid(), l.user_id) then 'friend' else 'club' end,
         (select c.name from public.club_members a join public.club_members b on b.club_id = a.club_id join public.clubs c on c.id = a.club_id
           where a.user_id = auth.uid() and b.user_id = l.user_id and b.share_location limit 1)
  from public.user_locations l
  join public.profiles pr on pr.id = l.user_id
  left join public.places p on p.id = l.place_id
  left join public.events e on e.id = l.event_id
  where l.user_id <> auth.uid() and not l.ghost and l.expires_at > now()
    and (public.is_friend(auth.uid(), l.user_id) or public.is_clubmate_sharing(auth.uid(), l.user_id))
  order by l.updated_at desc;
$$;

-- My clubs with my share flag (for the club page toggle).
create or replace function public.my_club_share(p_club uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select share_location from public.club_members where club_id = p_club and user_id = auth.uid()), true);
$$;

-- ---------------------------------------------- location-verified QR ---
insert into public.platform_settings (key, value, description) values
  ('checkin_radius_m', '300', 'How close (metres) a member must be to a meet to redeem its check-in QR.')
on conflict (key) do nothing;

create or replace function public.checkin_by_qr(p_event uuid, p_code text, p_lat float8 default null, p_lng float8 default null) returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  w bigint := floor(extract(epoch from now()) / 30)::bigint;
  already boolean;
  e public.events%rowtype;
  v_dist float8;
  v_radius float8 := public.setting_num('checkin_radius_m', 300);
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_code is null or (p_code <> public.event_qr_code_at(p_event, w) and p_code <> public.event_qr_code_at(p_event, w - 1)) then
    raise exception 'That code has expired. Scan the organiser''s screen again.';
  end if;
  if p_lat is null or p_lng is null then
    raise exception 'Turn on location so we can confirm you are at the meet.';
  end if;
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  v_dist := public.metres_between(p_lat, p_lng, e.lat, e.lng);
  if v_dist > v_radius then
    raise exception 'You are % m from the meet. Get within % m to check in.', round(v_dist)::int, v_radius::int;
  end if;
  select exists (select 1 from public.checkins where event_id = p_event and user_id = me) into already;
  if not already then
    insert into public.checkins (event_id, user_id, lat, lng, source) values (p_event, me, p_lat, p_lng, 'qr');
  end if;
  return json_build_object('new', not already, 'points', public.rule_points('meet_checkin'), 'distance_m', round(v_dist)::int);
end;
$$;

-- Seeded clubs predate applications: their owners keep the right to run them.
update public.profiles set club_owner = true where id in (select owner_id from public.clubs);

update public.point_rules set description = 'Be at the meet (within 300 m) and scan the organiser''s QR while it''s live.' where reason = 'meet_checkin';
