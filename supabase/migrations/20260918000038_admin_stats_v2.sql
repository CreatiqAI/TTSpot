-- Admin overview v2: today, 7-day trends per day, community totals, top spots.
create or replace function public.admin_stats() returns json
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days date[] := array(select (v_today - i) from generate_series(6, 0, -1) i);
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return json_build_object(
    -- totals
    'users', (select count(*) from public.profiles where username is not null),
    'users_7d', (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'users_today', (select count(*) from public.profiles where (created_at at time zone 'Asia/Kuala_Lumpur')::date = v_today),
    'on_map_now', (select count(*) from public.user_locations where updated_at > now() - interval '20 minutes' and not ghost),
    'active_24h', (select count(distinct user_id) from public.user_locations where updated_at > now() - interval '24 hours'),
    -- meets
    'meets_live', (select count(*) from public.events where status = 'active' and now() between starts_at - interval '1 hour' and coalesce(ends_at, starts_at + interval '6 hours')),
    'meets_upcoming', (select count(*) from public.events where status = 'active' and starts_at > now()),
    'meets_7d', (select count(*) from public.events where created_at > now() - interval '7 days'),
    'tt_today', (select count(*) from public.events where is_instant and (created_at at time zone 'Asia/Kuala_Lumpur')::date = v_today),
    -- activity
    'checkins_today', (select count(*) from public.checkins where (checked_in_at at time zone 'Asia/Kuala_Lumpur')::date = v_today)
                    + (select count(*) from public.place_checkins where (checked_in_at at time zone 'Asia/Kuala_Lumpur')::date = v_today),
    'checkins_7d', (select count(*) from public.checkins where checked_in_at > now() - interval '7 days')
                 + (select count(*) from public.place_checkins where checked_in_at > now() - interval '7 days'),
    'posts_7d', (select count(*) from public.posts where created_at > now() - interval '7 days'),
    'messages_7d', (select count(*) from public.messages where created_at > now() - interval '7 days'),
    -- per day, oldest first (7 entries)
    'signups_by_day', (select json_agg(c order by d) from (select d, (select count(*) from public.profiles p where (p.created_at at time zone 'Asia/Kuala_Lumpur')::date = d) c from unnest(v_days) d) t),
    'checkins_by_day', (select json_agg(c order by d) from (select d,
        (select count(*) from public.checkins x where (x.checked_in_at at time zone 'Asia/Kuala_Lumpur')::date = d)
      + (select count(*) from public.place_checkins y where (y.checked_in_at at time zone 'Asia/Kuala_Lumpur')::date = d) c from unnest(v_days) d) t),
    'posts_by_day', (select json_agg(c order by d) from (select d, (select count(*) from public.posts p where (p.created_at at time zone 'Asia/Kuala_Lumpur')::date = d) c from unnest(v_days) d) t),
    'active_by_day', (select json_agg(c order by d) from (select d, (select count(distinct user_id) from public.user_locations l where (l.updated_at at time zone 'Asia/Kuala_Lumpur')::date = d) c from unnest(v_days) d) t),
    -- queues
    'pending_verifications', (select count(*) from public.spot_verifications where status in ('pending', 'review')),
    'pending_partners', (select count(*) from public.partner_applications where status = 'pending'),
    'pending_suggestions', (select count(*) from public.place_suggestions where status = 'pending'),
    'open_reports', (select count(*) from public.reports where resolved_at is null),
    -- community
    'vendors', (select count(*) from public.vendors where active),
    'clubs', (select count(*) from public.clubs),
    'club_members', (select count(*) from public.club_members),
    'vouchers_live', (select count(*) from public.vouchers v where v.active and v.starts_at <= now() and (v.ends_at is null or v.ends_at > now())),
    'claims_30d', (select count(*) from public.voucher_claims where claimed_at > now() - interval '30 days'),
    'redemptions_30d', (select count(*) from public.voucher_redemptions where created_at > now() - interval '30 days'),
    'bills_30d', (select coalesce(sum(bill_amount), 0) from public.voucher_redemptions where created_at > now() - interval '30 days'),
    'commission_30d', (select coalesce(sum(commission_amount), 0) from public.voucher_redemptions where created_at > now() - interval '30 days'),
    'places', (select count(*) from public.places),
    -- top spots this week
    'top_places', (select coalesce(json_agg(json_build_object('id', id, 'name', name, 'count', c)), '[]'::json) from (
        select pl.id, pl.name, count(*) c from public.place_checkins pc join public.places pl on pl.id = pc.place_id
        where pc.checked_in_at > now() - interval '7 days' group by pl.id, pl.name order by c desc limit 3) t)
  );
end;
$$;
