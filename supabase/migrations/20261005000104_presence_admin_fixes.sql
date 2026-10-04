-- Presence and profile stats fixes (0.3.53).
--
-- 1. admin_stats: the dashboard counted "On the map" as a position under 20
--    minutes old. The app's rule since 0.3.52
--    (lib/features/friends/domain/presence.dart):
--
--      live      a position at most 1 minute old    kLiveWindow  "Live now"
--      on map    a position under 24 hours old      kShowWindow  "Seen today"
--
--    Both leave out ghosts and expired rows, as visible_pins leaves them off
--    the map. New keys live_now and seen_today. on_map_now (read by 0.3.52
--    and older dashboards) now carries live_now, so no dashboard counts 20
--    minutes any more. Change a window in presence.dart and here together:
--    test/presence_admin_test.dart reads this file and fails when they drift.
--
-- 2. Profile "Meets" counted check-ins only, so a member who joined a TT
--    session (an event_attendees row) and was never checked in read
--    "Meets 0". A meet now counts once it has started and wasn't cancelled,
--    when the member joined it, checked in at it or hosts it (TT sessions
--    and planned meets alike; future RSVPs wait until the start):
--
--      went_event_ids(user)      the one definition (ids only: who joined
--                                what is readable to everyone signed in)
--      profile_meet_count(user)  the number on the profile, the same for
--                                every viewer
--      profile_meets(user)       the list behind it, as the viewer may see
--                                it (events_with_counts, under events RLS),
--                                newest first. The sheet says how many more
--                                are private.

-- ------------------------------------------------------------ 1. admin ---
-- As in 20260918000041 except on_map_now / live_now / seen_today.
create or replace function public.admin_stats() returns json
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days date[] := array(select (v_today - i) from generate_series(6, 0, -1) i);
  v_live int;
  v_seen int;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  -- presence.dart: kLiveWindow (age <= 1 min), kShowWindow (age < 24 h).
  select count(*) filter (where updated_at >= now() - interval '1 minute'),
         count(*) filter (where updated_at > now() - interval '24 hours')
    into v_live, v_seen
    from public.user_locations
   where not ghost and expires_at > now();
  return json_build_object(
    'users', (select count(*) from public.profiles where username is not null),
    'users_7d', (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'users_today', (select count(*) from public.profiles where (created_at at time zone 'Asia/Kuala_Lumpur')::date = v_today),
    'live_now', v_live,
    'seen_today', v_seen,
    'on_map_now', v_live,
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

-- ------------------------------------------------------------ 2. meets ---
create or replace function public.went_event_ids(p_user uuid)
returns setof uuid
language sql stable security definer set search_path = public as $$
  select e.id
    from (
      select a.event_id from public.event_attendees a where a.user_id = p_user
      union
      select c.event_id from public.checkins c where c.user_id = p_user
      union
      select x.id from public.events x where x.organizer_id = p_user
    ) m
    join public.events e on e.id = m.event_id
   where e.status = 'active'
     and e.starts_at <= now();
$$;

create or replace function public.profile_meet_count(p_user uuid)
returns int
language sql stable set search_path = public as $$
  select count(*)::int from public.went_event_ids(p_user);
$$;

-- Security invoker: events_with_counts is security_invoker too, so a private
-- meet the viewer may not see stays out of the list (but in the count).
-- Rows as json, not setof events_with_counts: a function returning the
-- view's row type would stop later migrations dropping and recreating it.
create or replace function public.profile_meets(p_user uuid, p_limit int default 100)
returns setof json
language sql stable set search_path = public as $$
  select to_json(v)
    from public.events_with_counts v
   where v.id in (select public.went_event_ids(p_user))
   order by v.starts_at desc
   limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

revoke execute on function public.went_event_ids(uuid) from public, anon;
revoke execute on function public.profile_meet_count(uuid) from public, anon;
revoke execute on function public.profile_meets(uuid, int) from public, anon;
grant execute on function public.went_event_ids(uuid) to authenticated;
grant execute on function public.profile_meet_count(uuid) to authenticated;
grant execute on function public.profile_meets(uuid, int) to authenticated;
