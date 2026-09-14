-- =============================================================================
-- Chat attachments: photos, stickers, and shared meets / spots / cars.
-- =============================================================================
alter table public.messages
  add column image_url text,
  add column sticker   text,
  add column event_id  uuid references public.events (id) on delete set null,
  add column place_id  uuid references public.places (id) on delete set null,
  add column car_id    uuid references public.cars (id) on delete set null;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-photos', 'chat-photos', true, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "chat-photos: public read" on storage.objects for select using (bucket_id = 'chat-photos');
create policy "chat-photos: owner upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "chat-photos: owner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'chat-photos' and (storage.foldername(name))[1] = auth.uid()::text);
