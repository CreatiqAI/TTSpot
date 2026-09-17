-- Two kinds of club (official / underground), three club roles (president / vp /
-- secretary), club garage pings, activity leaderboard, official-club and partner
-- plans, partner state + shop photo, partner sponsorship DMs, event bookmarks.

-- ================================================================== clubs ---
alter table public.clubs
  add column if not exists tier text not null default 'underground' check (tier in ('official', 'underground')),
  add column if not exists official_until timestamptz,
  add column if not exists official_requested_at timestamptz,
  add column if not exists garage_name text check (garage_name is null or char_length(garage_name) <= 80),
  add column if not exists garage_lat float8,
  add column if not exists garage_lng float8;

-- The test club that already behaves like an official one.
update public.clubs set tier = 'official', official_until = now() + interval '30 days' where handle = 'ttspot_crew';

-- ---- roles: owner = President, vp, secretary. 'admin' rows become vp.
update public.club_members set role = 'vp' where role = 'admin';
update public.club_invites set role = 'vp' where role = 'admin';

create or replace function public.is_club_admin(p_club uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.club_members where club_id = p_club and user_id = p_user and role in ('owner', 'vp', 'secretary'))
      or exists (select 1 from public.clubs where id = p_club and owner_id = p_user);
$$;

create or replace function public.can_act_as_club(p_club uuid, p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.club_members m where m.club_id = p_club and m.user_id = p_user and m.role in ('owner', 'vp', 'secretary'))
      or exists (select 1 from public.clubs c where c.id = p_club and c.owner_id = p_user);
$$;

create or replace function public.set_club_role(p_club uuid, p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.clubs where id = p_club and owner_id = auth.uid()) then
    raise exception 'Only the president can change roles';
  end if;
  if p_role not in ('member', 'vp', 'secretary') then raise exception 'Unknown role'; end if;
  if p_user = auth.uid() then raise exception 'The president stays the president'; end if;
  update public.club_members set role = p_role where club_id = p_club and user_id = p_user;
end;
$$;

create or replace function public.invite_to_club(p_club uuid, p_user uuid, p_role text default 'member') returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_name text;
  v_role text := coalesce(p_role, 'member');
  v_owner uuid;
  v_tier text;
  v_count int;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if v_role not in ('member', 'vp', 'secretary') then raise exception 'Unknown role'; end if;
  select owner_id, name, tier into v_owner, v_name, v_tier from public.clubs where id = p_club;
  if v_name is null then raise exception 'Club not found'; end if;
  if v_role <> 'member' and v_owner <> auth.uid() then raise exception 'Only the president can appoint a VP or secretary'; end if;
  if v_role = 'member' and not public.is_club_admin(p_club) then raise exception 'Only the president, VP or secretary can invite'; end if;
  if p_user = auth.uid() then raise exception 'That is you'; end if;
  if v_role = 'member' and exists (select 1 from public.club_members where club_id = p_club and user_id = p_user) then
    raise exception 'Already a member';
  end if;
  if v_role <> 'member' and exists (select 1 from public.club_members where club_id = p_club and user_id = p_user and role = v_role) then
    raise exception 'Already holds that role';
  end if;
  if v_tier = 'underground' then
    select count(*) into v_count from public.club_members where club_id = p_club;
    if v_count >= 100 then raise exception 'Underground clubs hold up to 100 members. Go official for no limit.'; end if;
  end if;
  if exists (select 1 from public.club_invites where club_id = p_club and invitee_id = p_user and status = 'pending') then
    raise exception 'Already invited';
  end if;
  insert into public.club_invites (club_id, inviter_id, invitee_id, role) values (p_club, auth.uid(), p_user, v_role) returning id into v_id;
  perform public.notify(p_user, auth.uid(), 'club_invite', p_club => p_club,
    p_body => case when v_role = 'member' then '' else v_role || ':' end || v_name);
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
      set role = case when excluded.role in ('vp', 'secretary') then excluded.role else public.club_members.role end;
    perform public.notify(inv.inviter_id, auth.uid(), 'club_join', p_club => p_club,
      p_body => case when inv.role = 'member' then null else inv.role end);
  end if;
