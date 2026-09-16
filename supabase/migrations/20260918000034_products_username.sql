-- Mini store for partners (up to 5 display-only products with variants),
-- vouchers that apply to one product, and a live username check.

-- ------------------------------------------------------------ username ---
create or replace function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from public.profiles
    where username = lower(trim(p_username))::citext and id is distinct from auth.uid()
  );
$$;

-- ------------------------------------------------------------ products ---
create table if not exists public.vendor_products (
  id          uuid primary key default gen_random_uuid(),
  vendor_id   uuid not null references public.vendors (id) on delete cascade,
  name        text not null check (char_length(name) between 2 and 60),
  description text check (description is null or char_length(description) <= 300),
  price       numeric(10,2) check (price is null or price >= 0),           -- null = ask the shop
  photo_urls  text[] not null default '{}' check (cardinality(photo_urls) <= 4),
  -- [{"name": "Size", "options": ["S", "M", "L"]}] — up to 3 groups, 8 options each (checked in save_product)
  variants    jsonb not null default '[]'::jsonb,
  sort_order  int not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index if not exists vendor_products_vendor_idx on public.vendor_products (vendor_id, sort_order, created_at);
alter table public.vendor_products enable row level security;
drop policy if exists "products: read" on public.vendor_products;
create policy "products: read" on public.vendor_products for select to authenticated
  using (active or vendor_id = public.my_vendor_id());

create or replace function public.save_product(
  p_id uuid, p_name text, p_description text, p_price numeric, p_photo_urls text[], p_variants jsonb, p_active boolean
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_vendor uuid := public.my_vendor_id();
  v_id uuid;
  v_count int;
  g jsonb;
begin
  if v_vendor is null then raise exception 'You are not an active partner'; end if;
  if p_variants is not null then
    if jsonb_typeof(p_variants) <> 'array' or jsonb_array_length(p_variants) > 3 then raise exception 'Up to 3 variant groups'; end if;
    for g in select * from jsonb_array_elements(p_variants) loop
      if coalesce(char_length(g->>'name'), 0) between 1 and 30 is not true then raise exception 'Give every variant group a short name'; end if;
      if jsonb_typeof(g->'options') <> 'array' or jsonb_array_length(g->'options') between 1 and 8 is not true then raise exception 'Each group needs 1–8 options'; end if;
    end loop;
  end if;
  if p_id is null then
    select count(*) into v_count from public.vendor_products where vendor_id = v_vendor;
    if v_count >= 5 then raise exception 'Up to 5 products per shop for now'; end if;
    insert into public.vendor_products (vendor_id, name, description, price, photo_urls, variants, sort_order, active)
    values (v_vendor, trim(p_name), nullif(trim(p_description), ''), p_price, coalesce(p_photo_urls, '{}'), coalesce(p_variants, '[]'::jsonb), v_count, coalesce(p_active, true))
    returning id into v_id;
    return v_id;
  end if;
  update public.vendor_products
     set name = trim(p_name), description = nullif(trim(p_description), ''), price = p_price,
         photo_urls = coalesce(p_photo_urls, photo_urls), variants = coalesce(p_variants, variants), active = coalesce(p_active, active)
   where id = p_id and vendor_id = v_vendor;
  if not found then raise exception 'Product not found'; end if;
  return p_id;
end;
$$;

create or replace function public.delete_product(p_id uuid) returns void
language sql security definer set search_path = public as $$
  delete from public.vendor_products where id = p_id and vendor_id = public.my_vendor_id();
$$;

-- ---------------------------------------------- vouchers apply to one product ---
alter table public.vouchers add column if not exists product_id uuid references public.vendor_products (id) on delete set null;

drop function if exists public.save_voucher(uuid, text, text, text, text, numeric, numeric, int, int, int, timestamptz, timestamptz, boolean);
create function public.save_voucher(
  p_id uuid, p_title text, p_description text, p_terms text, p_kind text, p_value numeric, p_min_spend numeric,
  p_points_cost int, p_max_claims int, p_per_user int, p_starts timestamptz, p_ends timestamptz, p_active boolean,
  p_product_id uuid default null
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
  if p_product_id is not null and not exists (select 1 from public.vendor_products where id = p_product_id and vendor_id = v_vendor) then
    raise exception 'That product is not in your shop';
  end if;
  if p_id is null then
    select count(*) into v_live from public.vouchers where vendor_id = v_vendor and active and (ends_at is null or ends_at > now());
    if p_active and v_live >= public.setting_num('max_active_vouchers', 10) then
      raise exception 'You already have % live vouchers', v_live;
    end if;
    insert into public.vouchers (vendor_id, title, description, terms, discount_kind, discount_value, min_spend, points_cost,
                                 max_claims, per_user_limit, starts_at, ends_at, active, product_id)
    values (v_vendor, trim(p_title), nullif(trim(p_description), ''), nullif(trim(p_terms), ''), p_kind, coalesce(p_value, 0),
            coalesce(p_min_spend, 0), coalesce(p_points_cost, 0), p_max_claims, coalesce(p_per_user, 1),
            coalesce(p_starts, now()), p_ends, coalesce(p_active, true), p_product_id)
    returning id into v_id;
    return v_id;
  end if;
  update public.vouchers
     set title = trim(p_title), description = nullif(trim(p_description), ''), terms = nullif(trim(p_terms), ''),
         discount_kind = p_kind, discount_value = coalesce(p_value, 0), min_spend = coalesce(p_min_spend, 0),
         points_cost = coalesce(p_points_cost, 0), max_claims = p_max_claims, per_user_limit = coalesce(p_per_user, 1),
         starts_at = coalesce(p_starts, starts_at), ends_at = p_ends, active = coalesce(p_active, active),
         product_id = p_product_id
   where id = p_id and vendor_id = v_vendor;
  if not found then raise exception 'Voucher not found'; end if;
  return p_id;
end;
$$;

drop function if exists public.my_vendor_vouchers();
create function public.my_vendor_vouchers()
returns table (id uuid, title text, description text, terms text, discount_kind text, discount_value numeric, min_spend numeric,
               points_cost int, max_claims int, claims_count int, per_user_limit int, starts_at timestamptz, ends_at timestamptz,
               active boolean, created_at timestamptz, redemptions int, product_id uuid, product_name text)
language sql stable security definer set search_path = public as $$
  select v.id, v.title, v.description, v.terms, v.discount_kind, v.discount_value, v.min_spend, v.points_cost, v.max_claims,
         v.claims_count, v.per_user_limit, v.starts_at, v.ends_at, v.active, v.created_at,
         (select count(*)::int from public.voucher_redemptions r where r.voucher_id = v.id),
         v.product_id, (select p.name from public.vendor_products p where p.id = v.product_id)
  from public.vouchers v where v.vendor_id = public.my_vendor_id()
  order by v.active desc, v.created_at desc;
$$;

drop function if exists public.shop_vouchers(int);
create function public.shop_vouchers(p_limit int default 100)
returns table (id uuid, vendor_id uuid, vendor_name text, vendor_type text, vendor_logo text, vendor_address text, place_id uuid,
               title text, description text, terms text, discount_kind text, discount_value numeric, min_spend numeric,
               points_cost int, max_claims int, claims_count int, per_user_limit int, starts_at timestamptz, ends_at timestamptz,
               my_claims int, my_active_claim uuid, product_id uuid, product_name text)
language sql stable security definer set search_path = public as $$
  select v.id, vd.id, vd.name, vd.type, vd.logo_url, vd.address, vd.place_id,
         v.title, v.description, v.terms, v.discount_kind, v.discount_value, v.min_spend,
         v.points_cost, v.max_claims, v.claims_count, v.per_user_limit, v.starts_at, v.ends_at,
         (select count(*)::int from public.voucher_claims c where c.voucher_id = v.id and c.user_id = auth.uid() and c.status <> 'cancelled'),
         (select c.id from public.voucher_claims c where c.voucher_id = v.id and c.user_id = auth.uid() and c.status = 'active' and c.expires_at > now()
            order by c.claimed_at desc limit 1),
         v.product_id, (select p.name from public.vendor_products p where p.id = v.product_id)
  from public.vouchers v join public.vendors vd on vd.id = v.vendor_id
  where v.active and vd.active and v.starts_at <= now() and (v.ends_at is null or v.ends_at > now())
    and (v.max_claims is null or v.claims_count < v.max_claims)
    and vd.owner_id is distinct from auth.uid()
  order by v.points_cost = 0 desc, v.created_at desc
  limit p_limit;
$$;

-- ------------------------------------------------------------- public ---
drop view if exists public.vendors_public;
create view public.vendors_public
with (security_invoker = true) as
select v.id, v.owner_id, v.name, v.type, v.address, v.lat, v.lng, v.hours, v.hours_json, v.photo_urls, v.logo_url, v.description, v.phone, v.place_id, v.created_at,
       (select count(*) from public.vouchers vo where vo.vendor_id = v.id and vo.active and (vo.ends_at is null or vo.ends_at > now()))::int as live_vouchers,
       (select count(*) from public.events e where e.vendor_id = v.id and e.status = 'active' and e.starts_at >= now() - interval '6 hours')::int as upcoming_events,
       (select count(*) from public.vendor_products p where p.vendor_id = v.id and p.active)::int as product_count
from public.vendors v
where v.active;
grant select on public.vendors_public to authenticated;
