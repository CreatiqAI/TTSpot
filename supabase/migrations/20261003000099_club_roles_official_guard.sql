-- Two club fixes found while building public clubs (0.3.52).
--
-- 1. Appointing a VP or Secretary always failed: 0041 renamed the roles to
--    member / vp / secretary everywhere except club_invites' check constraint,
--    which still allowed only member / admin, so invite_to_club(…, 'vp') was
--    rejected by the table.
-- 2. "clubs: update own" let a president set tier = 'official' (and
--    official_until) straight from the client, skipping the paid, admin-approved
--    official status. Those columns now change only through admin RPCs /
--    the service role.

alter table public.club_invites drop constraint if exists club_invites_role_check;
alter table public.club_invites add constraint club_invites_role_check
  check (role in ('member', 'vp', 'secretary', 'admin'));

create or replace function public.clubs_guard_official() returns trigger
language plpgsql set search_path = public as $$
begin
  -- Security-definer RPCs (admin approval, official requests) run as the
  -- function owner; only a signed-in member's own UPDATE runs as authenticated.
  if current_user in ('authenticated', 'anon')
     and not public.is_admin()
     and (new.tier is distinct from old.tier
          or new.official_until is distinct from old.official_until
          or new.official_requested_at is distinct from old.official_requested_at) then
    raise exception 'Official status is set by TT Spot';
  end if;
  return new;
end;
$$;

drop trigger if exists clubs_guard_official on public.clubs;
create trigger clubs_guard_official before update on public.clubs
  for each row execute function public.clubs_guard_official();
