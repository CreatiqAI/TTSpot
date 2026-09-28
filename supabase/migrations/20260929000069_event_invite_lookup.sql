-- =============================================================================
-- Event invite QR helpers. The invite code itself (public.event_invite_code,
-- public.referral_codes, public.event_referrals) comes from the referral
-- migration; these functions guard with to_regclass and dynamic SQL so they
-- create and run even if that migration has not landed yet.
--
--   event_linked_count(p_event uuid) returns int
--     Host only: how many people joined TT Spot through this event's invite.
--   event_for_invite_code(p_code text) returns uuid
--     Any member: which event an invite code (https://ttspot.my/e/<CODE>) belongs to.
-- =============================================================================

create or replace function public.event_linked_count(p_event uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare v_n int := 0;
begin
  if not public.is_meet_host(p_event) then
    raise exception 'Only the host can see who joined through the invite';
  end if;
  if to_regclass('public.event_referrals') is null then
    return 0;
  end if;
  execute 'select count(*)::int from public.event_referrals where event_id = $1' into v_n using p_event;
  return coalesce(v_n, 0);
end;
$$;

create or replace function public.event_for_invite_code(p_code text) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_event uuid;
begin
  if auth.uid() is null or p_code is null or btrim(p_code) = '' then
    return null;
  end if;
  if to_regclass('public.referral_codes') is null then
    return null;
  end if;
  execute 'select event_id from public.referral_codes where upper(code) = upper($1) and event_id is not null limit 1'
    into v_event using btrim(p_code);
  return v_event;
end;
$$;

revoke execute on function public.event_linked_count(uuid) from public, anon;
revoke execute on function public.event_for_invite_code(text) from public, anon;
grant execute on function public.event_linked_count(uuid) to authenticated;
grant execute on function public.event_for_invite_code(text) to authenticated;
