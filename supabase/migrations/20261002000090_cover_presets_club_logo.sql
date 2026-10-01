-- 0090: meet cover presets + club logos are required.
--
-- 1. Cover presets. The plan wizard lets a host pick one of the bundled covers
--    (assets/covers/*.jpg) instead of uploading a photo. Those files also live
--    at event-covers/presets/<id>.jpg (plus the <id>_t.jpg thumbnail) so a
--    preset is an ordinary public URL in events.cover_url: the meet page, the
--    map sheet, chat cards, share cards, the website and older app builds all
--    read it like any uploaded cover. Members can only write to their own
--    folder; admins also manage the shared presets folder.
--
-- 2. Club logos. Owner's rule: a car club must have a logo. The app uploads
--    the logo before it inserts the club row, so a new club without one is
--    refused here too. Existing clubs without a logo keep working (only
--    INSERT checks for it); once a club has a logo it can be changed, never
--    removed. Club officers (owner, vp, secretary) set it through
--    set_club_logo(), because the clubs UPDATE policy is owner-only.

-- ------------------------------------------------------------ cover presets ---
drop policy if exists "storage: admins manage cover presets" on storage.objects;
create policy "storage: admins manage cover presets" on storage.objects
  for all to authenticated
  using (bucket_id = 'event-covers' and (storage.foldername(name))[1] = 'presets' and public.is_admin())
  with check (bucket_id = 'event-covers' and (storage.foldername(name))[1] = 'presets' and public.is_admin());

-- --------------------------------------------------------------- club logos ---
create or replace function public.clubs_logo_required() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.avatar_url is null or btrim(new.avatar_url) = '' then
      raise exception 'Add a club logo. It shows on the map and on your club''s events.';
    end if;
  elsif coalesce(btrim(old.avatar_url), '') <> '' and coalesce(btrim(new.avatar_url), '') = '' then
    raise exception 'A club logo can be changed, but not removed.';
  end if;
  return new;
end;
$$;

drop trigger if exists clubs_logo_required on public.clubs;
create trigger clubs_logo_required before insert or update of avatar_url on public.clubs
  for each row execute function public.clubs_logo_required();

create or replace function public.set_club_logo(p_club uuid, p_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_url is null or btrim(p_url) !~ '^https://' then raise exception 'Pick a logo first.'; end if;
  if not (
    public.is_admin()
    or exists (select 1 from public.clubs c where c.id = p_club and c.owner_id = auth.uid())
    or exists (select 1 from public.club_members m where m.club_id = p_club and m.user_id = auth.uid() and m.role in ('owner', 'vp', 'secretary'))
  ) then
    raise exception 'Only the club''s officers can change its logo.';
  end if;
  update public.clubs set avatar_url = btrim(p_url) where id = p_club;
  if not found then raise exception 'That club no longer exists.'; end if;
end;
$$;

revoke execute on function public.set_club_logo(uuid, text) from public, anon;
grant execute on function public.set_club_logo(uuid, text) to authenticated;
