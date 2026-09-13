-- =============================================================================
-- Phase 3: business partners (vendors), vouchers, redemptions, commission.
--
-- Vendors are ordinary members who applied in-app and were approved by an
-- admin. They publish vouchers; members claim them (optionally for points) and
-- get a QR; the vendor scans the QR at the counter, types the bill, and the
-- platform books a commission = bill × commission_rate (default 1 %). All
-- writes go through security-definer RPCs; RLS only grants reads.
-- =============================================================================

-- ------------------------------------------------------------ settings ---
create table public.platform_settings (
  key         text primary key,
  value       jsonb not null,
  description text,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null
);
alter table public.platform_settings enable row level security;
create policy "settings: read" on public.platform_settings for select to authenticated using (true);

insert into public.platform_settings (key, value, description) values
  ('commission_rate',      '0.01', 'Share of the bill (typed by the vendor at redemption) that goes to the platform. 0.01 = 1 %.'),
  ('voucher_claim_days',   '30',   'Days a claimed voucher stays valid if the voucher has no end date.'),
  ('max_active_vouchers',  '10',   'Live vouchers a vendor may have at once.');

create or replace function public.setting_num(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from public.platform_settings where key = p_key), p_default);
$$;

create or replace function public.admin_set_setting(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  insert into public.platform_settings (key, value, updated_at, updated_by) values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = auth.uid();
end;
$$;

-- ------------------------------------------------- partner applications ---
create table public.partner_applications (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles (id) on delete cascade,
  business_name  text not null check (char_length(business_name) between 2 and 80),
  business_type  text not null default 'other',  -- cafe | restaurant | workshop | detailing | accessories | tyres | petrol | other
  address        text,
  place_id       uuid references public.places (id) on delete set null,
  phone          text,
  ssm_no         text,                            -- company registration number, optional
  description    text,
  logo_url       text,
  status         text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reason         text,
  created_at     timestamptz not null default now(),
  decided_at     timestamptz,
  decided_by     uuid references public.profiles (id) on delete set null
);
create index partner_applications_user_idx on public.partner_applications (user_id, created_at desc);
create unique index partner_applications_one_pending on public.partner_applications (user_id) where status = 'pending';
alter table public.partner_applications enable row level security;
create policy "partner apps: own read" on public.partner_applications for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------- vendors ---
create table public.vendors (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null unique references public.profiles (id) on delete cascade,
  name            text not null,
  type            text not null default 'other',
  address         text,
  place_id        uuid references public.places (id) on delete set null,
  phone           text,
  description     text,
  logo_url        text,
  active          boolean not null default true,
  commission_rate numeric(6,4),                  -- null = platform default
  application_id  uuid references public.partner_applications (id) on delete set null,
  created_at      timestamptz not null default now()
);
alter table public.vendors enable row level security;
create policy "vendors: read" on public.vendors for select to authenticated using (true);

create or replace function public.my_vendor_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.vendors where owner_id = auth.uid() and active;
$$;

create or replace function public.apply_partner(
  p_name text, p_type text, p_address text default null, p_place uuid default null, p_phone text default null,
  p_description text default null, p_logo_url text default null, p_ssm text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_admin uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if exists (select 1 from public.vendors where owner_id = auth.uid()) then
    raise exception 'You are already a partner';
  end if;
  if exists (select 1 from public.partner_applications where user_id = auth.uid() and status = 'pending') then
    raise exception 'You already have an application waiting for review';
  end if;
  insert into public.partner_applications (user_id, business_name, business_type, address, place_id, phone, description, logo_url, ssm_no)
  values (auth.uid(), trim(p_name), coalesce(p_type, 'other'), nullif(trim(p_address), ''), p_place, nullif(trim(p_phone), ''),
          nullif(trim(p_description), ''), p_logo_url, nullif(trim(p_ssm), ''))
  returning id into v_id;
  for v_admin in select id from public.profiles where is_admin loop
    perform public.notify(v_admin, auth.uid(), 'partner', p_body => 'applied:' || trim(p_name));
  end loop;
  return v_id;
end;
$$;

create or replace function public.my_partner_application()
returns table (id uuid, business_name text, business_type text, address text, place_id uuid, phone text, ssm_no text, description text,
               logo_url text, status text, reason text, created_at timestamptz, decided_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, a.business_name, a.business_type, a.address, a.place_id, a.phone, a.ssm_no, a.description, a.logo_url,
         a.status, a.reason, a.created_at, a.decided_at
  from public.partner_applications a where a.user_id = auth.uid()
  order by a.created_at desc limit 1;
$$;

create or replace function public.admin_partner_queue(p_limit int default 100)
returns table (id uuid, user_id uuid, username text, avatar_url text, business_name text, business_type text, address text, place_id uuid,
               place_name text, phone text, ssm_no text, description text, logo_url text, status text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select a.id, a.user_id, pr.username::text, pr.avatar_url, a.business_name, a.business_type, a.address, a.place_id, p.name,
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
    insert into public.vendors (owner_id, name, type, address, place_id, phone, description, logo_url, application_id)
    values (a.user_id, a.business_name, a.business_type, a.address, a.place_id, a.phone, a.description, a.logo_url, a.id)
    on conflict (owner_id) do update
      set name = excluded.name, type = excluded.type, address = excluded.address, place_id = excluded.place_id,
          phone = excluded.phone, description = excluded.description, logo_url = excluded.logo_url, active = true,
          application_id = excluded.application_id;
    perform public.notify(a.user_id, null, 'partner', p_body => 'approved:' || a.business_name);
  else
    perform public.notify(a.user_id, null, 'partner', p_body => 'rejected:' || coalesce(p_note, 'no reason given'));
  end if;
end;
$$;

-- Vendor edits its own public details (name/type stay from the application).
create or replace function public.update_my_vendor(p_address text, p_phone text, p_description text, p_logo_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.vendors
     set address = nullif(trim(p_address), ''), phone = nullif(trim(p_phone), ''),
         description = nullif(trim(p_description), ''), logo_url = coalesce(p_logo_url, logo_url)
   where owner_id = auth.uid();
  if not found then raise exception 'You are not a partner'; end if;
end;
$$;

-- --------------------------------------------------------------- vouchers ---
create table public.vouchers (
  id              uuid primary key default gen_random_uuid(),
  vendor_id       uuid not null references public.vendors (id) on delete cascade,
  title           text not null check (char_length(title) between 2 and 80),
  description     text,
  terms           text,
  discount_kind   text not null default 'percent' check (discount_kind in ('percent', 'amount', 'freebie')),
  discount_value  numeric(10,2) not null default 0 check (discount_value >= 0),   -- % for percent, RM for amount, unused for freebie
  min_spend       numeric(10,2) not null default 0 check (min_spend >= 0),
  points_cost     int not null default 0 check (points_cost >= 0),               -- 0 = free to claim
  max_claims      int check (max_claims is null or max_claims > 0),              -- null = unlimited
  claims_count    int not null default 0,
  per_user_limit  int not null default 1 check (per_user_limit between 1 and 100),
  starts_at       timestamptz not null default now(),
  ends_at         timestamptz,
  active          boolean not null default true,
  created_at      timestamptz not null default now()
);
create index vouchers_vendor_idx on public.vouchers (vendor_id, created_at desc);
create index vouchers_live_idx on public.vouchers (active, starts_at, ends_at);
alter table public.vouchers enable row level security;
create policy "vouchers: read" on public.vouchers for select to authenticated using (true);

create or replace function public.save_voucher(
  p_id uuid, p_title text, p_description text, p_terms text, p_kind text, p_value numeric, p_min_spend numeric,
  p_points_cost int, p_max_claims int, p_per_user int, p_starts timestamptz, p_ends timestamptz, p_active boolean
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_vendor uuid := public.my_vendor_id();
  v_id uuid;
  v_live int;
begin
  if v_vendor is null then raise exception 'You are not an active partner'; end if;
  if p_kind = 'percent' and (p_value <= 0 or p_value > 100) then raise exception 'Percent must be 1-100'; end if;
  if p_kind = 'amount' and p_value <= 0 then raise exception 'Amount must be above 0'; end if;
  if p_ends is not null and p_ends <= coalesce(p_starts, now()) then raise exception 'End must be after start'; end if;
  if p_id is null then
    select count(*) into v_live from public.vouchers where vendor_id = v_vendor and active and (ends_at is null or ends_at > now());
    if p_active and v_live >= public.setting_num('max_active_vouchers', 10) then
      raise exception 'You already have % live vouchers', v_live;
    end if;
    insert into public.vouchers (vendor_id, title, description, terms, discount_kind, discount_value, min_spend, points_cost,
                                 max_claims, per_user_limit, starts_at, ends_at, active)
    values (v_vendor, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_terms), ''), p_kind, coalesce(p_value, 0),
            coalesce(p_min_spend, 0), coalesce(p_points_cost, 0), p_max_claims, coalesce(p_per_user, 1),
            coalesce(p_starts, now()), p_ends, coalesce(p_active, true))
    returning id into v_id;
    return v_id;
  end if;
  update public.vouchers
     set title = trim(p_title), description = nullif(trim(p_description), ''), terms = nullif(trim(p_terms), ''),
         discount_kind = p_kind, discount_value = coalesce(p_value, 0), min_spend = coalesce(p_min_spend, 0),
         points_cost = coalesce(p_points_cost, 0), max_claims = p_max_claims, per_user_limit = coalesce(p_per_user, 1),
         starts_at = coalesce(p_starts, starts_at), ends_at = p_ends, active = coalesce(p_active, active)
   where id = p_id and vendor_id = v_vendor;
  if not found then raise exception 'Voucher not found'; end if;
  return p_id;
end;
$$;

create or replace function public.set_voucher_active(p_id uuid, p_active boolean) returns void
language sql security definer set search_path = public as $$
  update public.vouchers set active = p_active where id = p_id and vendor_id = public.my_vendor_id();
$$;

-- ----------------------------------------------------------------- claims ---
create table public.voucher_claims (
  id            uuid primary key default gen_random_uuid(),
  voucher_id    uuid not null references public.vouchers (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  code          text not null default encode(extensions.gen_random_bytes(12), 'hex'),
  status        text not null default 'active' check (status in ('active', 'redeemed', 'expired', 'cancelled')),
  points_spent  int not null default 0,
  claimed_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  redeemed_at   timestamptz
);
create index voucher_claims_user_idx on public.voucher_claims (user_id, claimed_at desc);
create index voucher_claims_voucher_idx on public.voucher_claims (voucher_id);
alter table public.voucher_claims enable row level security;
create policy "claims: own read" on public.voucher_claims for select to authenticated using (user_id = auth.uid());

create or replace function public.claim_voucher(p_voucher uuid) returns json
language plpgsql security definer set search_path = public as $$
declare
  v public.vouchers%rowtype;
  v_mine int;
  v_balance int;
  v_id uuid;
  v_exp timestamptz;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into v from public.vouchers where id = p_voucher for update;
  if v.id is null or not v.active then raise exception 'This voucher is no longer available'; end if;
  if v.starts_at > now() then raise exception 'This voucher is not live yet'; end if;
  if v.ends_at is not null and v.ends_at < now() then raise exception 'This voucher has ended'; end if;
  if v.max_claims is not null and v.claims_count >= v.max_claims then raise exception 'All vouchers have been claimed'; end if;
  if exists (select 1 from public.vendors vd where vd.id = v.vendor_id and vd.owner_id = auth.uid()) then
    raise exception 'You cannot claim your own voucher';
  end if;
  select count(*) into v_mine from public.voucher_claims where voucher_id = p_voucher and user_id = auth.uid() and status <> 'cancelled';
  if v_mine >= v.per_user_limit then raise exception 'You already claimed this voucher'; end if;
  if v.points_cost > 0 then
    select points into v_balance from public.profiles where id = auth.uid() for update;
    if coalesce(v_balance, 0) < v.points_cost then
      raise exception 'You need % points for this (you have %)', v.points_cost, coalesce(v_balance, 0);
    end if;
  end if;
  v_exp := coalesce(v.ends_at, now() + make_interval(days => public.setting_num('voucher_claim_days', 30)::int));
  insert into public.voucher_claims (voucher_id, user_id, points_spent, expires_at)
  values (p_voucher, auth.uid(), v.points_cost, v_exp) returning id into v_id;
  update public.vouchers set claims_count = claims_count + 1 where id = p_voucher;
  if v.points_cost > 0 then
    perform public.award_points(auth.uid(), -v.points_cost, 'redeem', 'voucher_claim', v_id::text, v.title, 'claim:' || v_id);
  end if;
  return json_build_object('id', v_id, 'expires_at', v_exp, 'points_spent', v.points_cost);
end;
$$;

-- What the customer shows at the counter.
create or replace function public.voucher_claim_payload(p_claim uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  c public.voucher_claims%rowtype;
begin
  select * into c from public.voucher_claims where id = p_claim and user_id = auth.uid();
  if c.id is null then raise exception 'Voucher not found'; end if;
  if c.status <> 'active' then raise exception 'This voucher was already %', c.status; end if;
  if c.expires_at < now() then raise exception 'This voucher expired'; end if;
  return 'ttspot://voucher/' || c.id || '/' || c.code;
end;
$$;

-- Vendor-side: what is this QR, before redeeming.
create or replace function public.lookup_voucher_claim(p_claim uuid, p_code text) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  c public.voucher_claims%rowtype;
  v public.vouchers%rowtype;
  v_vendor uuid := public.my_vendor_id();
  v_username text;
  v_display text;
  v_avatar text;
begin
  if v_vendor is null then raise exception 'Only partners can scan vouchers'; end if;
  select * into c from public.voucher_claims where id = p_claim;
  if c.id is null or c.code <> p_code then raise exception 'Invalid voucher QR'; end if;
  select * into v from public.vouchers where id = c.voucher_id;
  if v.vendor_id <> v_vendor then raise exception 'This voucher belongs to another shop'; end if;
  select username, display_name, avatar_url into v_username, v_display, v_avatar from public.profiles where id = c.user_id;
  return json_build_object(
    'claim_id', c.id, 'status', case when c.status = 'active' and c.expires_at < now() then 'expired' else c.status end,
    'expires_at', c.expires_at, 'redeemed_at', c.redeemed_at,
    'voucher_id', v.id, 'title', v.title, 'discount_kind', v.discount_kind, 'discount_value', v.discount_value,
    'min_spend', v.min_spend, 'terms', v.terms,
    'username', v_username, 'display_name', v_display, 'avatar_url', v_avatar,
    'commission_rate', coalesce((select commission_rate from public.vendors where id = v_vendor), public.setting_num('commission_rate', 0.01))
  );
end;
$$;

-- ------------------------------------------------------------ redemptions ---
create table public.voucher_redemptions (
  id                uuid primary key default gen_random_uuid(),
  claim_id          uuid not null unique references public.voucher_claims (id) on delete cascade,
  voucher_id        uuid not null references public.vouchers (id) on delete cascade,
  vendor_id         uuid not null references public.vendors (id) on delete cascade,
  user_id           uuid not null references public.profiles (id) on delete cascade,
  bill_amount       numeric(10,2) not null check (bill_amount >= 0),
  commission_rate   numeric(6,4) not null,
  commission_amount numeric(10,2) not null,
  receipt_url       text,
  note              text,
  redeemed_by       uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now()
);
create index voucher_redemptions_vendor_idx on public.voucher_redemptions (vendor_id, created_at desc);
alter table public.voucher_redemptions enable row level security;
create policy "redemptions: read" on public.voucher_redemptions for select to authenticated
  using (user_id = auth.uid() or public.is_admin() or vendor_id = public.my_vendor_id());

create or replace function public.redeem_voucher(p_claim uuid, p_code text, p_bill numeric, p_receipt_url text default null, p_note text default null)
returns json
language plpgsql security definer set search_path = public as $$
declare
  c public.voucher_claims%rowtype;
  v public.vouchers%rowtype;
  v_vendor uuid := public.my_vendor_id();
  v_rate numeric;
  v_comm numeric;
  v_id uuid;
  v_name text;
begin
  if v_vendor is null then raise exception 'Only partners can redeem vouchers'; end if;
  if p_bill is null or p_bill < 0 then raise exception 'Enter the bill amount'; end if;
  select * into c from public.voucher_claims where id = p_claim for update;
  if c.id is null or c.code <> p_code then raise exception 'Invalid voucher QR'; end if;
  select * into v from public.vouchers where id = c.voucher_id;
  if v.vendor_id <> v_vendor then raise exception 'This voucher belongs to another shop'; end if;
  if c.status = 'redeemed' then raise exception 'Already redeemed on %', to_char(c.redeemed_at, 'DD Mon HH24:MI'); end if;
  if c.status <> 'active' then raise exception 'This voucher is %', c.status; end if;
  if c.expires_at < now() then
    update public.voucher_claims set status = 'expired' where id = c.id;
    raise exception 'This voucher expired';
  end if;
  if v.min_spend > 0 and p_bill < v.min_spend then raise exception 'Minimum spend is RM %', v.min_spend; end if;
  v_rate := coalesce((select commission_rate from public.vendors where id = v_vendor), public.setting_num('commission_rate', 0.01));
  v_comm := round(p_bill * v_rate, 2);
  insert into public.voucher_redemptions (claim_id, voucher_id, vendor_id, user_id, bill_amount, commission_rate, commission_amount, receipt_url, note, redeemed_by)
  values (c.id, v.id, v_vendor, c.user_id, p_bill, v_rate, v_comm, p_receipt_url, nullif(trim(p_note), ''), auth.uid())
  returning id into v_id;
  update public.voucher_claims set status = 'redeemed', redeemed_at = now() where id = c.id;
  select name into v_name from public.vendors where id = v_vendor;
  perform public.notify(c.user_id, null, 'voucher', p_body => 'redeemed:' || v.title || ' at ' || v_name);
  return json_build_object('id', v_id, 'bill', p_bill, 'commission', v_comm, 'rate', v_rate, 'title', v.title);
end;
$$;

-- --------------------------------------------------------------- listings ---

-- Rewards shop: live vouchers, with how many I already hold.
create or replace function public.shop_vouchers(p_limit int default 100)
returns table (id uuid, vendor_id uuid, vendor_name text, vendor_type text, vendor_logo text, vendor_address text, place_id uuid,
               title text, description text, terms text, discount_kind text, discount_value numeric, min_spend numeric,
               points_cost int, max_claims int, claims_count int, per_user_limit int, starts_at timestamptz, ends_at timestamptz,
               my_claims int, my_active_claim uuid)
language sql stable security definer set search_path = public as $$
  select v.id, vd.id, vd.name, vd.type, vd.logo_url, vd.address, vd.place_id,
         v.title, v.description, v.terms, v.discount_kind, v.discount_value, v.min_spend,
         v.points_cost, v.max_claims, v.claims_count, v.per_user_limit, v.starts_at, v.ends_at,
         (select count(*)::int from public.voucher_claims c where c.voucher_id = v.id and c.user_id = auth.uid() and c.status <> 'cancelled'),
         (select c.id from public.voucher_claims c where c.voucher_id = v.id and c.user_id = auth.uid() and c.status = 'active' and c.expires_at > now()
            order by c.claimed_at desc limit 1)
  from public.vouchers v join public.vendors vd on vd.id = v.vendor_id
  where v.active and vd.active and v.starts_at <= now() and (v.ends_at is null or v.ends_at > now())
    and (v.max_claims is null or v.claims_count < v.max_claims)
    and vd.owner_id is distinct from auth.uid()
  order by v.points_cost = 0 desc, v.created_at desc
  limit p_limit;
$$;

-- My wallet.
create or replace function public.my_vouchers(p_limit int default 100)
returns table (id uuid, voucher_id uuid, title text, discount_kind text, discount_value numeric, min_spend numeric, terms text,
               vendor_id uuid, vendor_name text, vendor_logo text, vendor_address text, place_id uuid,
               status text, points_spent int, claimed_at timestamptz, expires_at timestamptz, redeemed_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, v.id, v.title, v.discount_kind, v.discount_value, v.min_spend, v.terms,
         vd.id, vd.name, vd.logo_url, vd.address, vd.place_id,
         case when c.status = 'active' and c.expires_at < now() then 'expired' else c.status end,
         c.points_spent, c.claimed_at, c.expires_at, c.redeemed_at
  from public.voucher_claims c
  join public.vouchers v on v.id = c.voucher_id
  join public.vendors vd on vd.id = v.vendor_id
  where c.user_id = auth.uid()
  order by (c.status = 'active' and c.expires_at > now()) desc, c.claimed_at desc
  limit p_limit;
$$;

-- Vendor dashboard.
create or replace function public.my_vendor()
returns table (id uuid, name text, type text, address text, place_id uuid, phone text, description text, logo_url text, active boolean,
               commission_rate numeric, created_at timestamptz, live_vouchers int, redemptions_30d int, bill_30d numeric, commission_30d numeric)
language sql stable security definer set search_path = public as $$
  select vd.id, vd.name, vd.type, vd.address, vd.place_id, vd.phone, vd.description, vd.logo_url, vd.active,
         coalesce(vd.commission_rate, public.setting_num('commission_rate', 0.01)), vd.created_at,
         (select count(*)::int from public.vouchers v where v.vendor_id = vd.id and v.active and (v.ends_at is null or v.ends_at > now())),
         (select count(*)::int from public.voucher_redemptions r where r.vendor_id = vd.id and r.created_at > now() - interval '30 days'),
         (select coalesce(sum(r.bill_amount), 0) from public.voucher_redemptions r where r.vendor_id = vd.id and r.created_at > now() - interval '30 days'),
         (select coalesce(sum(r.commission_amount), 0) from public.voucher_redemptions r where r.vendor_id = vd.id and r.created_at > now() - interval '30 days')
  from public.vendors vd where vd.owner_id = auth.uid();
$$;

create or replace function public.my_vendor_vouchers()
returns table (id uuid, title text, description text, terms text, discount_kind text, discount_value numeric, min_spend numeric,
               points_cost int, max_claims int, claims_count int, per_user_limit int, starts_at timestamptz, ends_at timestamptz,
               active boolean, created_at timestamptz, redemptions int)
language sql stable security definer set search_path = public as $$
  select v.id, v.title, v.description, v.terms, v.discount_kind, v.discount_value, v.min_spend, v.points_cost, v.max_claims,
         v.claims_count, v.per_user_limit, v.starts_at, v.ends_at, v.active, v.created_at,
         (select count(*)::int from public.voucher_redemptions r where r.voucher_id = v.id)
  from public.vouchers v where v.vendor_id = public.my_vendor_id()
  order by v.active desc, v.created_at desc;
$$;

create or replace function public.my_vendor_redemptions(p_limit int default 100)
returns table (id uuid, title text, username text, avatar_url text, bill_amount numeric, commission_rate numeric, commission_amount numeric,
               receipt_url text, note text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, v.title, pr.username::text, pr.avatar_url, r.bill_amount, r.commission_rate, r.commission_amount, r.receipt_url, r.note, r.created_at
  from public.voucher_redemptions r
  join public.vouchers v on v.id = r.voucher_id
  join public.profiles pr on pr.id = r.user_id
  where r.vendor_id = public.my_vendor_id()
  order by r.created_at desc
  limit p_limit;
$$;

-- Monthly statement: one row per month for the last 12 months (vendor: own; admin: any vendor or all).
create or replace function public.vendor_monthly_report(p_vendor uuid default null)
returns table (month date, redemptions int, bill_total numeric, commission_total numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  v_vendor uuid := p_vendor;
begin
  if not public.is_admin() then
    v_vendor := public.my_vendor_id();
    if v_vendor is null then raise exception 'You are not a partner'; end if;
  end if;
  return query
    select date_trunc('month', r.created_at)::date, count(*)::int, sum(r.bill_amount), sum(r.commission_amount)
    from public.voucher_redemptions r
    where (v_vendor is null or r.vendor_id = v_vendor) and r.created_at > date_trunc('month', now()) - interval '11 months'
    group by 1 order by 1 desc;
end;
$$;

-- Admin: commission owed per vendor for a month.
create or replace function public.admin_commission_report(p_month date default date_trunc('month', now())::date)
returns table (vendor_id uuid, vendor_name text, owner_username text, redemptions int, bill_total numeric, commission_total numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select vd.id, vd.name, pr.username::text, count(r.id)::int, coalesce(sum(r.bill_amount), 0), coalesce(sum(r.commission_amount), 0)
    from public.vendors vd
    join public.profiles pr on pr.id = vd.owner_id
    left join public.voucher_redemptions r on r.vendor_id = vd.id
      and r.created_at >= date_trunc('month', p_month::timestamptz) and r.created_at < date_trunc('month', p_month::timestamptz) + interval '1 month'
    group by vd.id, vd.name, pr.username
    order by 6 desc, vd.name;
end;
$$;

-- Points screen label for spends.
insert into public.point_rules (reason, points, label, description, sort) values
  ('redeem', 0, 'Claimed a reward', 'Points spent on a partner voucher.', 900)
on conflict (reason) do nothing;

-- Expire stale claims nightly so wallets stay tidy (redeem_voucher also checks live).
select cron.schedule('ttspot-expire-claims', '5 0 * * *',
  $cron$ update public.voucher_claims set status = 'expired' where status = 'active' and expires_at < now() $cron$);
