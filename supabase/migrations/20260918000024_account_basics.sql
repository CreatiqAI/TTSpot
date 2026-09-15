-- Every account must have a username, a phone number and an accepted Terms
-- version. The app's router keeps sending people to "Complete your account"
-- until all three are there (existing members included).
--
-- Phone is private, so it lives in its own table (profiles is readable by
-- every member).

create table if not exists public.profile_private (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  phone text unique check (phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
  terms_accepted_at timestamptz,
  terms_version text,
  updated_at timestamptz not null default now()
);
alter table public.profile_private enable row level security;
drop policy if exists "own private row" on public.profile_private;
create policy "own private row" on public.profile_private
  for select using (user_id = auth.uid());
grant select on public.profile_private to authenticated;

-- Save phone + terms in one call. Phone must be E.164; the app normalises
-- Malaysian numbers (01x… -> +601x…).
create or replace function public.set_account_basics(p_phone text, p_terms_version text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_phone is null or p_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'Enter a valid phone number';
  end if;
  if coalesce(p_terms_version, '') = '' then
    raise exception 'Please accept the Terms of Use';
  end if;
  if exists (select 1 from public.profile_private where phone = p_phone and user_id <> me) then
    raise exception 'That phone number is already on another account';
  end if;
  insert into public.profile_private (user_id, phone, terms_accepted_at, terms_version, updated_at)
  values (me, p_phone, now(), p_terms_version, now())
  on conflict (user_id) do update
    set phone = excluded.phone,
        terms_accepted_at = now(),
        terms_version = excluded.terms_version,
        updated_at = now();
end;
$$;

-- Change just the phone later (Settings).
create or replace function public.set_my_phone(p_phone text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_phone is null or p_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'Enter a valid phone number';
  end if;
  if exists (select 1 from public.profile_private where phone = p_phone and user_id <> me) then
    raise exception 'That phone number is already on another account';
  end if;
  insert into public.profile_private (user_id, phone) values (me, p_phone)
  on conflict (user_id) do update set phone = excluded.phone, updated_at = now();
end;
$$;

-- What the app needs to decide whether the account is complete, plus which
-- sign-in methods are linked (email / google).
create or replace function public.my_account_basics()
returns table (phone text, terms_accepted_at timestamptz, terms_version text, email_confirmed boolean, providers text[])
language sql stable security definer set search_path = public, auth as $$
  select pp.phone, pp.terms_accepted_at, pp.terms_version,
         (u.email_confirmed_at is not null),
         coalesce((select array_agg(i.provider::text order by i.provider) from auth.identities i where i.user_id = u.id), '{}'::text[])
  from auth.users u
  left join public.profile_private pp on pp.user_id = u.id
  where u.id = auth.uid();
$$;

-- Admin: phone shows in the members list.
drop function if exists public.admin_recent_users(int);
create function public.admin_recent_users(p_limit int default 50)
returns table (id uuid, username text, display_name text, avatar_url text, created_at timestamptz, home_state text,
               is_admin boolean, club_owner boolean, cars int, last_seen timestamptz, phone text)
language sql stable security definer set search_path = public as $$
  select p.id, p.username::text, p.display_name, p.avatar_url, p.created_at, p.home_state,
         p.is_admin, p.club_owner,
         (select count(*)::int from public.cars c where c.owner_id = p.id),
         (select max(l.updated_at) from public.user_locations l where l.user_id = p.id),
         pp.phone
  from public.profiles p
  left join public.profile_private pp on pp.user_id = p.id
  where public.is_admin()
  order by p.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;
