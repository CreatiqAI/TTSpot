-- Admin · Members shows each member's points balance ("1,050 pts"). The list
-- comes from admin_recent_users, which now also returns points (a new column
-- in a returned table, so drop + create). Body otherwise the live one.

drop function if exists public.admin_recent_users(int);
create function public.admin_recent_users(p_limit int default 200)
returns table (id uuid, username text, display_name text, avatar_url text, created_at timestamptz, home_state text,
               is_admin boolean, club_owner boolean, cars int, last_seen timestamptz, phone text, is_partner boolean, email text,
               is_organizer boolean, points int)
language sql stable security definer set search_path = public, auth as $$
  select p.id, p.username::text, p.display_name, p.avatar_url, p.created_at, p.home_state,
         p.is_admin, p.club_owner,
         (select count(*)::int from public.cars c where c.owner_id = p.id),
         (select max(l.updated_at) from public.user_locations l where l.user_id = p.id),
         pp.phone,
         exists (select 1 from public.vendors v where v.owner_id = p.id and v.active),
         u.email::text,
         p.is_organizer,
         coalesce(p.points, 0)
  from public.profiles p
  left join public.profile_private pp on pp.user_id = p.id
  left join auth.users u on u.id = p.id
  where public.is_admin()
  order by p.created_at desc
  limit greatest(1, least(p_limit, 1000));
$$;
revoke execute on function public.admin_recent_users(int) from public, anon;
grant execute on function public.admin_recent_users(int) to authenticated;
