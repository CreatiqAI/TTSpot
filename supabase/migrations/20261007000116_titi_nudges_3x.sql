-- =============================================================================
-- 0116 titi_nudges_3x: proactive TiTi, three a day (batch 0.3.60).
--
-- Owner's rules (2026-10-07): up to 3 TiTi messages a member a day, one in
-- each window, at a random time inside it, at least 3 h apart, Malaysia time:
--   morning   08:00-12:00   weather (MET), a meet they joined today, road tax /
--                           insurance due, else a car fact
--   afternoon 13:00-18:00   meets / TT near them later today, friends out now,
--                           a MET storm warning, Friday points reset, an
--                           unopened box, else a car-care tip
--   evening   19:00-23:00   meets live now near them, Sunday's weekly recap,
--                           a busy spot near them, else a joke / quote
-- Nothing 23:00-08:00. Never the same trigger twice in a day. No car make,
-- model or colour in the line. Each member's time in a window comes from a
-- hash of (user id, day, window) in the function (titi-nudge/rules.ts plan()).
--
--   titi_nudges.slot          1 morning, 2 afternoon, 3 evening; unique
--                             (user_id, day, slot) = one per window.
--   titi_nudge_candidates()   now per window, with their last TiTi message time.
--   titi_nudge_context()      adds nearby / live meets, friends out, the
--                             busiest spot near them, this week's check-ins
--                             and points, and today's messages.
--   cron                      every 30 min 08:00-22:30 MYT (00:00-14:30 UTC).
--   titi_nudges_daily_budget  300 → 900 (only if still the old default).
-- titi_nudges_enabled is left as it is. Safe to re-run.
-- =============================================================================

-- ------------------------------------------------------------ the log ---

alter table public.titi_nudges add column if not exists slot smallint;
update public.titi_nudges
   set slot = case
     when extract(hour from sent_at at time zone 'Asia/Kuala_Lumpur') < 12.5 then 1
     when extract(hour from sent_at at time zone 'Asia/Kuala_Lumpur') < 18.5 then 2
     else 3 end
 where slot is null;
alter table public.titi_nudges alter column slot set not null;
alter table public.titi_nudges drop constraint if exists titi_nudges_slot_check;
alter table public.titi_nudges add constraint titi_nudges_slot_check check (slot in (1, 2, 3));

alter table public.titi_nudges drop constraint if exists titi_nudges_user_id_day_key;
alter table public.titi_nudges drop constraint if exists titi_nudges_user_day_slot_key;
alter table public.titi_nudges add constraint titi_nudges_user_day_slot_key unique (user_id, day, slot);

alter table public.titi_nudges drop constraint if exists titi_nudges_trigger_check;
alter table public.titi_nudges add constraint titi_nudges_trigger_check check (trigger in (
  'weather', 'meet', 'doc', 'nearby', 'friends', 'points', 'box', 'live', 'busy', 'recap',
  'fact', 'tip', 'joke',
  'fun'  -- 0.3.58 rows
));

-- ------------------------------------------------------------ switches ---

update public.platform_settings
   set value = '900'::jsonb,
       description = 'Most proactive TiTi messages per Malaysian day, all members together (3 a member a day: about 3 x members).'
 where key = 'titi_nudges_daily_budget' and value = '300'::jsonb;
insert into public.platform_settings (key, value, description) values
  ('titi_nudges_daily_budget', '900'::jsonb, 'Most proactive TiTi messages per Malaysian day, all members together (3 a member a day: about 3 x members).')
on conflict (key) do nothing;

-- ------------------------------------------------------- candidates ---

