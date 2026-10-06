-- 0111 club members list + club tag choice (0.3.56).
--
-- 1. club_members_list(club): the club page's "View all" page. One call:
--    each member with their role, the club tag they show and their default
--    car (the one marked default, else their newest), toy render included.
-- 2. Club tags, the owner's rule from 0.3.56: every member of an OFFICIAL
--    club, presidents included, picks which ONE of their official clubs'
--    tags shows beside their name, or none. A president who never chose
--    shows their own club (as in 0.3.55); now they can pick another of their
--    official clubs, or none. Underground clubs still never get a tag.
--
-- Where the choice lives:
--   * club_members.show_tag (0109): the club picked, at most one row true.
--   * profiles.settings.club_tag = 'none': "no tag", which also switches off
--     the president default. Any pick clears it.
-- With neither: the oldest official club they are president of, else none.
--
-- Old apps keep working: they call club_tag_of / set_club_tag(club, show)
-- and read club_tag on profiles, all with the same signatures. On an old
-- app the president still sees "you always carry it" (no switch); harmless.

-- ------------------------------------------------------------- tag rules ---

create or replace function public.club_tag_of(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with picks as (
    -- Their pick wins (any official club they are in).
    select m.club_id, 0 as pri, m.role
      from public.club_members m
     where m.user_id = p_user and m.show_tag
    union all
    -- No pick: the club they run, unless they chose no tag.
    select c.id, 1, 'owner'
      from public.clubs c
     where c.owner_id = p_user
       and not exists (select 1 from public.profiles p
                        where p.id = p_user and p.settings ->> 'club_tag' = 'none')
  )
  select jsonb_build_object(
           'club_id', c.id,
           'name', c.name,
           'handle', c.handle,
           'avatar_url', c.avatar_url,
           'role', case when c.owner_id = p_user then 'owner' else coalesce(p.role, 'member') end)
    from picks p
    join public.clubs c on c.id = p.club_id
   where c.tier = 'official'
     and (c.official_until is null or c.official_until > now())
   order by p.pri, c.created_at
   limit 1;
$$;

-- My choice: the tag of [p_club] (an official club I'm in), or none (null).
-- Returns the tag I show now (club_tag_of), null for none.
create or replace function public.set_my_club_tag(p_club uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'Sign in first'; end if;
  if p_club is not null then
    if not exists (select 1 from public.club_members where club_id = p_club and user_id = v_me) then
      raise exception 'Join the club first';
    end if;
    if not exists (select 1 from public.clubs c
                    where c.id = p_club and c.tier = 'official'
                      and (c.official_until is null or c.official_until > now())) then
      raise exception 'Only official clubs have a club tag';
    end if;
  end if;
  update public.club_members
     set show_tag = (club_id is not distinct from p_club)
   where user_id = v_me
     and (show_tag or club_id is not distinct from p_club);
  update public.profiles
     set settings = case when p_club is null
                         then coalesce(settings, '{}'::jsonb) || '{"club_tag": "none"}'::jsonb
                         else coalesce(settings, '{}'::jsonb) - 'club_tag' end
   where id = v_me;
  return public.club_tag_of(v_me);
end;
$$;

-- The club page's switch (and every older app): wear this club's tag, or
-- take it off. Taking off the tag that shows (a pick or the president
-- default) means no tag at all; taking off one that doesn't show changes
-- nothing that anyone sees.
create or replace function public.set_club_tag(p_club uuid, p_show boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'Sign in first'; end if;
  if not exists (select 1 from public.club_members where club_id = p_club and user_id = v_me) then
    raise exception 'Join the club first';
  end if;
  if p_show then
    perform public.set_my_club_tag(p_club);
  elsif (public.club_tag_of(v_me) ->> 'club_id')::uuid = p_club then
    perform public.set_my_club_tag(null);
  else
    update public.club_members set show_tag = false where club_id = p_club and user_id = v_me and show_tag;
  end if;
end;
$$;

-- ---------------------------------------------------------- members list ---

-- Everyone in [p_club] for the members page, officers first (President, VP,
-- Secretary), then in the order they joined. Same people the club page's
-- strip shows to any signed-in member (club_members, profiles and cars are
-- readable by every signed-in account), minus anyone in a block with me.
-- car = their default car (else newest) as a cars-shaped object with only
-- what a thumbnail needs, or null.
create or replace function public.club_members_list(p_club uuid)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  role text,
  joined_at timestamptz,
  club_tag jsonb,
  car jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select m.user_id,
         p.username::text,
         p.display_name,
         p.avatar_url,
         case when c.owner_id = m.user_id then 'owner' else coalesce(m.role, 'member') end,
         m.created_at,
         public.club_tag_of(m.user_id),
         k.car
    from public.club_members m
    join public.clubs c on c.id = m.club_id
    join public.profiles p on p.id = m.user_id
    left join lateral (
      select jsonb_build_object(
               'id', x.id,
               'owner_id', x.owner_id,
               'make', x.make,
               'model', x.model,
               'year', x.year,
               'photo_urls', coalesce(to_jsonb(x.photo_urls[1:1]), '[]'::jsonb),
               'created_at', x.created_at,
               'color', x.color,
               'is_default', x.is_default,
               'portrait_url', x.portrait_url,
               'body_style', x.body_style,
               'toy_url', x.toy_url,
               'toy_status', x.toy_status,
               'toy_source', x.toy_source) as car
        from public.cars x
       where x.owner_id = m.user_id
       order by x.is_default desc, x.created_at desc
       limit 1
    ) k on true
   where m.club_id = p_club
     and auth.uid() is not null
     and not exists (select 1 from public.blocks b
                      where (b.blocker_id = auth.uid() and b.blocked_id = m.user_id)
                         or (b.blocker_id = m.user_id and b.blocked_id = auth.uid()))
   order by case when c.owner_id = m.user_id then 0
                 when m.role = 'vp' then 1
                 when m.role = 'secretary' then 2
                 else 3 end,
            m.created_at,
            m.user_id
   limit 2000;
$$;

revoke all on function public.set_my_club_tag(uuid) from public;
revoke all on function public.club_members_list(uuid) from public;
grant execute on function public.set_my_club_tag(uuid) to authenticated;
grant execute on function public.club_members_list(uuid) to authenticated;
-- Unchanged from 0109, repeated so this file stands alone.
revoke all on function public.club_tag_of(uuid) from public;
revoke all on function public.set_club_tag(uuid, boolean) from public;
grant execute on function public.club_tag_of(uuid) to anon, authenticated;
grant execute on function public.set_club_tag(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
