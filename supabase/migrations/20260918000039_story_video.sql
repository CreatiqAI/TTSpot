-- Video moments: photo_url stays the poster (thumbnails, map pins), video_url plays in the viewer.
alter table public.stories add column if not exists video_url text;
