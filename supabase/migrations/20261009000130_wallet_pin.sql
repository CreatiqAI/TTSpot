-- Wallet PIN: a 6-digit PIN that guards everything of value on an account
-- (cards, points, vouchers), so a hijacked session can't trade the cards
-- away or spend the points.
--
-- How it works
-- - The PIN lives bcrypt-hashed in profile_private.pin_hash. Clients can
--   never read it (column grants below).
-- - verify_wallet_pin() checks it and, when right, unlocks the wallet for 5
--   minutes (profile_private.pin_unlocked_until). 5 wrong tries lock it for
--   15 minutes. The counter only persists because verify returns json
--   instead of raising (a raise would roll the counter back).
-- - Every member value action calls public.require_wallet_unlocked() first.
--   It raises 'PIN_SETUP_REQUIRED' when the member has no PIN yet (so every
--   account gets one on its first value action) and 'PIN_REQUIRED' when the
--   wallet is locked. The app catches both, shows the PIN sheet, retries.
-- - Partner/staff actions are not guarded: redeem_voucher (counter scan),
--   redeem_card_reward_claim (staff scan), claim_prize (crew hands over).
--
-- Forgot PIN: reset_wallet_pin() only works right after a fresh sign-in.
-- The app re-signs in with the password (signInWithPassword, or the login
-- Edge Function for usernames) or, for Apple accounts, runs Sign in with
-- Apple again. Both make a brand-new auth session. The reset is accepted
-- only when auth.users.last_sign_in_at AND the calling session's
-- auth.sessions.created_at are both under 2 minutes old. Checking the
-- session (not just the user) matters: a stolen session stays old even if
-- the real owner signs in elsewhere at the same moment.

-- ------------------------------------------------------------ storage ---

alter table public.profile_private
  add column if not exists pin_hash text,
  add column if not exists pin_failed int not null default 0,
  add column if not exists pin_locked_until timestamptz,
  add column if not exists pin_set_at timestamptz,
  add column if not exists pin_unlocked_until timestamptz;

-- Members read their own row through these columns only; the pin_* columns
-- are server-side. Every write goes through security definer RPCs.
-- NOTE: a new profile_private column needs adding to this grant to be readable.
revoke all on public.profile_private from anon, authenticated;
grant select (user_id, phone, terms_accepted_at, terms_version, updated_at)
  on public.profile_private to authenticated;

-- ------------------------------------------------------------- rules ---

-- Too easy to guess: one digit repeated (111111), a pair or triple repeated
-- (121212, 123123), or a straight run up or down (123456, 654321). The app
-- mirrors this in lib/features/safety/domain/pin_rules.dart.
create or replace function public.wallet_pin_is_trivial(p text)
returns boolean language sql immutable set search_path = public as $$
  select p ~ '^(.)\1{5}$'
      or p ~ '^(..)\1\1$'
      or p ~ '^(...)\1$'
      or position(p in '0123456789') > 0
      or position(p in '9876543210') > 0;
$$;

create or replace function public.wallet_pin_check_new(p_pin text)
returns void language plpgsql immutable set search_path = public as $$
begin
  if p_pin is null or p_pin !~ '^[0-9]{6}$' then raise exception 'Your PIN must be 6 digits.'; end if;
  if public.wallet_pin_is_trivial(p_pin) then raise exception 'That PIN is too easy to guess. Pick another.'; end if;
end;
$$;

create or replace function public.wallet_pin_lock_text(p_until timestamptz)
returns text language sql stable set search_path = public as $$
  select 'Too many tries. Try again in '
      || greatest(1, ceil(extract(epoch from (p_until - now())) / 60))::int
      || case when ceil(extract(epoch from (p_until - now())) / 60) <= 1 then ' minute.' else ' minutes.' end;
$$;

-- ------------------------------------------------------------- guard ---

-- The guard every member value action calls first. Stable messages the app
-- detects: PIN_SETUP_REQUIRED (no PIN yet), PIN_REQUIRED (locked).
create or replace function public.require_wallet_unlocked()
returns void language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_hash text;
  v_until timestamptz;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select pp.pin_hash, pp.pin_unlocked_until into v_hash, v_until from public.profile_private pp where pp.user_id = me;
  if v_hash is null then raise exception 'PIN_SETUP_REQUIRED' using hint = 'wallet_pin'; end if;
  if v_until is null or v_until <= now() then raise exception 'PIN_REQUIRED' using hint = 'wallet_pin'; end if;
