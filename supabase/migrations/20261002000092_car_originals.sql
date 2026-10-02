-- =============================================================================
-- Undo the plate blur: keep the original privately
--   Since 0.3.47 "Hide my number plate" uploads a blurred copy (`…_pb.jpg`) to
--   the public car-photos bucket and deleted the original, so the blur could
--   never be taken off again. From now on the original is MOVED, not deleted:
--
--   storage bucket car-originals: PRIVATE (public = false, so there is no
--     public URL). Members read, add, overwrite and delete files in their own
--     <uid>/ folder only; admins can read and delete (moderation). The app
--     previews an original through a short-lived signed URL, which storage
--     only signs for someone the select policy lets read the file.
--
--   cars.photo_originals jsonb: { "<public blurred URL>": "<uid>/<file>" },
--     the private original behind each blurred photo on the car. Written by
--     the owner's app on save (cars: owner can update). "Remove blur" uploads
--     the original back to car-photos under a new name, drops the entry and
--     deletes the private file. Deleting a car deletes its originals from the
--     app (storage has no cascade from a row).
--
--   Photos blurred before this (0.3.47) have no entry: their original is
--   gone and they stay blurred.
-- Safe to re-run.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('car-originals', 'car-originals', false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "car-originals: owner read" on storage.objects;
create policy "car-originals: owner read" on storage.objects for select to authenticated
  using (bucket_id = 'car-originals' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "car-originals: owner upload" on storage.objects;
create policy "car-originals: owner upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'car-originals' and (storage.foldername(name))[1] = auth.uid()::text);

-- Upsert (same file name again) needs update as well as insert.
drop policy if exists "car-originals: owner update" on storage.objects;
create policy "car-originals: owner update" on storage.objects for update to authenticated
  using (bucket_id = 'car-originals' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'car-originals' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "car-originals: owner delete" on storage.objects;
create policy "car-originals: owner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'car-originals' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "car-originals: admins read" on storage.objects;
create policy "car-originals: admins read" on storage.objects for select to authenticated
  using (bucket_id = 'car-originals' and public.is_admin());

drop policy if exists "car-originals: admins delete" on storage.objects;
create policy "car-originals: admins delete" on storage.objects for delete to authenticated
  using (bucket_id = 'car-originals' and public.is_admin());

alter table public.cars
  add column if not exists photo_originals jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'cars_photo_originals_object') then
    alter table public.cars add constraint cars_photo_originals_object check (jsonb_typeof(photo_originals) = 'object');
  end if;
end $$;

comment on column public.cars.photo_originals is
  'Blurred public photo URL -> path of its original in the private car-originals bucket (<owner uid>/<file>). Lets the owner remove the plate blur later.';
