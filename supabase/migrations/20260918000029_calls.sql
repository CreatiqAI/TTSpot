-- "Friends can call me": a friend may fetch my phone number to call or
-- WhatsApp me, only when I switched it on in Settings (settings.calls_from
-- = 'friends'; default nobody). Strangers and nearby people never can.
create or replace function public.friend_phone(p_user uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); v text;
begin
  if me is null or p_user is null or me = p_user then return null; end if;
  if not public.is_friend(me, p_user) then return null; end if;
  if coalesce((select p.settings->>'calls_from' from public.profiles p where p.id = p_user), 'nobody') <> 'friends' then return null; end if;
  if exists (select 1 from public.blocks b where b.blocker_id = p_user and b.blocked_id = me) then return null; end if;
  select pp.phone into v from public.profile_private pp where pp.user_id = p_user;
  return v;
end;
$$;
