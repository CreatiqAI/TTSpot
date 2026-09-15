-- Partner pages and the shop on the map.
--   * vendors get lat/lng (from the Google-picked address), opening hours and
--     up to 6 photos; partner_applications carry lat/lng too.
--   * every active partner with a location owns one place (places.vendor_id):
--     it appears on the Spots layer with the logo, members can check in there.
--   * vendors_public: what any member may read about a partner.

alter table public.vendors
  add column if not exists lat float8,
  add column if not exists lng float8,
  add column if not exists hours text check (hours is null or char_length(hours) <= 200),
  add column if not exists photo_urls text[] not null default '{}' check (cardinality(photo_urls) <= 6);
alter table public.partner_applications
  add column if not exists lat float8,
  add column if not exists lng float8;
alter table public.places add column if not exists vendor_id uuid references public.vendors (id) on delete set null;
create unique index if not exists places_vendor_key on public.places (vendor_id) where vendor_id is not null;

-- ------------------------------------------------------------- the place ---
-- Keep the partner's place in step with the partner: name, kind (= business
-- type), position, logo as cover, description.
create or replace function public.sync_vendor_place(p_vendor uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v public.vendors; pid uuid;
begin
  select * into v from public.vendors where id = p_vendor;
  if v.id is null or v.lat is null or v.lng is null or not v.active then return; end if;
  select id into pid from public.places where vendor_id = v.id;
  if pid is null then
    insert into public.places (name, kind, lat, lng, created_by, cover_url, description, vendor_id)
    values (v.name, v.type, v.lat, v.lng, v.owner_id, v.logo_url, v.description, v.id)
    returning id into pid;
  else
    update public.places
       set name = v.name, kind = v.type, lat = v.lat, lng = v.lng, cover_url = coalesce(v.logo_url, cover_url), description = v.description
     where id = pid;
  end if;
  update public.vendors set place_id = pid where id = v.id and place_id is distinct from pid;
end;
$$;

-- ------------------------------------------------------------- applying ---
drop function if exists public.apply_partner(text, text, text, uuid, text, text, text, text, text);
create or replace function public.apply_partner(
  p_name text, p_type text, p_address text default null, p_place uuid default null, p_phone text default null,
  p_description text default null, p_logo_url text default null, p_ssm text default null, p_kind text default 'vendor',
  p_lat float8 default null, p_lng float8 default null
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
  insert into public.partner_applications (user_id, kind, business_name, business_type, address, place_id, phone, description, logo_url, ssm_no, lat, lng)
  values (auth.uid(), v_kind, trim(p_name), coalesce(p_type, case when v_kind = 'club' then 'club' else 'other' end),
          nullif(trim(p_address), ''), p_place, nullif(trim(p_phone), ''), nullif(trim(p_description), ''), p_logo_url, nullif(trim(p_ssm), ''), p_lat, p_lng)
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
      insert into public.vendors (owner_id, name, type, address, place_id, phone, description, logo_url, application_id, lat, lng)
      values (a.user_id, a.business_name, a.business_type, a.address, a.place_id, a.phone, a.description, a.logo_url, a.id, a.lat, a.lng)
      on conflict (owner_id) do update
        set name = excluded.name, type = excluded.type, address = excluded.address,
            phone = excluded.phone, description = excluded.description, logo_url = excluded.logo_url, active = true,
            application_id = excluded.application_id, lat = coalesce(excluded.lat, vendors.lat), lng = coalesce(excluded.lng, vendors.lng)
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

-- -------------------------------------------------------------- editing ---
drop function if exists public.update_my_vendor(text, text, text, text);
create or replace function public.update_my_vendor(
  p_address text default null, p_phone text default null, p_description text default null, p_logo_url text default null,
  p_lat float8 default null, p_lng float8 default null, p_hours text default null, p_photo_urls text[] default null
) returns void
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  update public.vendors
     set address = coalesce(nullif(trim(p_address), ''), address),
         phone = coalesce(nullif(trim(p_phone), ''), phone),
         description = coalesce(nullif(trim(p_description), ''), description),
         logo_url = coalesce(p_logo_url, logo_url),
         lat = coalesce(p_lat, lat), lng = coalesce(p_lng, lng),
         hours = coalesce(nullif(trim(p_hours), ''), hours),
         photo_urls = coalesce(p_photo_urls, photo_urls)
   where owner_id = auth.uid()
   returning id into v_id;
  if v_id is null then raise exception 'You are not a partner'; end if;
  perform public.sync_vendor_place(v_id);
end;
$$;

-- --------------------------------------------------------------- public ---
create or replace view public.vendors_public
with (security_invoker = true) as
select v.id, v.owner_id, v.name, v.type, v.address, v.lat, v.lng, v.hours, v.photo_urls, v.logo_url, v.description, v.phone, v.place_id, v.created_at,
       (select count(*) from public.vouchers vo where vo.vendor_id = v.id and vo.active and (vo.ends_at is null or vo.ends_at > now()))::int as live_vouchers,
       (select count(*) from public.events e where e.vendor_id = v.id and e.status = 'active' and e.starts_at >= now() - interval '6 hours')::int as upcoming_events
from public.vendors v
where v.active;
grant select on public.vendors_public to authenticated;

-- Spots layer: partner places always count as spots and carry the logo.
drop view if exists public.places_with_counts;
create view public.places_with_counts
with (security_invoker = true) as
with act as (
  select p.id,
         (select count(*) from public.place_checkins pc where pc.place_id = p.id and pc.checked_in_at > now() - interval '90 days')::int as checkins_90d,
         (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.event_type <> 'tt'
                 and e.starts_at between now() - interval '90 days' and now())::int as meets_90d
  from public.places p
)
select
  p.*,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now())::int  as past_meets,
  (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at >= now())::int as upcoming_meets,
  (select max(e.starts_at) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now()) as last_meet_at,
  (select count(*) from public.checkins c join public.events e on e.id = c.event_id where e.place_id = p.id)::int      as checkins_total,
  (select count(*) from public.place_checkins pc where pc.place_id = p.id)::int                                          as spot_checkins,
  (select count(*) from public.posts po where po.place_id = p.id)::int                                                  as post_count,
  (select count(*) from public.stories s where s.place_id = p.id)::int                                                  as moment_count,
  a.checkins_90d,
  a.meets_90d,
  (
    (case when p.recommended then 100 else 0 end)
    + 3 * (select count(*) from public.place_checkins pc where pc.place_id = p.id)
    + 5 * (select count(*) from public.events e where e.place_id = p.id and e.status = 'active' and e.starts_at < now())
    + 2 * (select count(*) from public.posts po where po.place_id = p.id)
    + 1 * (select count(*) from public.stories s where s.place_id = p.id)
  )::int as score,
  (
    p.recommended
    or p.vendor_id is not null
    or p.cover_url is not null
    or exists (select 1 from public.place_checkins pc where pc.place_id = p.id)
    or exists (select 1 from public.posts po where po.place_id = p.id)
    or exists (select 1 from public.stories s where s.place_id = p.id)
    or exists (select 1 from public.place_suggestions sg where sg.place_id = p.id and sg.status = 'approved')
  ) as is_spot,
  (case p.top_override
     when 'top' then true
     when 'never' then false
     else (p.recommended or a.checkins_90d >= 20 or a.meets_90d >= 3)
   end) as is_top,
  (select vd.logo_url from public.vendors vd where vd.id = p.vendor_id) as vendor_logo,
  (select vd.name from public.vendors vd where vd.id = p.vendor_id) as vendor_name
from public.places p
join act a on a.id = p.id;

-- Existing partners with an address but no coordinates get none until they
-- re-pick the address in Edit shop; partners that already have coordinates
-- get their place now.
select public.sync_vendor_place(id) from public.vendors where active and lat is not null;
