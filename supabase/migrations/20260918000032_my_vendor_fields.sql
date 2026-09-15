-- The partner's own dashboard needs the new fields too (hours, position, photos).
drop function if exists public.my_vendor();
create function public.my_vendor()
returns table (id uuid, name text, type text, address text, place_id uuid, phone text, description text, logo_url text, active boolean,
               commission_rate numeric, created_at timestamptz, live_vouchers int, redemptions_30d int, bill_30d numeric, commission_30d numeric,
               lat float8, lng float8, hours text, photo_urls text[])
language sql stable security definer set search_path = public as $$
  select vd.id, vd.name, vd.type, vd.address, vd.place_id, vd.phone, vd.description, vd.logo_url, vd.active,
         coalesce(vd.commission_rate, public.setting_num('commission_rate', 0.01)), vd.created_at,
         (select count(*)::int from public.vouchers v where v.vendor_id = vd.id and v.active and (v.ends_at is null or v.ends_at > now())),
         (select count(*)::int from public.voucher_redemptions r where r.vendor_id = vd.id and r.created_at > now() - interval '30 days'),
         (select coalesce(sum(r.bill_amount), 0) from public.voucher_redemptions r where r.vendor_id = vd.id and r.created_at > now() - interval '30 days'),
         (select coalesce(sum(r.commission_amount), 0) from public.voucher_redemptions r where r.vendor_id = vd.id and r.created_at > now() - interval '30 days'),
         vd.lat, vd.lng, vd.hours, vd.photo_urls
  from public.vendors vd where vd.owner_id = auth.uid();
$$;
