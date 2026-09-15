-- A partner's statement is always their own. Admins who are also partners
-- were getting every vendor's totals here; cross-vendor numbers live in
-- admin_commission_report only.
create or replace function public.vendor_monthly_report(p_vendor uuid default null)
returns table (month date, redemptions int, bill_total numeric, commission_total numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  v_vendor uuid := coalesce(p_vendor, public.my_vendor_id());
begin
  if v_vendor is null then raise exception 'You are not a partner'; end if;
  if v_vendor <> coalesce(public.my_vendor_id(), '00000000-0000-0000-0000-000000000000') and not public.is_admin() then
    raise exception 'Not your statement';
  end if;
  return query
    select date_trunc('month', r.created_at)::date, count(*)::int, sum(r.bill_amount), sum(r.commission_amount)
    from public.voucher_redemptions r
    where r.vendor_id = v_vendor and r.created_at > date_trunc('month', now()) - interval '11 months'
    group by 1 order by 1 desc;
end;
$$;