end;
$$;

-- --------------------------------------------------------------- RPCs ---

-- {has_pin, locked_until, unlocked_until}; the times only while in the future.
create or replace function public.wallet_pin_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  r public.profile_private%rowtype;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into r from public.profile_private where user_id = me;
  return json_build_object(
    'has_pin', r.pin_hash is not null,
    'locked_until', case when r.pin_locked_until > now() then r.pin_locked_until end,
    'unlocked_until', case when r.pin_hash is not null and r.pin_unlocked_until > now() then r.pin_unlocked_until end
  );
end;
$$;

-- First set needs no old PIN; changing it needs the old one. A wrong old PIN
-- counts as a failed try (same lockout as verify), so the reply is json:
-- {ok: true, expires_at} or {ok: false, code: 'WRONG'|'LOCKED', error, ...}.
-- Bad input (not 6 digits, too easy) raises. Setting it unlocks for 5 min.
create or replace function public.set_wallet_pin(p_pin text, p_old_pin text default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  r public.profile_private%rowtype;
  v_exp timestamptz := now() + interval '5 minutes';
  v_left int;
begin
  if me is null then raise exception 'Sign in first'; end if;
  perform public.wallet_pin_check_new(p_pin);
  insert into public.profile_private (user_id) values (me) on conflict (user_id) do nothing;
  select * into r from public.profile_private where user_id = me for update;

  if r.pin_hash is not null then
    if r.pin_locked_until > now() then
      return json_build_object('ok', false, 'code', 'LOCKED', 'error', public.wallet_pin_lock_text(r.pin_locked_until), 'locked_until', r.pin_locked_until);
    end if;
    if p_old_pin is null then
      return json_build_object('ok', false, 'code', 'OLD_PIN_REQUIRED', 'error', 'Enter your current PIN.');
    end if;
    if extensions.crypt(p_old_pin, r.pin_hash) <> r.pin_hash then
      if r.pin_failed + 1 >= 5 then
        update public.profile_private set pin_failed = 0, pin_locked_until = now() + interval '15 minutes', pin_unlocked_until = null where user_id = me;
        return json_build_object('ok', false, 'code', 'LOCKED', 'error', 'Too many tries. Try again in 15 minutes.', 'locked_until', now() + interval '15 minutes');
      end if;
      update public.profile_private set pin_failed = pin_failed + 1 where user_id = me;
      v_left := 5 - (r.pin_failed + 1);
      return json_build_object('ok', false, 'code', 'WRONG', 'error', 'Wrong current PIN. ' || v_left || case when v_left = 1 then ' try left.' else ' tries left.' end, 'tries_left', v_left);
    end if;
  end if;

  update public.profile_private
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')),
         pin_set_at = now(), pin_failed = 0, pin_locked_until = null, pin_unlocked_until = v_exp
   where user_id = me;
  return json_build_object('ok', true, 'expires_at', v_exp);
end;
$$;

-- Forgot PIN. Only right after a fresh sign-in (see the header): password
-- users re-enter their password, Apple users run Sign in with Apple again
-- (or sign out and back in). Raises REAUTH_REQUIRED otherwise.
create or replace function public.reset_wallet_pin(p_new_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_signin timestamptz;
  v_sid text := auth.jwt() ->> 'session_id';
  v_session timestamptz;
  v_exp timestamptz := now() + interval '5 minutes';
begin
  if me is null then raise exception 'Sign in first'; end if;
  perform public.wallet_pin_check_new(p_new_pin);
  select u.last_sign_in_at into v_signin from auth.users u where u.id = me;
  if v_signin is null or v_signin < now() - interval '2 minutes' then
    raise exception 'REAUTH_REQUIRED' using hint = 'wallet_pin';
  end if;
  if v_sid is not null then
    select s.created_at into v_session from auth.sessions s where s.id::text = v_sid and s.user_id = me;
    if v_session is null or v_session < now() - interval '2 minutes' then
      raise exception 'REAUTH_REQUIRED' using hint = 'wallet_pin';
    end if;
  end if;
  insert into public.profile_private (user_id) values (me) on conflict (user_id) do nothing;
  update public.profile_private
     set pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf')),
         pin_set_at = now(), pin_failed = 0, pin_locked_until = null, pin_unlocked_until = v_exp
   where user_id = me;
  return json_build_object('ok', true, 'expires_at', v_exp);
end;
$$;

-- {ok: true, unlock_token: null, expires_at} on the right PIN (the unlock is
-- kept server-side in pin_unlocked_until, so the token is always null), or
-- {ok: false, code: 'WRONG'|'LOCKED'|'PIN_SETUP_REQUIRED', error, ...}.
create or replace function public.verify_wallet_pin(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  r public.profile_private%rowtype;
  v_exp timestamptz := now() + interval '5 minutes';
  v_left int;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into r from public.profile_private where user_id = me for update;
  if r.pin_hash is null then
    return json_build_object('ok', false, 'code', 'PIN_SETUP_REQUIRED', 'error', 'Set your wallet PIN first.');
  end if;
  if r.pin_locked_until > now() then
    return json_build_object('ok', false, 'code', 'LOCKED', 'error', public.wallet_pin_lock_text(r.pin_locked_until), 'locked_until', r.pin_locked_until);
  end if;
  if p_pin is null or p_pin !~ '^[0-9]{6}$' or extensions.crypt(p_pin, r.pin_hash) <> r.pin_hash then
    if r.pin_failed + 1 >= 5 then
      update public.profile_private set pin_failed = 0, pin_locked_until = now() + interval '15 minutes', pin_unlocked_until = null where user_id = me;
      return json_build_object('ok', false, 'code', 'LOCKED', 'error', 'Too many tries. Try again in 15 minutes.', 'locked_until', now() + interval '15 minutes');
    end if;
    update public.profile_private set pin_failed = pin_failed + 1 where user_id = me;
    v_left := 5 - (r.pin_failed + 1);
    return json_build_object('ok', false, 'code', 'WRONG', 'error', 'Wrong PIN. ' || v_left || case when v_left = 1 then ' try left.' else ' tries left.' end, 'tries_left', v_left);
  end if;
  update public.profile_private set pin_failed = 0, pin_locked_until = null, pin_unlocked_until = v_exp where user_id = me;
  return json_build_object('ok', true, 'unlock_token', null, 'expires_at', v_exp);
end;
$$;

revoke all on function public.wallet_pin_is_trivial(text) from public, anon;
revoke all on function public.wallet_pin_check_new(text) from public, anon;
revoke all on function public.wallet_pin_lock_text(timestamptz) from public, anon;
revoke all on function public.require_wallet_unlocked() from public, anon;
revoke all on function public.wallet_pin_status() from public, anon;
revoke all on function public.set_wallet_pin(text, text) from public, anon;
revoke all on function public.reset_wallet_pin(text) from public, anon;
revoke all on function public.verify_wallet_pin(text) from public, anon;
grant execute on function public.wallet_pin_is_trivial(text) to authenticated;
grant execute on function public.wallet_pin_check_new(text) to authenticated;
grant execute on function public.wallet_pin_lock_text(timestamptz) to authenticated;
grant execute on function public.require_wallet_unlocked() to authenticated;
grant execute on function public.wallet_pin_status() to authenticated;
grant execute on function public.set_wallet_pin(text, text) to authenticated;
grant execute on function public.reset_wallet_pin(text) to authenticated;
grant execute on function public.verify_wallet_pin(text) to authenticated;

-- ------------------------------------------------- guarded value actions ---
-- Each body is the live pg_get_functiondef (2026-10-09) plus the guard.

-- Blind box bought with points.
CREATE OR REPLACE FUNCTION public.buy_box()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  v_cost int := public.setting_num('box_points_cost', 100)::int;
  v_balance int;
  v_id uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  perform public.require_wallet_unlocked();
  if v_cost <= 0 then raise exception 'Boxes are not for sale right now'; end if;
  select points into v_balance from public.profiles where id = me for update;
  if coalesce(v_balance, 0) < v_cost then
    raise exception 'You need % points for a box (you have %)', v_cost, coalesce(v_balance, 0);
  end if;
  insert into public.card_boxes (user_id, source, points_spent) values (me, 'points', v_cost) returning id into v_id;
  perform public.award_points(me, -v_cost, 'box', 'card_box', v_id::text, 'Blind box', 'box:' || v_id);
  return v_id;
end;
$function$;

-- Card prize claimed by the member (spends cards).
CREATE OR REPLACE FUNCTION public.claim_card_reward(p_reward uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  r public.card_rewards%rowtype;
  v_mine int;
  v_used uuid[] := '{}';
  v_pick uuid[];
  v_need int;
  v_set_size int;
  v_rarity text;
  v_id uuid;
  v_exp timestamptz;
begin
  if me is null then raise exception 'Sign in first'; end if;
  perform public.require_wallet_unlocked();
  perform public.expire_card_reward_claims(me);
  select * into r from public.card_rewards where id = p_reward for update;
  if r.id is null or not r.active then raise exception 'This prize is no longer available'; end if;
  if r.starts_at > now() then raise exception 'This prize is not live yet'; end if;
  if r.ends_at is not null and r.ends_at < now() then raise exception 'This prize has ended'; end if;
  if r.stock is not null and r.claims_count >= r.stock then raise exception 'All of these have been claimed'; end if;
  if r.vendor_id is not null and exists (select 1 from public.vendors vd where vd.id = r.vendor_id and vd.owner_id = me) then
    raise exception 'You cannot claim your own prize';
  end if;
  select count(*) into v_mine from public.card_reward_claims where reward_id = p_reward and user_id = me and status in ('active', 'redeemed');
  if v_mine >= r.per_user_limit then raise exception 'You already claimed this prize'; end if;
  -- lock my held cards so two claims can't spend the same card
  perform 1 from public.user_cards where user_id = me and status = 'held' for update;

  if r.need_full_set then
    select count(*) into v_set_size from public.card_types where active;
    select coalesce(array_agg(id), '{}') into v_pick from (
      select distinct on (uc.card_id) uc.id
      from public.user_cards uc join public.card_types ct on ct.id = uc.card_id
      where uc.user_id = me and uc.status = 'held' and ct.active
      order by uc.card_id, uc.acquired_at asc
    ) s;
    if cardinality(v_pick) < v_set_size then
      raise exception 'You need the full set for this (% of % cards)', cardinality(v_pick), v_set_size;
    end if;
    v_used := v_used || v_pick;
  end if;

  for v_rarity, v_need in select * from (values ('common', r.need_common), ('rare', r.need_rare), ('legendary', r.need_legendary)) t(rar, need) loop
    if v_need <= 0 then continue; end if;
    select coalesce(array_agg(id), '{}') into v_pick from (
      select uc.id
      from public.user_cards uc join public.card_types ct on ct.id = uc.card_id
      where uc.user_id = me and uc.status = 'held' and ct.rarity = v_rarity and not (uc.id = any(v_used))
      order by (select count(*) from public.user_cards u2 where u2.user_id = me and u2.status = 'held' and u2.card_id = uc.card_id) desc,
               uc.acquired_at asc
      limit v_need
    ) s;
    if cardinality(v_pick) < v_need then
      raise exception 'You need % more % card%', v_need - cardinality(v_pick), v_rarity, case when v_need - cardinality(v_pick) = 1 then '' else 's' end;
    end if;
    v_used := v_used || v_pick;
  end loop;

  v_exp := coalesce(r.ends_at, now() + make_interval(days => public.setting_num('card_reward_claim_days', 30)::int));
  insert into public.card_reward_claims (reward_id, user_id, cards_used, expires_at)
  values (p_reward, me, cardinality(v_used), v_exp) returning id into v_id;
  update public.user_cards set status = 'redeemed', claim_id = v_id, redeemed_at = now() where id = any(v_used);
  update public.card_rewards set claims_count = claims_count + 1 where id = p_reward;
  return json_build_object('id', v_id, 'expires_at', v_exp, 'cards_used', cardinality(v_used));
end;
$function$;

-- Partner voucher: guarded only when it costs points (free ones move no value).
CREATE OR REPLACE FUNCTION public.claim_voucher(p_voucher uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if v.points_cost > 0 then perform public.require_wallet_unlocked(); end if;
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
$function$;

-- Accepting a trade moves my cards; declining moves nothing, so it isn't guarded.
CREATE OR REPLACE FUNCTION public.decide_trade(p_trade uuid, p_accept boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  t public.card_trades%rowtype;
  v_offer uuid[];
  v_request uuid[];
  v_ok int;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if p_accept then perform public.require_wallet_unlocked(); end if;
  select * into t from public.card_trades where id = p_trade for update;
  if t.id is null or t.to_user <> me then raise exception 'Trade not found'; end if;
  if t.status <> 'proposed' then raise exception 'This trade was already %', t.status; end if;
  if not p_accept then
    update public.card_trades set status = 'declined', decided_at = now() where id = p_trade;
    perform public.notify(t.from_user, me, 'cards', p_body => 'declined:' || p_trade);
    return;
  end if;
  select coalesce(array_agg(user_card_id), '{}') into v_offer from public.card_trade_items where trade_id = p_trade and side = 'offer';
  select coalesce(array_agg(user_card_id), '{}') into v_request from public.card_trade_items where trade_id = p_trade and side = 'request';
  -- lock the cards, then verify nothing moved since the offer
  perform 1 from public.user_cards where id = any(v_offer || v_request) for update;
  select count(*) into v_ok from public.user_cards where id = any(v_offer) and user_id = t.from_user and status = 'held';
  if v_ok <> cardinality(v_offer) then
    update public.card_trades set status = 'cancelled', decided_at = now() where id = p_trade;
    raise exception 'Some of the cards offered have already moved. The trade was cancelled.';
  end if;
  select count(*) into v_ok from public.user_cards where id = any(v_request) and user_id = t.to_user and status = 'held';
  if v_ok <> cardinality(v_request) then
    update public.card_trades set status = 'cancelled', decided_at = now() where id = p_trade;
    raise exception 'Some of your cards have already moved. The trade was cancelled.';
  end if;
  update public.user_cards set user_id = t.to_user, source = 'trade', acquired_at = now() where id = any(v_offer);
  update public.user_cards set user_id = t.from_user, source = 'trade', acquired_at = now() where id = any(v_request);
  update public.card_trades set status = 'accepted', decided_at = now() where id = p_trade;
  -- any other open offer that touched these cards is now moot
  update public.card_trades set status = 'cancelled', decided_at = now()
   where status = 'proposed' and id <> p_trade
     and id in (select trade_id from public.card_trade_items where user_card_id = any(v_offer || v_request));
  perform public.notify(t.from_user, me, 'cards', p_body => 'accepted:' || p_trade);
end;
$function$;

-- New trade offer (a gift is an offer with nothing asked back).
CREATE OR REPLACE FUNCTION public.propose_trade(p_to uuid, p_offer uuid[], p_request uuid[], p_message text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := auth.uid();
  v_max int := public.setting_num('trade_max_cards', 9)::int;
  v_offer uuid[] := (select coalesce(array_agg(distinct x), '{}') from unnest(coalesce(p_offer, '{}')) x);
  v_request uuid[] := (select coalesce(array_agg(distinct x), '{}') from unnest(coalesce(p_request, '{}')) x);
  v_ok int;
  v_id uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  perform public.require_wallet_unlocked();
  if p_to is null or p_to = me then raise exception 'Pick a friend to trade with'; end if;
  if not public.is_friend(me, p_to) then raise exception 'You can only trade with friends'; end if;
  if exists (select 1 from public.blocks b where (b.blocker_id = me and b.blocked_id = p_to) or (b.blocker_id = p_to and b.blocked_id = me)) then
    raise exception 'You cannot trade with this user';
  end if;
  if cardinality(v_offer) + cardinality(v_request) = 0 then raise exception 'Add at least one card to the trade'; end if;
  if cardinality(v_offer) > v_max or cardinality(v_request) > v_max then raise exception 'Up to % cards a side', v_max; end if;
  select count(*) into v_ok from public.user_cards where id = any(v_offer) and user_id = me and status = 'held';
  if v_ok <> cardinality(v_offer) then raise exception 'One of the cards you offered is no longer yours'; end if;
  select count(*) into v_ok from public.user_cards where id = any(v_request) and user_id = p_to and status = 'held';
  if v_ok <> cardinality(v_request) then raise exception 'One of the cards you asked for is no longer theirs'; end if;
  insert into public.card_trades (from_user, to_user, message) values (me, p_to, nullif(trim(coalesce(p_message, '')), '')) returning id into v_id;
  insert into public.card_trade_items (trade_id, user_card_id, side) select v_id, x, 'offer' from unnest(v_offer) x;
  insert into public.card_trade_items (trade_id, user_card_id, side) select v_id, x, 'request' from unnest(v_request) x;
  perform public.notify(p_to, me, 'cards', p_body => 'trade:' || v_id);
  return v_id;
end;
$function$;