end;
$$;

-- Underground: 100 members max (join requests and direct joins go through here).
create or replace function public.club_member_cap() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_tier text; v_count int;
begin
  select tier into v_tier from public.clubs where id = new.club_id;
  if v_tier = 'underground' then
    select count(*) into v_count from public.club_members where club_id = new.club_id;
    if v_count >= 100 then raise exception 'Underground clubs hold up to 100 members. Go official for no limit.'; end if;
  end if;
  return new;
end;
$$;
drop trigger if exists club_member_cap on public.club_members;
create trigger club_member_cap before insert on public.club_members for each row execute function public.club_member_cap();

-- Events: officers only for club events; underground clubs plan up to 7 days ahead.
drop policy if exists "events: organizer can insert" on public.events;
create policy "events: organizer can insert" on public.events for insert to authenticated
  with check (
    organizer_id = auth.uid()
    and (club_id is null or public.is_club_member(club_id))
    and (vendor_id is null or exists (select 1 from public.vendors v where v.id = events.vendor_id and v.owner_id = auth.uid() and v.active))
    and (
      event_type = 'tt'::public.event_type
      or public.is_admin()
      or (club_id is not null and exists (select 1 from public.club_members m where m.club_id = events.club_id and m.user_id = auth.uid() and m.role in ('owner', 'vp', 'secretary')))
      or vendor_id is not null
    )
  );

create or replace function public.club_event_horizon() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_tier text;
begin
  if new.club_id is null then return new; end if;
  select tier into v_tier from public.clubs where id = new.club_id;
  if v_tier = 'underground' and new.starts_at > now() + interval '7 days' then
    raise exception 'Underground clubs can plan meets up to 7 days ahead. Go official to plan further out.';
  end if;
  return new;
end;
$$;
drop trigger if exists club_event_horizon on public.events;
create trigger club_event_horizon before insert on public.events for each row execute function public.club_event_horizon();

-- Notify: official club meets → every member; partner events → every member of TT Spot.
create or replace function public.notify_new_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_tier text; v_uid uuid; v_name text;
begin
  if new.status <> 'active' or coalesce(new.is_instant, false) then return new; end if;
  if new.club_id is not null then
    select tier, name into v_tier, v_name from public.clubs where id = new.club_id;
    if v_tier = 'official' then
      for v_uid in select user_id from public.club_members where club_id = new.club_id and user_id <> new.organizer_id loop
        perform public.notify(v_uid, new.organizer_id, 'club_event', p_event => new.id, p_club => new.club_id, p_body => v_name);
      end loop;
    end if;
  elsif new.vendor_id is not null then
    select name into v_name from public.vendors where id = new.vendor_id;
    for v_uid in select id from public.profiles where username is not null and id <> new.organizer_id loop
      perform public.notify(v_uid, new.organizer_id, 'partner_event', p_event => new.id, p_body => v_name);
    end loop;
  end if;
  return new;
end;
$$;
drop trigger if exists notify_new_event on public.events;
create trigger notify_new_event after insert on public.events for each row execute function public.notify_new_event();

-- Official club: the president earns 10 % on top of every member's meet check-in.
create or replace function public.on_checkin_points() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pts int := public.rule_points('meet_checkin'); v_club uuid; v_tier text; v_owner uuid;
begin
  perform public.award_points(new.user_id, v_pts, 'meet_checkin', 'event', new.event_id::text, null, 'meet_checkin:' || new.event_id || ':' || new.user_id);
  perform public.settle_referral(new.user_id);
  select e.club_id into v_club from public.events e where e.id = new.event_id;
  if v_club is not null then
    select tier, owner_id into v_tier, v_owner from public.clubs where id = v_club;
    if v_tier = 'official' and v_owner is not null and v_owner <> new.user_id and v_pts > 0 then
      perform public.award_points(v_owner, greatest(1, round(v_pts * 0.10)::int), 'club_president_bonus', 'event', new.event_id::text,
        'A member checked in at your club''s meet', 'club_bonus:' || new.event_id || ':' || new.user_id);
    end if;
  end if;
  return new;
