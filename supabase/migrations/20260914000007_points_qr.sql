-- =============================================================================
-- Points + QR (phase 1)
--   point_ledger (append-only) · award_points() · earn rules wired to check-ins,
--   spot check-ins, Car of the Week · referrals (username = referral code) ·
--   friend QR tokens · rotating meet check-in QR (HMAC, 30 s windows)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- points ledger
-- -----------------------------------------------------------------------------
create table public.point_ledger (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  delta       int not null check (delta <> 0),
  reason      text not null,           -- meet_checkin | spot_checkin | referral_referrer | referral_referee | car_of_week | badge | admin | redeem …
  ref_type    text,                    -- event | place | user | post | voucher …
  ref_id      text,
  note        text,
  idem_key    text unique,             -- stops double awards (e.g. 'meet_checkin:<event>:<user>')
  created_at  timestamptz not null default now()
);
create index point_ledger_user_idx on public.point_ledger (user_id, created_at desc);

alter table public.point_ledger enable row level security;
create policy "point_ledger: read own" on public.point_ledger for select to authenticated using (user_id = auth.uid());
-- writes only through award_points() (security definer)

alter table public.profiles add column points int not null default 0;

-- Idempotent award. Returns true when a row was written.
create or replace function public.award_points(
  p_user uuid, p_delta int, p_reason text,
  p_ref_type text default null, p_ref_id text default null, p_note text default null, p_key text default null
) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_delta = 0 then return false; end if;
  insert into public.point_ledger (user_id, delta, reason, ref_type, ref_id, note, idem_key)
  values (p_user, p_delta, p_reason, p_ref_type, p_ref_id, p_note, p_key)
  on conflict (idem_key) do nothing;
  if not found then return false; end if;
  update public.profiles set points = points + p_delta where id = p_user;
  return true;
end;
$$;

-- What each action is worth. One place to tune.
create table public.point_rules (
  reason      text primary key,
  points      int not null,
  label       text not null,
  description text not null,
  sort        int not null default 100
);
insert into public.point_rules (reason, points, label, description, sort) values
  ('meet_checkin',      30,  'Check in at a meet',        'Scan the organiser''s QR or be within 500 m while it''s live.', 10),
  ('spot_checkin',      20,  'Check in at a spot',        'Within 300 m of a spot. Once per spot per day.',               20),
  ('spot_verified',     50,  'Verified spot check-in',    'Scan the spot sticker and post a photo of your car there.',    25),
  ('referral_referrer', 100, 'Bring a friend',            'They sign up with your code and do their first check-in.',     30),
  ('referral_referee',  50,  'Join with a code',          'Enter a friend''s username when you sign up.',                 40),
  ('car_of_week',       500, 'Car of the Week',           'Most-liked car post of the week.',                             50),
  ('badge',             25,  'Earn a badge',              'Every badge you unlock.',                                      60);

alter table public.point_rules enable row level security;
create policy "point_rules: read" on public.point_rules for select to authenticated using (true);

create or replace function public.rule_points(p_reason text) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select points from public.point_rules where reason = p_reason), 0);
$$;

-- -----------------------------------------------------------------------------
-- referrals: your username is your code
-- -----------------------------------------------------------------------------
create table public.referrals (
  referee_id   uuid primary key references public.profiles (id) on delete cascade,
  referrer_id  uuid not null references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now(),
  rewarded_at  timestamptz,
  constraint no_self_referral check (referee_id <> referrer_id)
);
create index referrals_referrer_idx on public.referrals (referrer_id);
alter table public.referrals enable row level security;
create policy "referrals: read own" on public.referrals for select to authenticated
  using (referee_id = auth.uid() or referrer_id = auth.uid());

-- Called once during onboarding (or from a scanned friend QR). Silently ignores bad codes.
create or replace function public.claim_referral(p_code text) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  ref_id uuid;
begin
  if me is null then return false; end if;
  if exists (select 1 from public.referrals where referee_id = me) then return false; end if;
  -- only brand-new members can be referred (no check-ins yet)
  if exists (select 1 from public.checkins where user_id = me)
     or exists (select 1 from public.place_checkins where user_id = me) then return false; end if;
  select id into ref_id from public.profiles where username = lower(trim(p_code));
  if ref_id is null or ref_id = me then return false; end if;
  insert into public.referrals (referee_id, referrer_id) values (me, ref_id);
  return true;
