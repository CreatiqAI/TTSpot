-- Recommended spots around the Klang Valley + check-ins. Run LAST (after seed_location.sql).
-- Idempotent: keyed on place name.

-- Dress up the venues the seed already created
update public.places set
  recommended = true,
  description = 'The TTDI Thursday institution. Park behind, order the teh tarik kurang manis, and talk cars till the chairs go up.',
  tags = array['mamak', 'late night', 'weekly meet'],
  cover_url = coalesce(cover_url, 'https://picsum.photos/seed/srimelur/1200/800')
where lower(name) = lower('Mamak Sri Melur, TTDI');

update public.places set
  recommended = true,
  description = 'Open-air rooftop with the Pyramid lit up behind you. Saturday nights fill up by 10.',
  tags = array['carpark', 'night shots', 'saturday'],
  cover_url = coalesce(cover_url, 'https://picsum.photos/seed/sunwayroof/1200/800')
where lower(name) = lower('Sunway Pyramid Open Carpark');

update public.places set
  recommended = true,
  description = 'Wide, empty and lit. Rolling shots after 11 pm, stadium backdrop.',
  tags = array['carpark', 'rolling shots', 'midnight'],
  cover_url = coalesce(cover_url, 'https://picsum.photos/seed/bjalil/1200/800')
where lower(name) = lower('Stadium Bukit Jalil Carpark B');

update public.places set
  recommended = true,
  description = 'Sunrise stop before the Genting climb. Nasi lemak stalls open from 6.',
  tags = array['R&R', 'sunrise', 'touge start'],
  cover_url = coalesce(cover_url, 'https://picsum.photos/seed/gombakrr/1200/800')
where lower(name) = lower('Gombak R&R (Genting bound)');

update public.places set
  recommended = true,
  description = 'The one and only. Track days, drift practice and the Sepang 1000km.',
  tags = array['circuit', 'track day'],
  cover_url = coalesce(cover_url, 'https://picsum.photos/seed/sepang/1200/800')
where lower(name) = lower('Sepang International Circuit');

update public.places set
  recommended = true,
  description = 'Twin Towers in every shot. Weekend supercar traffic from 8 am.',
  tags = array['carpark', 'skyline', 'sunday'],
  cover_url = coalesce(cover_url, 'https://picsum.photos/seed/klccpark/1200/800')
where lower(name) = lower('KLCC Park Carpark');

-- New spots that are not meet venues (yet)
insert into public.places (name, kind, lat, lng, created_by, recommended, description, tags, cover_url)
select v.name, v.kind, v.lat, v.lng, '11111111-1111-1111-1111-111111111111', true, v.description, v.tags, v.cover
from (values
  ('Genting Sempah R&R', 'route', 3.3672, 101.7770, 'Top of the old Karak road. Coffee, corn in a cup and the best view of the climb you just did.', array['touge', 'viewpoint', 'sunrise'], 'https://picsum.photos/seed/sempah/1200/800'),
  ('Gohtong Jaya Lookout', 'route', 3.4030, 101.7990, 'Clouds below you on a good morning. Watch for the police at the bottom.', array['viewpoint', 'cool air', 'touge'], 'https://picsum.photos/seed/gohtong/1200/800'),
  ('Ulu Yam Dam Road', 'route', 3.4600, 101.6300, 'Smooth, quiet, and 40 minutes of corners. Breakfast at the Ulu Yam loh mee after.', array['touge', 'breakfast run', 'scenic'], 'https://picsum.photos/seed/uluyam/1200/800'),
  ('Seri Wawasan Bridge, Putrajaya', 'other', 2.9207, 101.6822, 'Lit up white at night. The classic Putrajaya car-and-bridge photo.', array['night shots', 'photo spot', 'putrajaya'], 'https://picsum.photos/seed/wawasan/1200/800'),
  ('Titiwangsa Lake Gardens', 'carpark', 3.1780, 101.7050, 'KL skyline across the water. Blue hour is 7:10 pm.', array['skyline', 'photo spot', 'blue hour'], 'https://picsum.photos/seed/titiwangsa/1200/800'),
  ('Bukit Ampang Lookout Point', 'other', 3.1620, 101.7690, 'Whole city at your feet. Small carpark, go early on Saturday night.', array['viewpoint', 'night', 'lepak'], 'https://picsum.photos/seed/ampanglookout/1200/800'),
  ('Kopitiam Jalan Ampang', 'mamak', 3.1390, 101.6869, 'Central meeting point before a convoy. Kaya toast, kopi, easy parking after 9.', array['mamak', 'breakfast', 'convoy start'], 'https://picsum.photos/seed/kopitiamampang/1200/800'),
  ('Bentong Town Mamak', 'mamak', 3.5210, 101.9080, 'The Karak reward. Everyone stops here on the way back from Cameron or Bentong.', array['mamak', 'karak', 'road trip'], 'https://picsum.photos/seed/bentong/1200/800')
) as v(name, kind, lat, lng, description, tags, cover)
where not exists (select 1 from public.places p where lower(p.name) = lower(v.name));

-- Kopitiam Jalan Ampang may already exist from the testing event; enrich it either way
update public.places set
  recommended = true,
  description = coalesce(description, 'Central meeting point before a convoy. Kaya toast, kopi, easy parking after 9.'),
  tags = case when cardinality(tags) = 0 then array['mamak', 'breakfast', 'convoy start'] else tags end,
  cover_url = coalesce(cover_url, 'https://picsum.photos/seed/kopitiamampang/1200/800')
where lower(name) = lower('Kopitiam Jalan Ampang');

-- Spot check-ins over the last month (bypass nothing: inserted directly, no distance rule needed for seed)
with u as (
  select unnest(array[
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333',
    '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555', '66666666-6666-6666-6666-666666666666'
  ]::uuid[]) as id
),
spots as (
  select p.id, p.lat, p.lng, p.name,
    case
      when p.name ilike 'Genting Sempah%' then 5
      when p.name ilike 'Gohtong%' then 4
      when p.name ilike 'Ulu Yam%' then 4
      when p.name ilike 'Seri Wawasan%' then 3
      when p.name ilike 'Titiwangsa%' then 3
      when p.name ilike 'Bukit Ampang%' then 3
      when p.name ilike 'Mamak Sri Melur%' then 6
      when p.name ilike 'Sunway Pyramid%' then 4
      when p.name ilike 'KLCC Park%' then 2
      when p.name ilike 'Bentong%' then 2
      when p.name ilike 'Kopitiam Jalan%' then 2
      else 0
    end as n
  from public.places p
)
insert into public.place_checkins (place_id, user_id, checked_in_at, lat, lng)
select s.id, u.id, now() - (interval '1 day' * (2 + (row_number() over (partition by s.id order by u.id)) * 3)), s.lat, s.lng
from spots s
join lateral (select id from u order by id limit s.n) u on true
where s.n > 0
on conflict do nothing;
