-- Nearby radius up to 10 km (was 3 km).
alter table public.user_locations drop constraint if exists user_locations_share_radius_m_check;
alter table public.user_locations add constraint user_locations_share_radius_m_check check (share_radius_m between 500 and 10000);
