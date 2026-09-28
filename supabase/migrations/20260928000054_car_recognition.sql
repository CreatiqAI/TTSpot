-- Car-first onboarding: the recogniser (edge function recognize-car) reads the
-- first photo and fills these in. specs is a short factory spec line such as
-- "1.5 L NA · 102 hp · CVT"; body_style is hatchback / sedan / SUV / ...
-- Both optional, both editable, both dropped when the owner changes the
-- make or model the guess was for.
alter table public.cars add column if not exists specs text;
alter table public.cars add column if not exists body_style text;