end;
$$;

-- ---- garage (underground): set by an officer; members get pinged when a clubmate arrives.
create or replace function public.set_club_garage(p_club uuid, p_name text, p_lat float8, p_lng float8) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_club_admin(p_club) then raise exception 'Only the president, VP or secretary can set the garage'; end if;
  update public.clubs set garage_name = nullif(trim(p_name), ''), garage_lat = p_lat, garage_lng = p_lng where id = p_club;
end;
$$;

create table if not exists public.club_garage_visits (
  club_id uuid not null references public.clubs (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  day     date not null default (now() at time zone 'Asia/Kuala_Lumpur')::date,
  primary key (club_id, user_id, day)
);
alter table public.club_garage_visits enable row level security;

create or replace function public.on_location_garage() returns trigger
language plpgsql security definer set search_path = public as $$
declare c record; v_uid uuid; v_name text;
begin
  if new.ghost then return new; end if;
  for c in
    select cl.id, cl.name, cl.garage_name
    from public.club_members m join public.clubs cl on cl.id = m.club_id
    where m.user_id = new.user_id and m.share_location and cl.garage_lat is not null
      and abs(cl.garage_lat - new.lat) < 0.005 and abs(cl.garage_lng - new.lng) < 0.005
      and public.metres_between(new.lat, new.lng, cl.garage_lat, cl.garage_lng) <= 200
  loop
    begin
      insert into public.club_garage_visits (club_id, user_id) values (c.id, new.user_id);
    exception when unique_violation then continue; end;
    select coalesce(display_name, username) into v_name from public.profiles where id = new.user_id;
    for v_uid in select user_id from public.club_members where club_id = c.id and user_id <> new.user_id loop
      perform public.notify(v_uid, new.user_id, 'garage', p_club => c.id, p_body => coalesce(c.garage_name, 'the garage'));
    end loop;
  end loop;
  return new;
end;
$$;
drop trigger if exists on_location_garage on public.user_locations;
create trigger on_location_garage after insert or update of lat, lng on public.user_locations for each row execute function public.on_location_garage();

-- ---- leaderboard: who shows up (90 days).
create or replace function public.club_leaderboard(p_club uuid, p_limit int default 10)
returns table (user_id uuid, username text, display_name text, avatar_url text, score int, checkins int, joins int, posts int, moments int)
language sql stable security definer set search_path = public as $$
  with m as (select user_id from public.club_members where club_id = p_club),
  ev as (select id from public.events where club_id = p_club and created_at > now() - interval '90 days'),
  s as (
    select m.user_id,
      (select count(*) from public.checkins c where c.user_id = m.user_id and c.event_id in (select id from ev))::int as checkins,
      (select count(*) from public.event_attendees a where a.user_id = m.user_id and a.event_id in (select id from ev))::int as joins,
      (select count(*) from public.posts p where p.author_id = m.user_id and p.club_id = p_club and p.created_at > now() - interval '90 days')::int as posts,
      (select count(*) from public.stories st where st.author_id = m.user_id and st.event_id in (select id from ev))::int as moments
    from m
  )
  select s.user_id, p.username::text, p.display_name, p.avatar_url,
         s.checkins * 3 + s.joins + s.posts * 2 + s.moments as score, s.checkins, s.joins, s.posts, s.moments
  from s join public.profiles p on p.id = s.user_id
  order by score desc, p.username
  limit p_limit;
$$;

-- ---- official tier: request → admin approves for 30 days (payment is settled outside the app for now).
create or replace function public.request_official_club(p_club uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text; v_admin uuid;
begin
  if not exists (select 1 from public.clubs where id = p_club and owner_id = auth.uid()) then raise exception 'Only the president can do this'; end if;
  update public.clubs set official_requested_at = now() where id = p_club and tier = 'underground' returning name into v_name;
  if v_name is null then raise exception 'This club is already official'; end if;
  for v_admin in select id from public.profiles where is_admin loop
    perform public.notify(v_admin, auth.uid(), 'club_official', p_club => p_club, p_body => 'requested:' || v_name);
  end loop;
end;
$$;

create or replace function public.admin_set_club_tier(p_club uuid, p_tier text, p_days int default 30) returns void
language plpgsql security definer set search_path = public as $$
declare v_owner uuid; v_name text;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_tier not in ('official', 'underground') then raise exception 'Unknown tier'; end if;
  update public.clubs
     set tier = p_tier,
         official_until = case when p_tier = 'official' then greatest(coalesce(official_until, now()), now()) + make_interval(days => p_days) else null end,
         official_requested_at = null
   where id = p_club returning owner_id, name into v_owner, v_name;
  perform public.notify(v_owner, null, 'club_official', p_club => p_club,
    p_body => case when p_tier = 'official' then 'approved:' else 'ended:' end || v_name);
end;
$$;

create or replace function public.admin_official_queue()
returns table (id uuid, name text, handle text, avatar_url text, owner_id uuid, owner_username text, members int, requested_at timestamptz, tier text, official_until timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.handle::text, c.avatar_url, c.owner_id, p.username::text,
         (select count(*)::int from public.club_members m where m.club_id = c.id), c.official_requested_at, c.tier, c.official_until
  from public.clubs c join public.profiles p on p.id = c.owner_id
  where public.is_admin() and (c.official_requested_at is not null or c.tier = 'official')
  order by c.official_requested_at desc nulls last, c.name;
$$;

-- Expire official tiers nightly.
create or replace function public.expire_official_clubs() returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in update public.clubs set tier = 'underground', official_until = null
           where tier = 'official' and official_until is not null and official_until < now()
           returning id, owner_id, name loop
    perform public.notify(r.owner_id, null, 'club_official', p_club => r.id, p_body => 'expired:' || r.name);
  end loop;
end;
$$;
select cron.schedule('ttspot-expire-official-clubs', '10 0 * * *', $$select public.expire_official_clubs()$$);

-- ================================================================ partners ---
alter table public.partner_applications
  add column if not exists state text,
  add column if not exists shop_photo_url text;
alter table public.vendors
  add column if not exists state text,
  add column if not exists plan_until timestamptz;

drop function if exists public.apply_partner(text, text, text, uuid, text, text, text, text, text, float8, float8);
create function public.apply_partner(
  p_name text, p_type text, p_address text default null, p_place uuid default null, p_phone text default null,
  p_description text default null, p_logo_url text default null, p_ssm text default null, p_kind text default 'vendor',
  p_lat float8 default null, p_lng float8 default null, p_state text default null, p_shop_photo_url text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_admin uuid;
  v_kind text := coalesce(p_kind, 'vendor');
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if v_kind not in ('vendor', 'club') then raise exception 'Unknown application kind'; end if;
  if v_kind = 'vendor' then
    if exists (select 1 from public.vendors where owner_id = auth.uid()) then raise exception 'You are already a partner'; end if;
    if coalesce(p_state, '') not in ('Johor', 'Penang', 'Kuala Lumpur') then raise exception 'Partners need a shop in Johor, Penang or Kuala Lumpur for now'; end if;
    if nullif(trim(coalesce(p_ssm, '')), '') is null then raise exception 'Enter your SSM registration number'; end if;
    if p_shop_photo_url is null then raise exception 'Add a photo of your shop'; end if;
  end if;
  if v_kind = 'club' and exists (select 1 from public.profiles where id = auth.uid() and club_owner) then
    raise exception 'You are already a club owner';
  end if;
  if exists (select 1 from public.partner_applications where user_id = auth.uid() and kind = v_kind and status = 'pending') then
    raise exception 'You already have an application waiting for review';
  end if;
  insert into public.partner_applications (user_id, kind, business_name, business_type, address, place_id, phone, description, logo_url, ssm_no, lat, lng, state, shop_photo_url)
  values (auth.uid(), v_kind, trim(p_name), coalesce(p_type, case when v_kind = 'club' then 'club' else 'other' end),
          nullif(trim(p_address), ''), p_place, nullif(trim(p_phone), ''), nullif(trim(p_description), ''), p_logo_url, nullif(trim(p_ssm), ''), p_lat, p_lng, p_state, p_shop_photo_url)
  returning id into v_id;
  for v_admin in select id from public.profiles where is_admin loop
    perform public.notify(v_admin, auth.uid(), 'partner', p_body => 'applied:' || trim(p_name));
  end loop;
  return v_id;
end;
$$;

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
    if a.kind = 'club' then
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
      p_body => case when a.kind = 'club' then 'rejected-club:' else 'rejected:' end || coalesce(p_note, 'no reason given'));
  end if;
end;
$$;

create or replace function public.admin_set_vendor_plan(p_vendor uuid, p_days int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  update public.vendors set plan_until = greatest(coalesce(plan_until, now()), now()) + make_interval(days => p_days) where id = p_vendor;
end;
$$;

create or replace function public.admin_partners_list()
returns table (id uuid, name text, type text, logo_url text, state text, plan_until timestamptz, owner_username text, live_vouchers int, redemptions_30d int)
language sql stable security definer set search_path = public as $$
  select v.id, v.name, v.type, v.logo_url, v.state, v.plan_until, p.username::text,
         (select count(*)::int from public.vouchers vo where vo.vendor_id = v.id and vo.active and (vo.ends_at is null or vo.ends_at > now())),
         (select count(*)::int from public.voucher_redemptions r where r.vendor_id = v.id and r.created_at > now() - interval '30 days')
  from public.vendors v join public.profiles p on p.id = v.owner_id
  where public.is_admin() and v.active
  order by v.name;
$$;

-- my_vendor(): + state, plan_until
drop function if exists public.my_vendor();
create function public.my_vendor()
returns table (id uuid, name text, type text, address text, place_id uuid, phone text, description text, logo_url text, active boolean,
               commission_rate numeric, created_at timestamptz, live_vouchers int, redemptions_30d int, bill_30d numeric, commission_30d numeric,
               lat float8, lng float8, hours text, photo_urls text[], hours_json jsonb, views_30d int, checkins_30d int, claims_30d int,
               state text, plan_until timestamptz)
language sql stable security definer set search_path = public as $$
  select vd.id, vd.name, vd.type, vd.address, vd.place_id, vd.phone, vd.description, vd.logo_url, vd.active,
         coalesce(vd.commission_rate, public.setting_num('commission_rate', 0.01)), vd.created_at,
         (select count(*)::int from public.vouchers v where v.vendor_id = vd.id and v.active and (v.ends_at is null or v.ends_at > now())),
         (select count(*)::int from public.voucher_redemptions r where r.vendor_id = vd.id and r.created_at > now() - interval '30 days'),
         (select coalesce(sum(r.bill_amount), 0) from public.voucher_redemptions r where r.vendor_id = vd.id and r.created_at > now() - interval '30 days'),
         (select coalesce(sum(r.commission_amount), 0) from public.voucher_redemptions r where r.vendor_id = vd.id and r.created_at > now() - interval '30 days'),
         vd.lat, vd.lng, vd.hours, vd.photo_urls, vd.hours_json,
         (select count(*)::int from public.vendor_page_views pv where pv.vendor_id = vd.id and pv.day > (now() at time zone 'Asia/Kuala_Lumpur')::date - 30),
         (select count(*)::int from public.place_checkins pc where pc.place_id = vd.place_id and pc.checked_in_at > now() - interval '30 days'),
         (select count(*)::int from public.voucher_claims c join public.vouchers v on v.id = c.voucher_id where v.vendor_id = vd.id and c.claimed_at > now() - interval '30 days'),
         vd.state, vd.plan_until
  from public.vendors vd where vd.owner_id = auth.uid();
$$;

-- Partners see every club and what its members drive.
create or replace function public.vendor_club_insights()
returns table (id uuid, name text, handle text, avatar_url text, tier text, home_state text, members int, top_makes json)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.handle::text, c.avatar_url, c.tier, c.home_state,
         (select count(*)::int from public.club_members m where m.club_id = c.id),
         (select coalesce(json_agg(json_build_object('make', make, 'n', n)), '[]'::json) from (
            select cr.make, count(*) n from public.club_members m join public.cars cr on cr.owner_id = m.user_id
            where m.club_id = c.id group by cr.make order by n desc limit 3) t)
  from public.clubs c
  where public.my_vendor_id() is not null
  order by 7 desc, c.name;
$$;

-- A partner reaching out to an organiser (sponsorship, ads). Same thread as when the member messages the shop.
create or replace function public.get_or_create_vendor_dm_with(p_user uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v uuid := public.my_vendor_id(); conv uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if v is null then raise exception 'You are not an active partner'; end if;
  if p_user = me then raise exception 'That is you'; end if;
  select c.id into conv from public.conversations c
  where c.kind = 'dm' and c.vendor_id = v
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = p_user)
  limit 1;
  if conv is null then
    insert into public.conversations (kind, vendor_id) values ('dm', v) returning id into conv;
    insert into public.conversation_members (conversation_id, user_id) values (conv, p_user), (conv, me) on conflict do nothing;
  end if;
  return conv;
end; $$;

-- ================================================================ bookmarks ---
create table if not exists public.event_bookmarks (
  user_id  uuid not null references public.profiles (id) on delete cascade,
  event_id uuid not null references public.events (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, event_id)
);
alter table public.event_bookmarks enable row level security;
drop policy if exists "bookmarks: own" on public.event_bookmarks;
create policy "bookmarks: own" on public.event_bookmarks for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.toggle_event_bookmark(p_event uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if exists (select 1 from public.event_bookmarks where user_id = auth.uid() and event_id = p_event) then
    delete from public.event_bookmarks where user_id = auth.uid() and event_id = p_event;
    return false;
  end if;
  insert into public.event_bookmarks (user_id, event_id) values (auth.uid(), p_event);
  return true;
end;
$$;

-- Reminders now cover bookmarks too, and run hourly so a same-day meet is not missed.
create or replace function public.send_event_reminders() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, type, event_id)
  select distinct x.user_id, 'event_reminder', e.id
  from (select user_id, event_id from public.event_attendees union select user_id, event_id from public.event_bookmarks) x
  join public.events e on e.id = x.event_id
  where e.status = 'active'
    and e.starts_at between now() and now() + interval '24 hours'
    and not exists (select 1 from public.notifications n where n.user_id = x.user_id and n.event_id = e.id and n.type = 'event_reminder');
end;
$$;
select cron.unschedule('ttspot-event-reminders');
select cron.schedule('ttspot-event-reminders', '0 * * * *', $$select public.send_event_reminders()$$);

-- ================================================================ views + stats ---
drop view if exists public.events_with_counts;
create view public.events_with_counts
with (security_invoker = true) as
select e.id, e.organizer_id, e.title, e.description, e.event_type, e.cover_url, e.starts_at, e.venue_name, e.lat, e.lng, e.max_attendees,
       e.status, e.created_at, e.place_id, e.club_id, e.is_instant, e.ends_at, e.qr_secret, e.visibility, e.address, e.vendor_id,
       (select count(*) from public.event_attendees a where a.event_id = e.id)::int as attendee_count,
       (select count(*) from public.checkins c where c.event_id = e.id)::int as checkin_count,
       (select v.name from public.vendors v where v.id = e.vendor_id) as vendor_name,
       (select v.logo_url from public.vendors v where v.id = e.vendor_id) as vendor_logo_url,
       (select c.name from public.clubs c where c.id = e.club_id) as club_name,
       (select c.tier from public.clubs c where c.id = e.club_id) as club_tier
from public.events e;
grant select on public.events_with_counts to authenticated;

-- admin_stats: + pending official requests
create or replace function public.admin_stats() returns json
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days date[] := array(select (v_today - i) from generate_series(6, 0, -1) i);
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return json_build_object(
    'users', (select count(*) from public.profiles where username is not null),
    'users_7d', (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'users_today', (select count(*) from public.profiles where (created_at at time zone 'Asia/Kuala_Lumpur')::date = v_today),
    'on_map_now', (select count(*) from public.user_locations where updated_at > now() - interval '20 minutes' and not ghost),
    'active_24h', (select count(distinct user_id) from public.user_locations where updated_at > now() - interval '24 hours'),
    'meets_live', (select count(*) from public.events where status = 'active' and now() between starts_at - interval '1 hour' and coalesce(ends_at, starts_at + interval '6 hours')),
    'meets_upcoming', (select count(*) from public.events where status = 'active' and starts_at > now()),
    'meets_7d', (select count(*) from public.events where created_at > now() - interval '7 days'),
    'tt_today', (select count(*) from public.events where is_instant and (created_at at time zone 'Asia/Kuala_Lumpur')::date = v_today),
    'checkins_today', (select count(*) from public.checkins where (checked_in_at at time zone 'Asia/Kuala_Lumpur')::date = v_today)
                    + (select count(*) from public.place_checkins where (checked_in_at at time zone 'Asia/Kuala_Lumpur')::date = v_today),
    'checkins_7d', (select count(*) from public.checkins where checked_in_at > now() - interval '7 days')
                 + (select count(*) from public.place_checkins where checked_in_at > now() - interval '7 days'),
    'posts_7d', (select count(*) from public.posts where created_at > now() - interval '7 days'),
    'messages_7d', (select count(*) from public.messages where created_at > now() - interval '7 days'),
    'signups_by_day', (select json_agg(c order by d) from (select d, (select count(*) from public.profiles p where (p.created_at at time zone 'Asia/Kuala_Lumpur')::date = d) c from unnest(v_days) d) t),
    'checkins_by_day', (select json_agg(c order by d) from (select d,
        (select count(*) from public.checkins x where (x.checked_in_at at time zone 'Asia/Kuala_Lumpur')::date = d)
      + (select count(*) from public.place_checkins y where (y.checked_in_at at time zone 'Asia/Kuala_Lumpur')::date = d) c from unnest(v_days) d) t),
    'posts_by_day', (select json_agg(c order by d) from (select d, (select count(*) from public.posts p where (p.created_at at time zone 'Asia/Kuala_Lumpur')::date = d) c from unnest(v_days) d) t),
    'active_by_day', (select json_agg(c order by d) from (select d, (select count(distinct user_id) from public.user_locations l where (l.updated_at at time zone 'Asia/Kuala_Lumpur')::date = d) c from unnest(v_days) d) t),
    'pending_verifications', (select count(*) from public.spot_verifications where status in ('pending', 'review')),
    'pending_partners', (select count(*) from public.partner_applications where status = 'pending'),
    'pending_official', (select count(*) from public.clubs where official_requested_at is not null and tier = 'underground'),
    'pending_suggestions', (select count(*) from public.place_suggestions where status = 'pending'),
    'open_reports', (select count(*) from public.reports where resolved_at is null),
    'vendors', (select count(*) from public.vendors where active),
    'clubs', (select count(*) from public.clubs),
    'clubs_official', (select count(*) from public.clubs where tier = 'official'),
    'club_members', (select count(*) from public.club_members),
    'vouchers_live', (select count(*) from public.vouchers v where v.active and v.starts_at <= now() and (v.ends_at is null or v.ends_at > now())),
    'claims_30d', (select count(*) from public.voucher_claims where claimed_at > now() - interval '30 days'),
    'redemptions_30d', (select count(*) from public.voucher_redemptions where created_at > now() - interval '30 days'),
    'bills_30d', (select coalesce(sum(bill_amount), 0) from public.voucher_redemptions where created_at > now() - interval '30 days'),
    'commission_30d', (select coalesce(sum(commission_amount), 0) from public.voucher_redemptions where created_at > now() - interval '30 days'),
    'places', (select count(*) from public.places),
    'top_places', (select coalesce(json_agg(json_build_object('id', id, 'name', name, 'count', c)), '[]'::json) from (
        select pl.id, pl.name, count(*) c from public.place_checkins pc join public.places pl on pl.id = pc.place_id
        where pc.checked_in_at > now() - interval '7 days' group by pl.id, pl.name order by c desc limit 3) t)
  );
end;
$$;
