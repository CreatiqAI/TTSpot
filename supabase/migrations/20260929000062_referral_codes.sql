-- =============================================================================
-- System referral codes
--
-- Every member gets a 6-character code (e.g. K7XP4M) the moment their username
-- is first set; a meet host can mint one code per event to invite people to
-- that meet. Codes use an alphabet without look-alikes (no 0 O 1 I L).
--
--   referral_codes            code -> member OR event (exactly one)
--   event_referrals           who joined through an event's code
--   new_referral_code()       a fresh unused code (not inserted)
--   my_referral_code()        my code, created if missing
--   event_invite_code(uuid)   the event's code (host only), created once
--   redeem_referral_code(text) -> {kind: 'user'|'event', name, claimed?}
--
-- claim_referral(text) keeps working (it is also called by add_friend_by_qr
-- with a username): it now accepts a member code or a username and hands off
-- to the generalised claim_referral_from(uuid).
-- =============================================================================

create table public.referral_codes (
  code        text primary key check (code ~ '^[A-Z0-9]{6}$'),
  user_id     uuid unique references public.profiles (id) on delete cascade,
  event_id    uuid unique references public.events (id) on delete cascade,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  constraint referral_codes_one_owner check ((user_id is null) <> (event_id is null))
);
alter table public.referral_codes enable row level security;
-- Writes only happen through the security-definer functions below.
create policy "referral_codes: read own" on public.referral_codes for select to authenticated
  using (user_id = auth.uid() or (event_id is not null and public.is_meet_host(event_id)));