-- Members who may get this window's message: TiTi tips on, a push token, not
-- suspended, nothing yet in this window today, fewer than 8 pushes in the
-- last 24 hours. The function then keeps the ones whose random time has come.
drop function if exists public.titi_nudge_candidates(int);
create or replace function public.titi_nudge_candidates(p_slot int, p_limit int default 5000)
returns table (user_id uuid, last_sent_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id,
         (select max(n.sent_at) from public.titi_nudges n where n.user_id = p.id)
    from public.profiles p
   where p.suspended_at is null
     and p.username is not null
     and not public.setting_off(p.settings, 'titi_tips')
     and exists (select 1 from public.push_tokens t where t.user_id = p.id)
     and not exists (select 1 from public.titi_nudges n
                      where n.user_id = p.id and n.slot = p_slot
                        and n.day = (now() at time zone 'Asia/Kuala_Lumpur')::date)
     and (select count(*) from public.notifications x
           where x.user_id = p.id and not x.silent and x.created_at > now() - interval '24 hours') < 8
   order by p.id
   limit greatest(1, least(p_limit, 20000));
$$;
revoke execute on function public.titi_nudge_candidates(int, int) from public, anon, authenticated;
grant execute on function public.titi_nudge_candidates(int, int) to service_role;

-- --------------------------------------------------------------- context ---

-- Everything the function needs to pick a trigger and write the line, per
-- member, in one call. "Near" = within 15 km of their last position (30 days).
-- Meets: public ones, a friend's, or their own club's; never their own.
create or replace function public.titi_nudge_context(p_users uuid[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_midnight timestamptz := (v_today::timestamp at time zone 'Asia/Kuala_Lumpur');
  v_week text := public.points_week_key(now());
  v_week_start timestamptz := public.points_week_start(now());
  v_near constant double precision := 15000;
begin
  return coalesce((
    select jsonb_object_agg(p.id, jsonb_build_object(
      'id', p.id,
      'name', coalesce(nullif(btrim(p.display_name), ''), p.username::text),
      'home_state', p.home_state,
      'titi_tips', not public.setting_off(p.settings, 'titi_tips'),
      'titi_lang', p.settings ->> 'titi_lang',
      'has_token', exists (select 1 from public.push_tokens t where t.user_id = p.id),
      'pushes_24h', (select count(*) from public.notifications x
                      where x.user_id = p.id and not x.silent and x.created_at > now() - interval '24 hours'),
      'car', (select jsonb_build_object('make', c.make, 'model', c.model, 'color', c.color, 'year', c.year)
                from public.cars c where c.owner_id = p.id
               order by c.is_default desc nulls last, c.created_at limit 1),
      'location', case when loc.lat is not null then jsonb_build_object('lat', loc.lat, 'lng', loc.lng) end,
      'recent', (select coalesce(jsonb_agg(left(m.content, 160) order by m.created_at), '[]'::jsonb)
                   from (select content, created_at from public.titi_messages
                          where user_id = p.id and role = 'user' and btrim(content) <> ''
                          order by created_at desc limit 8) m),
      'meets_today', (select coalesce(jsonb_agg(jsonb_build_object(
                          'id', e.id, 'title', e.title, 'venue', e.venue_name, 'starts_at', e.starts_at,
                          'going', exists (select 1 from public.event_attendees a where a.event_id = e.id and a.user_id = p.id),
                          'reminded_today', exists (select 1 from public.notifications n
                                                     where n.user_id = p.id and n.event_id = e.id
                                                       and n.type::text in ('event_reminder', 'meet_start')
                                                       and n.created_at >= v_midnight))
                          order by e.starts_at), '[]'::jsonb)
                        from public.events e
                       where e.status = 'active'
                         and e.starts_at > now()
                         and (e.starts_at at time zone 'Asia/Kuala_Lumpur')::date = v_today
                         and (exists (select 1 from public.event_attendees a where a.event_id = e.id and a.user_id = p.id)
                           or exists (select 1 from public.event_bookmarks b where b.event_id = e.id and b.user_id = p.id))),
      'docs', (select coalesce(jsonb_agg(jsonb_build_object('car_id', c.id, 'model', c.model, 'kind', x.kind, 'due', x.due, 'days', x.due - v_today)
                        order by x.due), '[]'::jsonb)
                 from public.car_documents d
                 join public.cars c on c.id = d.car_id
                cross join lateral (values ('road_tax', d.road_tax_expiry), ('insurance', d.insurance_expiry)) as x(kind, due)
                where c.owner_id = p.id and x.due between v_today and v_today + 7),
      'doc_pinged_today', exists (select 1 from public.notifications n
                                   where n.user_id = p.id and n.type::text = 'car_doc' and n.created_at >= v_midnight),
      'boxes', (select coalesce(jsonb_agg(b.id order by b.created_at), '[]'::jsonb)
                  from public.card_boxes b where b.user_id = p.id and b.status = 'sealed'),
      'week_key', v_week,
      'post_done', exists (select 1 from public.point_ledger l where l.idem_key = 'weekly_post:' || p.id || ':' || v_week),

      -- Meets / TT near them later today that they haven't joined.
      'nearby', (select coalesce(jsonb_agg(to_jsonb(z) order by z.starts_at), '[]'::jsonb) from (
                   select e.id, e.title, e.event_type::text as type, e.venue_name as venue, e.starts_at,
                          round((public.metres_between(loc.lat, loc.lng, e.lat, e.lng) / 1000)::numeric, 1) as km,
                          (select count(*) from public.event_attendees a where a.event_id = e.id) as going
                     from public.events e
                    where loc.lat is not null
                      and e.status = 'active'
                      and e.starts_at > now()
                      and (e.starts_at at time zone 'Asia/Kuala_Lumpur')::date = v_today
                      and e.organizer_id <> p.id
                      and abs(e.lat - loc.lat) < 0.2 and abs(e.lng - loc.lng) < 0.2
                      and public.metres_between(loc.lat, loc.lng, e.lat, e.lng) <= v_near
                      and not exists (select 1 from public.event_attendees a where a.event_id = e.id and a.user_id = p.id)
                      and not exists (select 1 from public.event_bookmarks b where b.event_id = e.id and b.user_id = p.id)
                      and (e.visibility = 'public' or public.is_friend(e.organizer_id, p.id)
                           or (e.club_id is not null and exists (select 1 from public.club_members cm where cm.club_id = e.club_id and cm.user_id = p.id)))
                    order by e.starts_at limit 3) z),

      -- Meets happening right now near them, with how many have checked in.
      'live', (select coalesce(jsonb_agg(to_jsonb(z) order by z.here desc, z.km), '[]'::jsonb) from (
                 select e.id, e.title, e.event_type::text as type, e.venue_name as venue,
                        round((public.metres_between(loc.lat, loc.lng, e.lat, e.lng) / 1000)::numeric, 1) as km,
                        (select count(distinct c.user_id) from public.checkins c where c.event_id = e.id) as here
                   from public.events e
                  where loc.lat is not null
                    and e.status = 'active'
                    and e.starts_at <= now() and e.starts_at > now() - interval '12 hours'
                    and now() < coalesce(e.ends_at, e.starts_at + interval '4 hours')
                    and abs(e.lat - loc.lat) < 0.2 and abs(e.lng - loc.lng) < 0.2
                    and public.metres_between(loc.lat, loc.lng, e.lat, e.lng) <= v_near
                    and not exists (select 1 from public.checkins c where c.event_id = e.id and c.user_id = p.id)
                    and (e.visibility = 'public' or e.organizer_id = p.id or public.is_friend(e.organizer_id, p.id)
                         or (e.club_id is not null and exists (select 1 from public.club_members cm where cm.club_id = e.club_id and cm.user_id = p.id)))
                  order by here desc limit 3) z),

      -- Friends out right now: checked in to a meet that's on, or at a spot /
      -- meet on the map in the last 45 minutes (not on Nobody).
      'friends_out', (select jsonb_build_object('count', count(*),
                                                'names', coalesce((jsonb_agg(f.first) filter (where f.rn <= 2)), '[]'::jsonb))
                        from (select fid, split_part(coalesce(nullif(btrim(fp.display_name), ''), fp.username::text), ' ', 1) as first,
                                     row_number() over (order by fid) as rn
                                from public.friend_ids(p.id) fid
                                join public.profiles fp on fp.id = fid
                               where fp.suspended_at is null
                                 and (exists (select 1 from public.checkins c join public.events e on e.id = c.event_id
                                               where c.user_id = fid and e.status = 'active'
                                                 and e.starts_at <= now() and e.starts_at > now() - interval '12 hours'
                                                 and now() < coalesce(e.ends_at, e.starts_at + interval '4 hours'))
                                   or exists (select 1 from public.user_locations l
                                               where l.user_id = fid and not l.ghost and l.share_mode <> 'ghost'
                                                 and l.updated_at > now() - interval '45 minutes'
                                                 and (l.place_id is not null or l.event_id is not null)))) f),

      -- The busiest spot near them today: different members checked in there
      -- today, plus members going to meets there today. At least 3.
      'busy', (select to_jsonb(z) from (select * from (
                 select pl.id, pl.name,
                        round((public.metres_between(loc.lat, loc.lng, pl.lat, pl.lng) / 1000)::numeric, 1) as km,
                        (select count(distinct pc.user_id) from public.place_checkins pc where pc.place_id = pl.id and pc.day = v_today) as checkins,
                        (select count(*) from public.event_attendees a join public.events e on e.id = a.event_id
                          where e.place_id = pl.id and e.status = 'active' and e.visibility = 'public'
                            and (e.starts_at at time zone 'Asia/Kuala_Lumpur')::date = v_today) as going
                   from public.places pl
                  where loc.lat is not null
                    and abs(pl.lat - loc.lat) < 0.2 and abs(pl.lng - loc.lng) < 0.2
                    and public.metres_between(loc.lat, loc.lng, pl.lat, pl.lng) <= v_near) s
                where s.checkins + s.going >= 3
                order by s.checkins + s.going desc, s.km
                limit 1) z),

      -- This week so far (since Friday 6 PM): check-ins at meets and spots, points earned.
      'week', jsonb_build_object(
                'checkins', (select count(*) from public.checkins c where c.user_id = p.id and c.checked_in_at >= v_week_start)
                          + (select count(*) from public.place_checkins pc where pc.user_id = p.id and pc.checked_in_at >= v_week_start),
                'points', (select coalesce(sum(l.delta), 0) from public.point_ledger l
                            where l.user_id = p.id and l.delta > 0 and l.created_at >= v_week_start)),

      'sent_today', (select coalesce(jsonb_agg(jsonb_build_object('slot', n.slot, 'trigger', n.trigger, 'sent_at', n.sent_at) order by n.sent_at), '[]'::jsonb)
                       from public.titi_nudges n where n.user_id = p.id and n.day = v_today),
      'nudges', (select coalesce(jsonb_agg(jsonb_build_object('trigger', n.trigger, 'ref', n.ref, 'sent_at', n.sent_at, 'text', n.text)
                         order by n.sent_at desc), '[]'::jsonb)
                   from public.titi_nudges n where n.user_id = p.id and n.sent_at > now() - interval '30 days')
    ))
    from public.profiles p
    left join lateral (select l.lat, l.lng from public.user_locations l
                        where l.user_id = p.id and l.updated_at > now() - interval '30 days') loc on true
    where p.id = any (p_users)
  ), '{}'::jsonb);
end;
$$;
revoke execute on function public.titi_nudge_context(uuid[]) from public, anon, authenticated;
grant execute on function public.titi_nudge_context(uuid[]) to service_role;

-- ---------------------------------------------------------------- cron ---

-- Posts {} to the function (longer timeout: bigger batches). Never raises.
create or replace function public.titi_nudge_post() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
  v_url text;
begin
  if coalesce((select value #>> '{}' from public.platform_settings where key = 'titi_nudges_enabled'), 'false') not in ('true', '1', 'on') then
    return;
  end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'titi_nudge_secret';
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'titi_nudge_url';
  if v_secret is null or v_url is null then
    raise warning 'titi_nudge_post: titi_nudge_secret / titi_nudge_url not set';
    return;
  end if;
  perform net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-titi-secret', v_secret),
    timeout_milliseconds := 150000
  );
exception when others then
  raise warning 'titi_nudge_post: %', sqlerrm;
end;
$$;
revoke execute on function public.titi_nudge_post() from public, anon, authenticated;

-- Every 30 minutes from 08:00 to 22:30 Malaysia time (00:00-14:30 UTC).
do $outer$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'ttspot-titi-nudges';
    perform cron.schedule('ttspot-titi-nudges', '0,30 0-14 * * *', 'select public.titi_nudge_post()');
  else
    raise notice 'pg_cron not available: run titi_nudge_post() every 30 minutes some other way';
  end if;
end;
$outer$;
