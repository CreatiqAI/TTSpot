-- Partners, round two: structured opening hours, posting as the partner,
-- and simple numbers on the dashboard.

-- ------------------------------------------------------------ hours ---
-- {"mon": {"open": "10:00", "close": "19:00"}, ..., "sun": null}
alter table public.vendors add column if not exists hours_json jsonb;

-- ------------------------------------------------------------- posts ---
alter table public.posts
  add column if not exists vendor_id uuid references public.vendors (id) on delete set null,
  add column if not exists as_vendor boolean not null default false;
create index if not exists posts_vendor_idx on public.posts (vendor_id) where vendor_id is not null;

drop policy if exists "posts: insert own" on public.posts;
create policy "posts: insert own" on public.posts for insert to authenticated
  with check (
    author_id = auth.uid()
    and (not as_club or (club_id is not null and public.is_club_admin(club_id)))
    and (not as_vendor or (vendor_id is not null and public.can_act_as_vendor(vendor_id)))
  );

drop view if exists public.posts_with_counts;
create view public.posts_with_counts
with (security_invoker = true) as
select
  p.*,
  (select count(*) from public.post_likes l where l.post_id = p.id)::int    as like_count,
  (select count(*) from public.post_comments c where c.post_id = p.id)::int as comment_count,
  (select count(*) from public.poll_votes v where v.post_id = p.id)::int    as vote_count
from public.posts p;

-- -------------------------------------------------------------- views ---
create table if not exists public.vendor_page_views (
  vendor_id uuid not null references public.vendors (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  day       date not null default (now() at time zone 'Asia/Kuala_Lumpur')::date,
  primary key (vendor_id, viewer_id, day)
);
alter table public.vendor_page_views enable row level security;

-- One view per member per day; owners looking at their own page do not count.
create or replace function public.view_partner(p_vendor uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  if exists (select 1 from public.vendors v where v.id = p_vendor and v.owner_id = auth.uid()) then return; end if;
  insert into public.vendor_page_views (vendor_id, viewer_id) values (p_vendor, auth.uid()) on conflict do nothing;
end;
$$;

-- ------------------------------------------------------------ editing ---
drop function if exists public.update_my_vendor(text, text, text, text, float8, float8, text, text[]);
create or replace function public.update_my_vendor(
  p_address text default null, p_phone text default null, p_description text default null, p_logo_url text default null,
  p_lat float8 default null, p_lng float8 default null, p_hours text default null, p_photo_urls text[] default null,
  p_hours_json jsonb default null
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
         hours_json = coalesce(p_hours_json, hours_json),
         photo_urls = coalesce(p_photo_urls, photo_urls)
   where owner_id = auth.uid()
   returning id into v_id;
  if v_id is null then raise exception 'You are not a partner'; end if;
  perform public.sync_vendor_place(v_id);
end;
$$;

-- ------------------------------------------------------------- public ---
drop view if exists public.vendors_public;
create view public.vendors_public
with (security_invoker = true) as
select v.id, v.owner_id, v.name, v.type, v.address, v.lat, v.lng, v.hours, v.hours_json, v.photo_urls, v.logo_url, v.description, v.phone, v.place_id, v.created_at,
       (select count(*) from public.vouchers vo where vo.vendor_id = v.id and vo.active and (vo.ends_at is null or vo.ends_at > now()))::int as live_vouchers,
       (select count(*) from public.events e where e.vendor_id = v.id and e.status = 'active' and e.starts_at >= now() - interval '6 hours')::int as upcoming_events
from public.vendors v
where v.active;
grant select on public.vendors_public to authenticated;

-- ---------------------------------------------------------- dashboard ---
drop function if exists public.my_vendor();
create function public.my_vendor()
returns table (id uuid, name text, type text, address text, place_id uuid, phone text, description text, logo_url text, active boolean,
               commission_rate numeric, created_at timestamptz, live_vouchers int, redemptions_30d int, bill_30d numeric, commission_30d numeric,
               lat float8, lng float8, hours text, photo_urls text[], hours_json jsonb, views_30d int, checkins_30d int, claims_30d int)
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
         (select count(*)::int from public.voucher_claims c join public.vouchers v on v.id = c.voucher_id where v.vendor_id = vd.id and c.claimed_at > now() - interval '30 days')
  from public.vendors vd where vd.owner_id = auth.uid();
$$;