create table public.event_referrals (
  event_id   uuid not null references public.events (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (event_id, user_id)
);
create index event_referrals_user_idx on public.event_referrals (user_id);
alter table public.event_referrals enable row level security;
create policy "event_referrals: read own or hosted" on public.event_referrals for select to authenticated
  using (user_id = auth.uid() or public.is_meet_host(event_id));

-- -----------------------------------------------------------------------------
-- code generation
-- -----------------------------------------------------------------------------

-- A random code that is not in use right now. Not inserted: callers insert it
-- and retry on unique_violation, since another session may take it first.
create or replace function public.new_referral_code() returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; -- no 0 O 1 I L
  n constant int := length(alphabet);
  b bytea;
  c text;
begin
  loop
    b := extensions.gen_random_bytes(6);
    c := '';
    for i in 0..5 loop
      c := c || substr(alphabet, (get_byte(b, i) % n) + 1, 1);
    end loop;
    exit when not exists (select 1 from public.referral_codes where code = c);
  end loop;
  return c;
end;
$$;

-- The member's code, created if missing. Internal: clients call my_referral_code().
create or replace function public.ensure_user_referral_code(p_user uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  select code into c from public.referral_codes where user_id = p_user;
  if found then return c; end if;
  loop
    c := public.new_referral_code();
    begin
      insert into public.referral_codes (code, user_id, created_by) values (c, p_user, p_user);
      return c;
    exception when unique_violation then
      -- Either the code was taken meanwhile (try another) or this member got
      -- one from a concurrent call (use it).
      select code into c from public.referral_codes where user_id = p_user;
      if found then return c; end if;
    end;
  end loop;
end;
$$;

-- Every profile gets a code when its username is first set.
create or replace function public.on_profile_username_referral_code() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.ensure_user_referral_code(new.id);
  return null;
end;
$$;
create trigger profiles_referral_code_after_insert after insert on public.profiles
  for each row when (new.username is not null)
  execute function public.on_profile_username_referral_code();
create trigger profiles_referral_code_after_username after update of username on public.profiles
  for each row when (old.username is null and new.username is not null)
  execute function public.on_profile_username_referral_code();

-- Backfill everyone who already has a username.
do $$
declare p record;
begin
  for p in select id from public.profiles where username is not null loop
    perform public.ensure_user_referral_code(p.id);
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- client RPCs
-- -----------------------------------------------------------------------------

create or replace function public.my_referral_code() returns text
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'You''re signed out. Sign in again.'; end if;
  return public.ensure_user_referral_code(me);
end;
$$;

-- The event's invite code. Only the host (organiser, club officers, admins).
create or replace function public.event_invite_code(p_event uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can get this meet''s invite code'; end if;
  select code into c from public.referral_codes where event_id = p_event;
  if found then return c; end if;
  loop
    c := public.new_referral_code();
    begin
      insert into public.referral_codes (code, event_id, created_by) values (c, p_event, auth.uid());
      return c;
    exception when unique_violation then
      select code into c from public.referral_codes where event_id = p_event;
      if found then return c; end if;
    end;
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- claiming
-- -----------------------------------------------------------------------------

-- The existing referral claim, generalised to take the referrer's id: the
-- signed-in member becomes p_referrer's referee, once, while still brand new
-- (no check-ins yet). Paid out by settle_referral on the first check-in.
create or replace function public.claim_referral_from(p_referrer uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null or p_referrer is null or p_referrer = me then return false; end if;
  if exists (select 1 from public.referrals where referee_id = me) then return false; end if;
  if exists (select 1 from public.checkins where user_id = me)
     or exists (select 1 from public.place_checkins where user_id = me) then return false; end if;
  insert into public.referrals (referee_id, referrer_id) values (me, p_referrer) on conflict do nothing;
  return found;
end;
$$;

-- Old entry point, still used by add_friend_by_qr (with a username) and older
-- app builds. Accepts a member code or a username; silently ignores bad codes.
create or replace function public.claim_referral(p_code text) returns boolean
language plpgsql security definer set search_path = public as $$
declare ref_id uuid;
begin
  select user_id into ref_id from public.referral_codes
   where code = upper(trim(coalesce(p_code, ''))) and user_id is not null;
  if ref_id is null then
    select id into ref_id from public.profiles where username = lower(ltrim(trim(coalesce(p_code, '')), '@'))::citext;
  end if;
  if ref_id is null then return false; end if;
  return public.claim_referral_from(ref_id);
end;
$$;

-- What onboarding calls with whatever was typed in "Referral code".
--   member code (or, for old invites, a username) -> the referral claim
--   event code -> recorded in event_referrals
-- Unknown code -> error (onboarding ignores it; sign-up never blocks on it).
create or replace function public.redeem_referral_code(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  rc public.referral_codes;
  ref_id uuid;
  v_name text;
begin
  if me is null then raise exception 'You''re signed out. Sign in again.'; end if;
  if v_code = '' then raise exception 'That referral code doesn''t exist'; end if;

  select * into rc from public.referral_codes where code = v_code;
  if found and rc.event_id is not null then
    insert into public.event_referrals (event_id, user_id) values (rc.event_id, me) on conflict do nothing;
    select title into v_name from public.events where id = rc.event_id;
    return jsonb_build_object('kind', 'event', 'name', v_name);
  end if;

  ref_id := rc.user_id; -- null when no code matched
  if ref_id is null then
    select id into ref_id from public.profiles where username = lower(ltrim(trim(coalesce(p_code, '')), '@'))::citext;
  end if;
  if ref_id is null then raise exception 'That referral code doesn''t exist'; end if;
  if ref_id = me then raise exception 'That''s your own code'; end if;

  select coalesce(nullif(trim(display_name), ''), username::text) into v_name from public.profiles where id = ref_id;
  return jsonb_build_object('kind', 'user', 'name', v_name, 'claimed', public.claim_referral_from(ref_id));
end;
$$;

-- -----------------------------------------------------------------------------
-- grants
-- -----------------------------------------------------------------------------

revoke execute on function public.new_referral_code() from public, anon, authenticated;
revoke execute on function public.ensure_user_referral_code(uuid) from public, anon, authenticated;
revoke execute on function public.on_profile_username_referral_code() from public, anon, authenticated;
revoke execute on function public.claim_referral_from(uuid) from public, anon, authenticated;
revoke execute on function public.my_referral_code() from public, anon;
revoke execute on function public.event_invite_code(uuid) from public, anon;
revoke execute on function public.redeem_referral_code(text) from public, anon;
grant execute on function public.my_referral_code() to authenticated;
grant execute on function public.event_invite_code(uuid) to authenticated;
grant execute on function public.redeem_referral_code(text) to authenticated;

update public.point_rules set description = 'Enter a referral code when you sign up.' where reason = 'referral_referee';
