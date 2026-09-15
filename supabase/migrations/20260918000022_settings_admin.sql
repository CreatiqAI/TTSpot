-- =============================================================================
-- Settings, friend colours, admin dashboard, account deletion.
-- =============================================================================

-- ------------------------------------------------------------- settings ---
alter table public.profiles add column settings jsonb not null default '{}'::jsonb;

create or replace function public.update_my_settings(p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  update public.profiles set settings = coalesce(settings, '{}'::jsonb) || coalesce(p_patch, '{}'::jsonb)
  where id = auth.uid() returning settings into v;
  return v;
end;
$$;

-- --------------------------------------------------------- friend colours ---
create table public.friend_tags (
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  friend_id  uuid not null references public.profiles (id) on delete cascade,
  color      text not null check (color in ('red','orange','yellow','green','blue','purple','pink')),
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id)
);
alter table public.friend_tags enable row level security;
create policy "friend_tags: own" on public.friend_tags for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- ---------------------------------------------------------------- reports ---
alter table public.reports add column resolved_at timestamptz, add column resolved_by uuid references public.profiles (id) on delete set null,
  add column note text;

create or replace function public.admin_reports(p_limit int default 100)
returns table (id uuid, reporter uuid, reporter_username text, target_type text, target_id uuid, reason text, created_at timestamptz, resolved_at timestamptz, target_label text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select r.id, r.reporter_id, pr.username::text, r.target_type::text, r.target_id, r.reason, r.created_at, r.resolved_at,
      case r.target_type::text
        when 'profile' then (select '@' || p.username from public.profiles p where p.id = r.target_id)
        when 'event' then (select e.title from public.events e where e.id = r.target_id)
        when 'comment' then (select left(c.body, 60) from public.event_comments c where c.id = r.target_id)
        else null end
    from public.reports r join public.profiles pr on pr.id = r.reporter_id
    order by r.resolved_at nulls first, r.created_at desc
    limit p_limit;
end;
$$;

create or replace function public.admin_resolve_report(p_id uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  update public.reports set resolved_at = now(), resolved_by = auth.uid(), note = p_note where id = p_id;
end;
$$;

-- ------------------------------------------------------------- admin stats ---
create or replace function public.admin_stats() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return json_build_object(
    'users', (select count(*) from public.profiles where username is not null),
    'users_7d', (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'meets_upcoming', (select count(*) from public.events where status = 'active' and starts_at > now()),
    'meets_live', (select count(*) from public.events where status = 'active' and now() between starts_at - interval '1 hour' and coalesce(ends_at, starts_at + interval '6 hours')),
    'checkins_today', (select count(*) from public.checkins where checked_in_at > date_trunc('day', now())),
    'posts_7d', (select count(*) from public.posts where created_at > now() - interval '7 days'),
    'pending_verifications', (select count(*) from public.spot_verifications where status in ('pending', 'review')),
    'pending_partners', (select count(*) from public.partner_applications where status = 'pending'),
    'open_reports', (select count(*) from public.reports where resolved_at is null),
    'vendors', (select count(*) from public.vendors where active),
    'clubs', (select count(*) from public.clubs),
    'on_map_now', (select count(*) from public.user_locations where updated_at > now() - interval '20 minutes' and not ghost)
  );
end;
$$;

create or replace function public.admin_recent_users(p_limit int default 30)
returns table (id uuid, username text, display_name text, avatar_url text, created_at timestamptz, home_state text, is_admin boolean, club_owner boolean, cars int, last_seen timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select p.id, p.username::text, p.display_name, p.avatar_url, p.created_at, p.home_state, p.is_admin, p.club_owner,
      (select count(*)::int from public.cars c where c.owner_id = p.id),
      (select l.updated_at from public.user_locations l where l.user_id = p.id)
    from public.profiles p where p.username is not null
    order by p.created_at desc limit p_limit;
end;
$$;

create or replace function public.admin_set_role(p_user uuid, p_admin boolean default null, p_club_owner boolean default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_user = auth.uid() and p_admin = false then raise exception 'You cannot remove your own admin role'; end if;
  update public.profiles set is_admin = coalesce(p_admin, is_admin), club_owner = coalesce(p_club_owner, club_owner) where id = p_user;
end;
$$;

-- ---------------------------------------------------------- delete account ---
-- Removes the auth user; every table cascades from profiles.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  delete from public.profiles where id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;
