-- =============================================================================
-- Garage redesign: car cut-outs for the roller-door bay
--   The owner's phone cuts the car out of its cover photo (Apple Vision on
--   iPhone, ML Kit subject segmentation on Android: the member's own pixels,
--   nothing regenerated) and uploads a PNG with alpha next to the photo in
--   car-photos (`<photo path>_cut.png`).
--
--   cutout_url     the PNG, or null when there is none (not made yet, or the
--                  cut-out didn't pass the quality check: the car shows as a
--                  photo card instead).
--   cutout_source  the photo URL the cut-out was made from. A cover photo that
--                  no longer matches means the cut-out is stale: the owner's
--                  phone makes a new one, everyone else sees the card.
--   garage_style   'auto' (cut-out when there is a good one) | 'card' (the
--                  member forced the photo card).
--
-- RLS: nothing new. Everyone signed in reads cars ("cars: authenticated can
-- read") and only the owner updates their row ("cars: owner can update").
-- =============================================================================

alter table public.cars
  add column if not exists cutout_url text,
  add column if not exists cutout_source text,
  add column if not exists garage_style text not null default 'auto';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'cars_garage_style_check') then
    alter table public.cars add constraint cars_garage_style_check check (garage_style in ('auto', 'card'));
  end if;
end $$;

comment on column public.cars.cutout_url is 'Car cut out of its cover photo on the owner''s phone (PNG with alpha), null when none or it failed the quality check.';
comment on column public.cars.cutout_source is 'The photo URL the cut-out was made from; a different cover photo makes it stale.';
comment on column public.cars.garage_style is 'auto: cut-out in the garage bay when there is a good one; card: always the photo card.';
