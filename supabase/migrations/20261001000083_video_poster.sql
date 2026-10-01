-- =============================================================================
-- Video messages show a still before they play.
--   video_poster_url  a JPEG frame captured on the phone when sending, stored
--                     next to the video in chat-media (<uid>/<ts>.jpg beside
--                     <uid>/<ts>.mp4). Older videos have none; the app loads
--                     their first frame instead.
--   video_ms          the length, so the bubble can show it without loading
--                     the video.
-- Chat stickers are keys drawn from bundled art (messages.sticker, free text,
-- no constraint), so the new packs need no schema change.
-- =============================================================================
alter table public.messages
  add column if not exists video_poster_url text,
  add column if not exists video_ms int;

-- chat-media took audio and video only; posters are JPEGs. (A null list
-- already allows everything, so leave that alone.)
update storage.buckets
   set allowed_mime_types = array(select distinct unnest(allowed_mime_types || array['image/jpeg']))
 where id = 'chat-media'
   and allowed_mime_types is not null
   and not ('image/jpeg' = any (allowed_mime_types));
