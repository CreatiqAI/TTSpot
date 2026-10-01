-- =============================================================================
-- Video posts, and a place on a post from the address search.
--
-- Video: a post has photos OR one video (up to 60 s / 50 MB, checked in the
-- app). The files sit in post-photos next to the photos:
--   <uid>/posts/<ts>.mp4     the video            -> video_url
--   <uid>/posts/<ts>.jpg     a still from it      -> video_poster_url
--   <uid>/posts/<ts>_t.jpg   its grid thumbnail   (found by name, like photos)
-- The poster is also photo_urls[1], so everything that shows a post's cover
-- (grids, partner and club pages, shared-post cards, the spot cover trigger,
-- and older app versions) shows the still without knowing about video.
--   video_ms   the length, for the duration chip on tiles without loading it.
--
-- Place: the post screen now searches addresses (the `places` Edge Function)
-- and offers "Use my location". A TT Spot pick still sets place_id. Anything
-- else (a mamak, a petrol station, "Near Taman Tun Dr Ismail") is kept on the
-- post itself, so ordinary addresses never become Spots on the map:
--   place_name, place_address, and the coordinates in lat / lng (which held
--   only spotted pins until now; spotted posts keep their pin there).
-- =============================================================================

alter table public.posts
  add column if not exists video_url        text,
  add column if not exists video_poster_url text,
  add column if not exists video_ms         int,
  add column if not exists place_name       text,
  add column if not exists place_address    text;

alter table public.posts drop constraint if exists posts_video_ms_check;
alter table public.posts add constraint posts_video_ms_check
  check (video_ms is null or video_ms between 0 and 600000);

-- One video and nothing else but its poster.
alter table public.posts drop constraint if exists posts_video_or_photos;
alter table public.posts add constraint posts_video_or_photos
  check (video_url is null or cardinality(photo_urls) <= 1);

alter table public.posts drop constraint if exists posts_place_name_check;
alter table public.posts add constraint posts_place_name_check
  check (place_name is null or char_length(place_name) between 1 and 120);

alter table public.posts drop constraint if exists posts_place_address_check;
alter table public.posts add constraint posts_place_address_check
  check (place_address is null or char_length(place_address) <= 300);

-- -------------------------------------------------------------- storage ---
-- post-photos took images only, 10 MB. Videos need mp4 / mov and 50 MB (the
-- same cap as chat-media). Photos are still compressed on the phone.
update storage.buckets
   set file_size_limit = greatest(coalesce(file_size_limit, 0), 52428800),
       allowed_mime_types = array(select distinct unnest(allowed_mime_types || array['video/mp4', 'video/quicktime']))
 where id = 'post-photos'
   and allowed_mime_types is not null;
update storage.buckets
   set file_size_limit = greatest(coalesce(file_size_limit, 0), 52428800)
 where id = 'post-photos'
   and allowed_mime_types is null;

-- ---------------------------------------------------------------- views ---
-- p.* is expanded when a view is made, so the new columns need a rebuild.
-- (Nothing in the app reads this view; the feed selects from posts.)
drop view if exists public.posts_with_counts;
create view public.posts_with_counts
with (security_invoker = true) as
select
  p.*,
  (select count(*) from public.post_likes l where l.post_id = p.id)::int    as like_count,
  (select count(*) from public.post_comments c where c.post_id = p.id)::int as comment_count,
  (select count(*) from public.poll_votes v where v.post_id = p.id)::int    as vote_count
from public.posts p;
grant all on public.posts_with_counts to anon, authenticated, service_role;
