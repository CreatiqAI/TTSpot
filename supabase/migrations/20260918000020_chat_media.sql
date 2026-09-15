-- =============================================================================
-- Voice notes and video messages in chat.
-- =============================================================================
alter table public.messages
  add column audio_url text,
  add column audio_ms  int,
  add column video_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-media', 'chat-media', true, 52428800, array['audio/mp4','audio/aac','audio/m4a','audio/x-m4a','audio/mpeg','video/mp4','video/quicktime'])
on conflict (id) do nothing;

create policy "chat-media: public read" on storage.objects for select using (bucket_id = 'chat-media');
create policy "chat-media: owner upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "chat-media: owner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);
