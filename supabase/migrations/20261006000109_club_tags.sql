-- 0109 club_tags: the official club tag beside a member's name (0.3.55).
--
-- The president of an OFFICIAL club always shows a small club tag (crest +
-- name) beside their name. Members of an official club can choose to wear
-- that club's tag too (opt-in, one club at a time). Underground clubs never
-- get a tag.
--
-- Official, as the app has it since 0040: tier = 'official' and
-- official_until is null (granted with no end) or still in the future. The
-- nightly expire_official_clubs() cron flips expired clubs back anyway; the
-- date check covers the hours in between.
--
-- How the app reads it (no extra round trips in lists):
--   * public.club_tag(profiles) is a PostgREST computed field, so any
--     profiles select or embed can ask for `club_tag` next to the columns
--     (post authors, comment authors, club members).
--   * public.club_tag_of(uuid) answers for one person (the profile header).
-- Both return json {club_id, name, handle, avatar_url, role} or null.
-- Cost per person: one index probe on club_members (partial index below) and
-- one on clubs.owner_id, then the club by primary key.

-- The member's choice: wear this club's tag. At most one row per member is
-- true (set_club_tag clears the others).
alter table public.club_members add column if not exists show_tag boolean not null default false;

create index if not exists club_members_show_tag_idx on public.club_members (user_id) where show_tag;
create index if not exists clubs_owner_idx on public.clubs (owner_id);

-- The tag someone shows, or null. An explicit choice wins over the club they
-- run (a president who also wears another official club's tag shows that
-- one); otherwise the oldest official club they are president of.
create or replace function public.club_tag_of(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with picks as (
    select m.club_id, 0 as pri, m.role
      from public.club_members m
     where m.user_id = p_user and m.show_tag
    union all
    select c.id, 1, 'owner'
      from public.clubs c
     where c.owner_id = p_user
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

-- Computed field: `select=id,username,club_tag` on profiles (and in embeds).
create or replace function public.club_tag(public.profiles)
returns jsonb
language sql
stable
set search_path = public
as $$
  select public.club_tag_of($1.id);
$$;

-- Wear (or stop wearing) a club's tag. Members only, official clubs only;
-- turning one on turns the others off.
create or replace function public.set_club_tag(p_club uuid, p_show boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not exists (select 1 from public.club_members where club_id = p_club and user_id = auth.uid()) then
    raise exception 'Join the club first';
  end if;
  if p_show then
    if not exists (select 1 from public.clubs c
                    where c.id = p_club and c.tier = 'official'
                      and (c.official_until is null or c.official_until > now())) then
      raise exception 'Only official clubs have a club tag';
    end if;
    update public.club_members set show_tag = false
     where user_id = auth.uid() and show_tag and club_id <> p_club;
  end if;
  update public.club_members set show_tag = p_show
   where club_id = p_club and user_id = auth.uid();
end;
$$;

revoke all on function public.club_tag_of(uuid) from public;
revoke all on function public.set_club_tag(uuid, boolean) from public;
grant execute on function public.club_tag_of(uuid) to anon, authenticated;
grant execute on function public.club_tag(public.profiles) to anon, authenticated;
grant execute on function public.set_club_tag(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
