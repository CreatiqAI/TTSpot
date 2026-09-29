-- The eight TiTi default avatars live at avatars/defaults/a1.png … a8.png so a
-- member's avatar_url can point at one without uploading anything. Members may
-- only write to their own folder; admins may also manage the shared defaults.

drop policy if exists "storage: admins manage default avatars" on storage.objects;
create policy "storage: admins manage default avatars" on storage.objects
  for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'defaults' and public.is_admin())
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'defaults' and public.is_admin());