end;
$$;

-- Pay the referral out on the referee's first real check-in.
create or replace function public.settle_referral(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.referrals;
begin
  select * into r from public.referrals where referee_id = p_user and rewarded_at is null;
  if not found then return; end if;
  update public.referrals set rewarded_at = now() where referee_id = p_user;
  perform public.award_points(r.referrer_id, public.rule_points('referral_referrer'), 'referral_referrer', 'user', p_user::text, null, 'referral_referrer:' || p_user);
  perform public.award_points(p_user, public.rule_points('referral_referee'), 'referral_referee', 'user', r.referrer_id::text, null, 'referral_referee:' || p_user);
  perform public.notify(r.referrer_id, p_user, 'referral', p_body => public.rule_points('referral_referrer')::text);
end;
$$;

-- -----------------------------------------------------------------------------
-- earn hooks
-- -----------------------------------------------------------------------------
create or replace function public.on_checkin_points() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.award_points(new.user_id, public.rule_points('meet_checkin'), 'meet_checkin', 'event', new.event_id::text, null, 'meet_checkin:' || new.event_id || ':' || new.user_id);
  perform public.settle_referral(new.user_id);
  return new;
end; $$;
create trigger checkins_after_insert_points after insert on public.checkins
  for each row execute function public.on_checkin_points();

create or replace function public.on_place_checkin_points() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.award_points(new.user_id, public.rule_points('spot_checkin'), 'spot_checkin', 'place', new.place_id::text, null, 'spot_checkin:' || new.place_id || ':' || new.user_id || ':' || new.day);
  perform public.settle_referral(new.user_id);
  return new;
end; $$;
create trigger place_checkins_after_insert_points after insert on public.place_checkins
  for each row execute function public.on_place_checkin_points();

create or replace function public.on_badge_points() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.award_points(new.user_id, public.rule_points('badge'), 'badge', 'badge', new.badge_id, null, 'badge:' || new.badge_id || ':' || new.user_id);
  return new;
end; $$;
create trigger user_badges_after_insert_points after insert on public.user_badges
  for each row execute function public.on_badge_points();

create or replace function public.on_weekly_winner_points() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.user_id is not null then
    perform public.award_points(new.user_id, public.rule_points('car_of_week'), 'car_of_week', 'post', new.post_id::text, null, 'car_of_week:' || new.week_start);
  end if;
  return new;
end; $$;
create trigger weekly_winners_after_insert_points after insert on public.weekly_winners
  for each row execute function public.on_weekly_winner_points();

-- -----------------------------------------------------------------------------
-- friend QR: a rotating token so a photo of your QR can't be replayed forever
-- -----------------------------------------------------------------------------
alter table public.profiles add column qr_token text not null default encode(extensions.gen_random_bytes(9), 'base64');

create or replace function public.my_qr_payload() returns text
language sql stable security definer set search_path = public as $$
  select 'https://ttspot.my/u/' || username || '?t=' || replace(replace(replace(qr_token, '+', '-'), '/', '_'), '=', '')
  from public.profiles where id = auth.uid();
$$;

create or replace function public.rotate_my_qr() returns void
language sql security definer set search_path = public as $$
  update public.profiles set qr_token = encode(extensions.gen_random_bytes(9), 'base64') where id = auth.uid();
$$;

-- Scan → instant friends (both people are physically present). Returns the friend's id.
create or replace function public.add_friend_by_qr(p_username text, p_token text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  other public.profiles;
begin
  if me is null then raise exception 'Not signed in'; end if;
  select * into other from public.profiles where username = lower(trim(p_username));
  if not found then raise exception 'That QR code doesn''t belong to anyone'; end if;
  if replace(replace(replace(other.qr_token, '+', '-'), '/', '_'), '=', '') <> p_token then
    raise exception 'This QR code has expired. Ask them to show it again.';
  end if;
  if other.id = me then raise exception 'That''s your own code'; end if;
  if exists (select 1 from public.blocks b where (b.blocker_id = me and b.blocked_id = other.id) or (b.blocker_id = other.id and b.blocked_id = me)) then
    raise exception 'You cannot add this user';
  end if;
  insert into public.friendships (requester_id, addressee_id, status, accepted_at)
  values (me, other.id, 'accepted', now())
  on conflict (least(requester_id, addressee_id), greatest(requester_id, addressee_id))
  do update set status = 'accepted', accepted_at = coalesce(public.friendships.accepted_at, now());
  perform public.notify(other.id, me, 'friend_accepted');
  -- a brand-new member scanning a friend's code counts as a referral
  perform public.claim_referral(other.username);
  return other.id;
end;
$$;

-- -----------------------------------------------------------------------------
-- meet check-in QR: HMAC(event secret, 30-second window), shown by the organiser
-- -----------------------------------------------------------------------------
alter table public.events add column qr_secret text not null default encode(extensions.gen_random_bytes(16), 'hex');

create or replace function public.event_qr_code_at(p_event uuid, p_window bigint) returns text
language sql stable security definer set search_path = public as $$
  select substr(encode(extensions.hmac(p_window::text, e.qr_secret, 'sha256'), 'hex'), 1, 10)
  from public.events e where e.id = p_event;
$$;

-- Organiser fetches this every ~25 s. Payload: ttspot://checkin/<event>/<code>
create or replace function public.event_qr_payload(p_event uuid) returns text
language plpgsql security definer set search_path = public as $$
declare e public.events;
begin
  select * into e from public.events where id = p_event;
  if not found then raise exception 'No such meet'; end if;
  if e.organizer_id <> auth.uid() then raise exception 'Only the organiser can show the check-in code'; end if;
  return 'ttspot://checkin/' || p_event || '/' || public.event_qr_code_at(p_event, floor(extract(epoch from now()) / 30)::bigint);
end;
$$;

-- Attendee scans it. Accepts the current and previous window (clock drift).
create or replace function public.checkin_by_qr(p_event uuid, p_code text, p_lat float8 default null, p_lng float8 default null) returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  w bigint := floor(extract(epoch from now()) / 30)::bigint;
  already boolean;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_code is null or (p_code <> public.event_qr_code_at(p_event, w) and p_code <> public.event_qr_code_at(p_event, w - 1)) then
    raise exception 'That code has expired. Scan the organiser''s screen again.';
  end if;
  select exists (select 1 from public.checkins where event_id = p_event and user_id = me) into already;
  if not already then
    insert into public.checkins (event_id, user_id, lat, lng, source) values (p_event, me, p_lat, p_lng, 'qr');
  end if;
  return json_build_object('new', not already, 'points', public.rule_points('meet_checkin'));
end;
$$;

-- 'qr' is a proof of presence on its own: skip the distance rule for it
alter table public.checkins drop constraint checkins_source_check;
alter table public.checkins add constraint checkins_source_check check (source in ('manual', 'auto', 'organizer', 'qr'));

create or replace function public.on_checkin_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e public.events;
  w record;
begin
  select * into e from public.events where id = new.event_id;
  if e.status <> 'active' then raise exception 'This meet was cancelled'; end if;
  select * into w from public.event_live_window(new.event_id);
  if now() < w.opens_at or now() > w.closes_at then
    raise exception 'Check-in only works around the meet time';
  end if;
  if new.source not in ('organizer', 'qr') then
    if new.lat is null or new.lng is null then raise exception 'Turn on location to check in'; end if;
    if public.metres_between(new.lat, new.lng, e.lat, e.lng) > 500 then
      raise exception 'You are too far from the meet to check in';
    end if;
  end if;
  return new;
end; $$;

-- -----------------------------------------------------------------------------
-- history for the Points screen
-- -----------------------------------------------------------------------------
create or replace function public.my_point_history(p_limit int default 100)
returns table (id bigint, delta int, reason text, ref_type text, ref_id text, note text, created_at timestamptz, label text)
language sql stable security definer set search_path = public as $$
  select l.id, l.delta, l.reason, l.ref_type, l.ref_id, l.note, l.created_at, coalesce(r.label, l.reason)
  from public.point_ledger l left join public.point_rules r on r.reason = l.reason
  where l.user_id = auth.uid()
  order by l.created_at desc
  limit p_limit;
$$;
