-- =============================================================================
-- 0108 · Points restructure and four-tier badges (0.3.55).
--
-- POINTS (point_rules; retired rules keep their rows and labels for history)
--   meet_checkin       +10  once per meet (unchanged key)
--   spot_checkin       +10  a spot or a partner shop (its place), once per
--                           spot per points week. A second check-in in the
--                           same week is still recorded (meets, albums, the
--                           spot's counts) and earns 0; checkin_place() says
--                           when that spot pays again.
--   weekly_post        +10  the first post of the week that passes the photo
--                           check (moderation 'ok'); replaces first_post.
--   referral_referrer   +5  bring a friend (still paid at their first check-in)
--   referral_referee    +5  join with a code (same moment)
--   badge              +10  every new badge tier, bronze included
--   Retired (points 0, active false): spot_verified, first_post, car_of_week,
--   spot_suggested. Spends (box, portrait, redeem, ...) and freepoints stay.
--   club_president_bonus (10 % of a member's meet check-in, official clubs,
--   a paid perk) is left as it is: now 1 point a check-in.
--
-- POINTS WEEK: Friday 18:00 Malaysia time to the next Friday 18:00. The rule
--   lives in ONE helper, points_week_start(ts); points_next_reset() and
--   points_week_key() are built on it, and every weekly limit uses them.
--
-- BADGES: five badges, four tiers (1 bronze, 2 silver, 3 platinum, 4 gold).
--   posts      posts that passed the photo check (not as a club / partner)   1/10/20/50
--   organizer  meets hosted or co-hosted, any type, started, not cancelled   1/10/20/50
--   joiner     meets joined or checked in at, started, not cancelled, not
--              hosted / co-hosted by them                                   1/20/50/100
--   explorer   distinct places checked in: spots, partner shops (their
--              place) and meets (the meet's place), not TT sessions         1/10/20/50
--   popular    followers                                                    1/50/100/200
--   Tiers live in badge_tiers (one row per member per badge, tier >= 1).
--   recompute_badges() derives them from the counts; it is called by triggers
--   on posts, follows, place_checkins, checkins, event_attendees, event_crew
--   and events, by a 10-minute sweep for meets that just started, and when a
--   member opens their badges page. A tier never goes down. Each new tier pays
--   +10 once (ledger key badge_tier:<badge>:<tier>:<user>) and drops one
--   'badge' Activity row (body = the tier). The old one-shot badges are
--   retired: award_badge() is a no-op and RLS hides them from members.
--   Backfill at the end: everyone's current tiers, no points, no Activity.
--
-- Profile honour row: up to 3 medallions. profiles.settings.honour_badges
--   (set_honour_badges) or, when never chosen, the 3 most recent tiers
--   (honour_badges()).
-- =============================================================================

-- --------------------------------------------------------- points week ---
create or replace function public.points_week_start(p_ts timestamptz default now())
returns timestamptz
language sql stable set search_path = public as $$
  -- Shift Malaysia local time back 18 h so the week starts at Friday 00:00,
  -- step back to that Friday, then add the 18 h again.
  select ((date_trunc('day', s) - make_interval(days => (extract(isodow from s)::int + 2) % 7) + interval '18 hours')
          at time zone 'Asia/Kuala_Lumpur')
    from (select (p_ts at time zone 'Asia/Kuala_Lumpur') - interval '18 hours' as s) x;
$$;

-- When the weekly limits reset next (Malaysia has no daylight saving).
create or replace function public.points_next_reset(p_ts timestamptz default now())
returns timestamptz
language sql stable set search_path = public as $$
  select public.points_week_start(p_ts) + interval '7 days';
$$;

-- '2026-10-02': the Friday the points week of [p_ts] started on, for ledger keys.
create or replace function public.points_week_key(p_ts timestamptz default now())
returns text
language sql stable set search_path = public as $$
  select to_char(public.points_week_start(p_ts) at time zone 'Asia/Kuala_Lumpur', 'YYYY-MM-DD');
$$;

grant execute on function public.points_week_start(timestamptz) to authenticated;
grant execute on function public.points_next_reset(timestamptz) to authenticated;
grant execute on function public.points_week_key(timestamptz) to authenticated;

-- --------------------------------------------------------- point rules ---
alter table public.point_rules add column if not exists active boolean not null default true;
alter table public.point_rules add column if not exists limit_note text;

update public.point_rules set points = 10, sort = 10, label = 'Check in at a meet',
       description = 'Scan the host''s QR or tap I''m here while the meet is on. Once per meet.',
       limit_note = 'Once per meet', active = true
 where reason = 'meet_checkin';
update public.point_rules set points = 10, sort = 20, label = 'Check in at a spot or partner shop',
       description = 'Within 300 m of any spot or partner shop. Once per spot per week (resets Friday 6 PM).',
       limit_note = 'Once per spot per week', active = true
 where reason = 'spot_checkin';
insert into public.point_rules (reason, points, label, description, sort, limit_note, active) values
  ('weekly_post', 10, 'Share a post', 'Your first post of the week that passes the photo check. Resets Friday 6 PM.', 30, '1 post a week', true)
on conflict (reason) do update set points = excluded.points, label = excluded.label, description = excluded.description,
  sort = excluded.sort, limit_note = excluded.limit_note, active = true;
update public.point_rules set points = 5, sort = 40, label = 'Bring a friend',
       description = 'They join with your code. Paid when they do their first check-in.',
       limit_note = 'When they do their first check-in', active = true
 where reason = 'referral_referrer';
update public.point_rules set points = 5, sort = 45, label = 'Join with a code',
       description = 'Enter a friend''s code when you sign up. Paid at your first check-in.',
       limit_note = 'Paid at your first check-in', active = true
 where reason = 'referral_referee';
update public.point_rules set points = 10, sort = 50, label = 'Earn a badge',
       description = 'Every new badge, and every step up a tier.',
       limit_note = 'Each new tier counts', active = true
 where reason = 'badge';
-- Retired earning rules: kept for the history labels, never pay again.
update public.point_rules set points = 0, active = false where reason in ('spot_verified', 'first_post', 'car_of_week');
insert into public.point_rules (reason, points, label, description, sort, active) values
  ('spot_suggested', 0, 'Spot added', 'A spot you suggested went live.', 70, false),
  ('club_president_bonus', 0, 'Club meet bonus', 'A member checked in at your official club''s meet.', 75, true)
on conflict (reason) do nothing;

-- Inactive rules pay nothing, whatever their points say.
create or replace function public.rule_points(p_reason text)
returns integer
language sql stable security definer set search_path = public as $$
  select coalesce((select points from public.point_rules where reason = p_reason and active), 0);
$$;

-- ---------------------------------------------- spot check-in, weekly ---
-- Once per spot per points week. The ledger check also covers a spot paid
-- earlier this week under the old per-day key.
create or replace function public.on_place_checkin_points() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_week timestamptz := public.points_week_start(new.checked_in_at);
begin
  if not exists (
    select 1 from public.point_ledger l
     where l.user_id = new.user_id and l.reason = 'spot_checkin'
       and l.ref_id = new.place_id::text
       and l.created_at >= v_week and l.created_at < v_week + interval '7 days'
  ) then
    perform public.award_points(new.user_id, public.rule_points('spot_checkin'), 'spot_checkin', 'place', new.place_id::text,
      (select name from public.places where id = new.place_id),
      'spot_checkin:' || new.place_id || ':' || new.user_id || ':w' || public.points_week_key(new.checked_in_at));
  end if;
  perform public.settle_referral(new.user_id);
  return new;
end; $$;

-- As before, plus what this check-in paid and, when it paid nothing, when
-- this spot pays again ({new, total, points, points_again_at}).
create or replace function public.checkin_place(p_place uuid, p_lat double precision, p_lng double precision)
returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  pl public.places;
  d  float8;
  total int;
  today boolean;
  v_pts int := 0;
begin
  if me is null then raise exception 'Not signed in'; end if;
  select * into pl from public.places where id = p_place;
  if not found then raise exception 'This spot no longer exists'; end if;
  if p_lat is null or p_lng is null then raise exception 'Turn on location to check in'; end if;
  d := public.metres_between(p_lat, p_lng, pl.lat, pl.lng);
  if d > 300 then
    raise exception 'You are % m away. Get closer to check in.', round(d)::int;
  end if;
  insert into public.place_checkins (place_id, user_id, lat, lng) values (p_place, me, p_lat, p_lng)
  on conflict (place_id, user_id, day) do nothing;
  today := found;
  select count(*)::int into total from public.place_checkins where place_id = p_place;
  if today then
    -- the insert trigger paid it inside this transaction (same now())
    select coalesce(sum(l.delta), 0)::int into v_pts from public.point_ledger l
     where l.user_id = me and l.reason = 'spot_checkin' and l.ref_id = p_place::text and l.created_at = now();
  end if;
  return json_build_object('new', today, 'total', total, 'points', v_pts,
    'points_again_at', case when v_pts = 0 then public.points_next_reset(now()) end);
end;
$$;

-- ------------------------------------------------- weekly post (+10) ---
-- The first personal post of each points week (by created_at) that passes the
-- photo check. Club / partner posts don't count. A silent Activity row says
-- so (no push).
create or replace function public.on_post_points() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_pts int := public.rule_points('weekly_post');
begin
  if new.as_club or new.as_vendor then return null; end if;
  if v_pts > 0 and public.award_points(new.author_id, v_pts, 'weekly_post', 'post', new.id::text, null,
       'weekly_post:' || new.author_id || ':' || public.points_week_key(new.created_at)) then
    insert into public.notifications (user_id, type, post_id, body, silent)
    values (new.author_id, 'points', new.id, '+' || v_pts || ' · your post this week', true);
  end if;
  return null;
end;
$$;

drop trigger if exists posts_first_post_points on public.posts;
drop trigger if exists posts_points on public.posts;
create trigger posts_points after insert or update of moderation on public.posts
  for each row when (new.moderation = 'ok') execute function public.on_post_points();
drop function if exists public.on_post_first_points();

-- ------------------------------------------- retired one-shot payouts ---
-- Sticker check-ins: the +50 bonus is gone (the check-in itself still pays
-- through the moment it posts at the spot). The note no longer says "+0".
create or replace function public.decide_spot_verification(p_id uuid, p_approve boolean, p_reason text, p_by uuid, p_ai jsonb default null::jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v public.spot_verifications;
  pl public.places;
  s_id uuid;
  pts int := public.rule_points('spot_verified');
begin
  select * into v from public.spot_verifications where id = p_id for update;
  if not found then raise exception 'No such verification'; end if;
  if v.status in ('approved', 'rejected') then return; end if;
  select * into pl from public.places where id = v.place_id;

  if p_approve then
    insert into public.stories (author_id, photo_url, caption, lat, lng, place_id)
    values (v.user_id, v.photo_url, 'Verified check-in', coalesce(v.lat, pl.lat), coalesce(v.lng, pl.lng), v.place_id)
    returning id into s_id;
    perform public.award_points(v.user_id, pts, 'spot_verified', 'place', v.place_id::text, pl.name,
      'spot_verified:' || v.place_id || ':' || v.user_id || ':' || v.day);
    update public.spot_verifications
      set status = 'approved', reason = p_reason, decided_at = now(), decided_by = p_by, story_id = s_id,
          ai_result = coalesce(p_ai, ai_result)
      where id = p_id;
    perform public.notify(v.user_id, null, 'points', p_body =>
      case when pts > 0 then '+' || pts || ' · verified check-in at ' || pl.name else 'Verified check-in at ' || pl.name end);
  else
    update public.spot_verifications
      set status = 'rejected', reason = p_reason, decided_at = now(), decided_by = p_by, ai_result = coalesce(p_ai, ai_result)
      where id = p_id;
    perform public.notify(v.user_id, null, 'points', p_body => 'Check-in at ' || pl.name || ' not approved: ' || coalesce(p_reason, 'no reason given'));
  end if;
end;
$$;

-- Suggested spots: the 30 points were hard-coded; now a (retired) rule.
create or replace function public.admin_review_suggestion(p_id uuid, p_approve boolean, p_kind text default null::text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare s public.place_suggestions; v_place uuid;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select * into s from public.place_suggestions where id = p_id and status = 'pending';
  if not found then raise exception 'Already reviewed'; end if;
  if not p_approve then
    update public.place_suggestions set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
    return null;
  end if;
  select id into v_place from public.places p
  where abs(p.lat - s.lat) < 0.0015 and abs(p.lng - s.lng) < 0.0015 and lower(p.name) = lower(s.name) limit 1;
  if v_place is null then
    insert into public.places (name, kind, lat, lng, created_by, cover_url, description)
    values (s.name, coalesce(p_kind, s.kind, 'other'), s.lat, s.lng, s.user_id, s.photo_url, s.note)
    returning id into v_place;
  else
    update public.places set cover_url = coalesce(cover_url, s.photo_url), kind = coalesce(p_kind, kind) where id = v_place;
  end if;
  update public.place_suggestions set status = 'approved', place_id = v_place, reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  begin
    perform public.award_points(s.user_id, public.rule_points('spot_suggested'), 'spot_suggested', 'place', v_place::text, 'Spot added: ' || s.name);
  exception when others then null; -- points are a bonus, never a blocker
  end;
  return v_place;
end;
$$;

-- Old one-shot badges (Garage Open, First Meet, Regular, ...) are retired.
-- Every old caller (cars, checkins, events, follows, posts, Car of the Week,
-- checkin_place) goes through here, so they all stop at once.
create or replace function public.award_badge(p_user uuid, p_badge text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  return false; -- 0108: badges are tiered now (badge_tiers / recompute_badges)
end;
$$;
drop trigger if exists user_badges_after_insert_points on public.user_badges;

-- --------------------------------------------------------------- badges ---
alter table public.badges add column if not exists active boolean not null default true;
alter table public.badges add column if not exists unit text;
alter table public.badges add column if not exists thresholds int[];

update public.badges set active = false where id not in ('posts', 'organizer', 'joiner', 'explorer', 'popular');
insert into public.badges (id, name, description, emoji, sort, unit, thresholds, active) values
  ('posts', 'Posts', 'Posts you shared that passed the photo check.', '📸', 1, 'posts', '{1,10,20,50}', true),
  ('organizer', 'Car meet organizer', 'Meets you hosted or co-hosted, any type, once they start.', '📣', 2, 'meets organized', '{1,10,20,50}', true),
  ('joiner', 'Car meet joining', 'Meets you joined or checked in at, once they start. Not the ones you host.', '🏁', 3, 'meets joined', '{1,20,50,100}', true),
  ('explorer', 'Explorer', 'Different spots, partner shops and meets you checked in at. TT sessions don''t count.', '🧭', 4, 'places', '{1,10,20,50}', true),
  ('popular', 'Popular', 'People who follow you.', '⭐', 5, 'followers', '{1,50,100,200}', true)
on conflict (id) do update set name = excluded.name, description = excluded.description, emoji = excluded.emoji,
  sort = excluded.sort, unit = excluded.unit, thresholds = excluded.thresholds, active = true;

-- Members only ever see the five; old user_badges rows stay in the table.
drop policy if exists "badges: read" on public.badges;
create policy "badges: read" on public.badges for select to authenticated using (active);
drop policy if exists "user_badges: read" on public.user_badges;
create policy "user_badges: read" on public.user_badges for select to authenticated
  using (exists (select 1 from public.badges b where b.id = badge_id and b.active));

create table if not exists public.badge_tiers (
  user_id          uuid not null references public.profiles (id) on delete cascade,
  badge_id         text not null references public.badges (id) on delete cascade,
  tier             smallint not null check (tier between 1 and 4),
  tier_reached_at  timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  primary key (user_id, badge_id)
);
create index if not exists badge_tiers_recent_idx on public.badge_tiers (user_id, tier_reached_at desc);
alter table public.badge_tiers enable row level security;
drop policy if exists "badge_tiers: read" on public.badge_tiers;
create policy "badge_tiers: read" on public.badge_tiers for select to authenticated using (true);
-- writes only through recompute_badges()

create or replace function public.badge_tier_name(p_tier int)
returns text
language sql immutable as $$
  select case p_tier when 1 then 'Bronze' when 2 then 'Silver' when 3 then 'Platinum' when 4 then 'Gold' end;
$$;

-- What a badge counts for a member, right now.
create or replace function public.badge_count(p_user uuid, p_badge text)
returns int
language plpgsql stable security definer set search_path = public as $$
declare n int := 0;
begin
  if p_badge = 'posts' then
    select count(*) into n from public.posts p
     where p.author_id = p_user and p.moderation = 'ok' and not p.as_club and not p.as_vendor;
  elsif p_badge = 'organizer' then
    select count(*) into n from public.events e
     where e.id in (select x.id from public.events x where x.organizer_id = p_user
                    union
                    select k.event_id from public.event_crew k where k.user_id = p_user and k.role = 'cohost')
       and e.status = 'active' and e.starts_at <= now();
  elsif p_badge = 'joiner' then
    select count(*) into n from public.events e
     where e.id in (select a.event_id from public.event_attendees a where a.user_id = p_user
                    union
                    select c.event_id from public.checkins c where c.user_id = p_user)
       and e.status = 'active' and e.starts_at <= now()
       and e.organizer_id <> p_user
       and not exists (select 1 from public.event_crew k where k.event_id = e.id and k.user_id = p_user and k.role = 'cohost');
  elsif p_badge = 'explorer' then
    select count(distinct x.k) into n from (
      select 'p' || pc.place_id::text as k from public.place_checkins pc where pc.user_id = p_user
      union
      select coalesce('p' || e.place_id::text, 'e' || e.id::text)
        from public.checkins c join public.events e on e.id = c.event_id
       where c.user_id = p_user and e.event_type <> 'tt'
    ) x;
  elsif p_badge = 'popular' then
    select count(*) into n from public.follows f where f.followee_id = p_user;
  end if;
  return coalesce(n, 0);
end;
$$;

-- Raise a member's tiers to what their counts reach ([p_only] = one badge).
-- Never lowers a tier. [p_pay]: +10 per new tier and one Activity row per
-- badge that moved (off for the backfill). Returns the tier steps gained.
create or replace function public.recompute_badges(p_user uuid, p_only text default null, p_pay boolean default true)
returns int
language plpgsql security definer set search_path = public as $$
declare
  b record;
  v_n int;
  v_old int;
  v_new int;
  v_gained int := 0;
  v_pts int := public.rule_points('badge');
begin
  if p_user is null then return 0; end if;
  for b in select id, name, thresholds from public.badges where active and thresholds is not null and (p_only is null or id = p_only) loop
    v_n := public.badge_count(p_user, b.id);
    select count(*) into v_new from unnest(b.thresholds) th where th <= v_n;
    if v_new = 0 then continue; end if;
    select tier into v_old from public.badge_tiers where user_id = p_user and badge_id = b.id;
    v_old := coalesce(v_old, 0);
    if v_new <= v_old then continue; end if;
    insert into public.badge_tiers as bt (user_id, badge_id, tier, tier_reached_at, updated_at)
    values (p_user, b.id, v_new, now(), now())
    on conflict (user_id, badge_id) do update
      set tier = excluded.tier, tier_reached_at = excluded.tier_reached_at, updated_at = excluded.updated_at
      where bt.tier < excluded.tier;
    if not found then continue; end if; -- another transaction got there first
    v_gained := v_gained + (v_new - v_old);
    if p_pay then
      for t in (v_old + 1) .. v_new loop
        perform public.award_points(p_user, v_pts, 'badge', 'badge', b.id || ':' || t,
          b.name || ' · ' || public.badge_tier_name(t), 'badge_tier:' || b.id || ':' || t || ':' || p_user);
      end loop;
      if not exists (select 1 from public.notifications n
                      where n.user_id = p_user and n.type = 'badge' and n.badge_id = b.id and n.body = v_new::text) then
        insert into public.notifications (user_id, type, badge_id, body) values (p_user, 'badge', b.id, v_new::text);
      end if;
    end if;
  end loop;
  return v_gained;
end;
$$;

-- Triggers: whatever moves a count. A badge must never block what earned it.
create or replace function public.on_badge_activity() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    case tg_table_name
      when 'posts' then
        perform public.recompute_badges(new.author_id, 'posts');
      when 'follows' then
        perform public.recompute_badges(new.followee_id, 'popular');
      when 'place_checkins' then
        perform public.recompute_badges(new.user_id, 'explorer');
      when 'checkins' then
        perform public.recompute_badges(new.user_id, 'explorer');
        perform public.recompute_badges(new.user_id, 'joiner');
      when 'event_attendees' then
        perform public.recompute_badges(new.user_id, 'joiner');
      when 'event_crew' then
        perform public.recompute_badges(new.user_id, 'organizer');
      when 'events' then
        perform public.recompute_badges(new.organizer_id, 'organizer');
      else null;
    end case;
  exception when others then
    raise warning 'badge recompute failed on %: %', tg_table_name, sqlerrm;
  end;
  return null;
end;
$$;

drop trigger if exists posts_badge_tiers on public.posts;
create trigger posts_badge_tiers after insert or update of moderation on public.posts
  for each row when (new.moderation = 'ok' and not new.as_club and not new.as_vendor) execute function public.on_badge_activity();
drop trigger if exists follows_badge_tiers on public.follows;
create trigger follows_badge_tiers after insert on public.follows
  for each row execute function public.on_badge_activity();
drop trigger if exists place_checkins_badge_tiers on public.place_checkins;
create trigger place_checkins_badge_tiers after insert on public.place_checkins
  for each row execute function public.on_badge_activity();
drop trigger if exists checkins_badge_tiers on public.checkins;
create trigger checkins_badge_tiers after insert on public.checkins
  for each row execute function public.on_badge_activity();
drop trigger if exists event_attendees_badge_tiers on public.event_attendees;
create trigger event_attendees_badge_tiers after insert on public.event_attendees
  for each row execute function public.on_badge_activity();
drop trigger if exists event_crew_badge_tiers on public.event_crew;
create trigger event_crew_badge_tiers after insert or update of role on public.event_crew
  for each row when (new.role = 'cohost') execute function public.on_badge_activity();
-- TT now starts at once; later meets are picked up by the sweep below.
drop trigger if exists events_badge_tiers on public.events;
create trigger events_badge_tiers after insert on public.events
  for each row when (new.starts_at <= now()) execute function public.on_badge_activity();

-- Meets count once they start: every 10 minutes, everyone at a meet that
-- started in the last hour (overlap is harmless: tiers only move up once).
create or replace function public.badge_tiers_sweep()
returns void
language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  for u in
    with started as (
      select e.id, e.organizer_id from public.events e
       where e.status = 'active' and e.starts_at <= now() and e.starts_at > now() - interval '1 hour'
    )
    select s.organizer_id from started s
    union select k.user_id from public.event_crew k join started s on s.id = k.event_id where k.role = 'cohost'
    union select a.user_id from public.event_attendees a join started s on s.id = a.event_id
    union select c.user_id from public.checkins c join started s on s.id = c.event_id
  loop
    begin
      perform public.recompute_badges(u, 'organizer');
      perform public.recompute_badges(u, 'joiner');
    exception when others then
      raise warning 'badge sweep failed for %: %', u, sqlerrm;
    end;
  end loop;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'ttspot-badge-tiers';
    perform cron.schedule('ttspot-badge-tiers', '*/10 * * * *', 'select public.badge_tiers_sweep()');
  else
    raise notice 'pg_cron not available: run badge_tiers_sweep() every 10 minutes some other way';
  end if;
end;
$$;

-- ------------------------------------------------------------ app RPCs ---
-- The profile's honour row: the member's pick (settings.honour_badges, up to
-- 3, in their order) or, when they never picked, their 3 latest tiers.
create or replace function public.honour_badges(p_user uuid)
returns table (badge_id text, name text, tier smallint, tier_reached_at timestamptz, chosen boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_pick text[];
begin
  select array(select jsonb_array_elements_text(p.settings -> 'honour_badges')) into v_pick
    from public.profiles p
   where p.id = p_user and jsonb_typeof(p.settings -> 'honour_badges') = 'array';
  if exists (select 1 from public.badge_tiers t join public.badges b on b.id = t.badge_id and b.active
              where t.user_id = p_user and t.badge_id = any (coalesce(v_pick, '{}'))) then
    return query
      select t.badge_id, b.name, t.tier, t.tier_reached_at, true
        from unnest(v_pick) with ordinality as k(id, ord)
        join public.badge_tiers t on t.user_id = p_user and t.badge_id = k.id
        join public.badges b on b.id = t.badge_id and b.active
       order by k.ord
       limit 3;
  else
    return query
      select t.badge_id, b.name, t.tier, t.tier_reached_at, false
        from public.badge_tiers t join public.badges b on b.id = t.badge_id and b.active
       where t.user_id = p_user
       order by t.tier_reached_at desc, b.sort
       limit 3;
  end if;
end;
$$;

-- Save my pick (badges I hold, up to 3, in order). Empty = back to automatic.
create or replace function public.set_honour_badges(p_ids text[])
returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v text[];
begin
  if me is null then raise exception 'Not signed in'; end if;
  select coalesce(array_agg(x.id order by x.ord), '{}') into v from (
    select distinct on (k.id) k.id, k.ord
      from unnest(coalesce(p_ids, '{}')) with ordinality as k(id, ord)
     where exists (select 1 from public.badge_tiers t join public.badges b on b.id = t.badge_id and b.active
                    where t.user_id = me and t.badge_id = k.id)
     order by k.id, k.ord
  ) x;
  if cardinality(v) > 3 then raise exception 'Pick up to 3 badges.'; end if;
  update public.profiles
     set settings = case when cardinality(v) = 0 then coalesce(settings, '{}'::jsonb) - 'honour_badges'
                         else coalesce(settings, '{}'::jsonb) || jsonb_build_object('honour_badges', to_jsonb(v)) end
   where id = me;
end;
$$;

-- The badges page: every badge with the member's tier, live count and
-- whether it is in their honour row. Opening my own page catches up my
-- tiers first (meets that started since the last sweep).
create or replace function public.badge_progress(p_user uuid default auth.uid())
returns table (badge_id text, name text, description text, unit text, thresholds int[], sort int,
               tier smallint, tier_reached_at timestamptz, progress int, on_profile boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  if p_user is null then return; end if;
  if p_user = auth.uid() then
    begin
      perform public.recompute_badges(p_user);
    exception when others then
      raise warning 'badge catch-up failed for %: %', p_user, sqlerrm;
    end;
  end if;
  return query
    select b.id, b.name, b.description, b.unit, b.thresholds, b.sort,
           coalesce(t.tier, 0)::smallint, t.tier_reached_at,
           public.badge_count(p_user, b.id),
           b.id in (select h.badge_id from public.honour_badges(p_user) h)
      from public.badges b
      left join public.badge_tiers t on t.user_id = p_user and t.badge_id = b.id
     where b.active and b.thresholds is not null
     order by b.sort;
end;
$$;

-- The points page: when the weekly limits reset, and whether this week's
-- post has paid yet.
create or replace function public.points_week_status()
returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'week_start', public.points_week_start(now()),
    'next_reset', public.points_next_reset(now()),
    'post_done', exists (select 1 from public.point_ledger l
                          where l.idem_key = 'weekly_post:' || auth.uid() || ':' || public.points_week_key(now()))
  );
$$;

revoke execute on function public.badge_count(uuid, text) from public, anon, authenticated;
revoke execute on function public.recompute_badges(uuid, text, boolean) from public, anon, authenticated;
revoke execute on function public.badge_tiers_sweep() from public, anon, authenticated;
revoke execute on function public.on_badge_activity() from public, anon, authenticated;
revoke execute on function public.on_post_points() from public, anon, authenticated;
revoke execute on function public.honour_badges(uuid) from public, anon;
revoke execute on function public.set_honour_badges(text[]) from public, anon;
revoke execute on function public.badge_progress(uuid) from public, anon;
revoke execute on function public.points_week_status() from public, anon;
grant execute on function public.honour_badges(uuid) to authenticated;
grant execute on function public.set_honour_badges(text[]) to authenticated;
grant execute on function public.badge_progress(uuid) to authenticated;
grant execute on function public.points_week_status() to authenticated;

-- ------------------------------------------------------------- backfill ---
-- Everyone's tiers from their history so far. No points, no Activity rows.
do $$
declare u uuid;
begin
  for u in select id from public.profiles loop
    perform public.recompute_badges(u, null, false);
  end loop;
end;
$$;
