-- Top spots become the car cafés from docs/Malaysia_Car_Cafes_Reference.docx.
-- The old hand-picked spots stop being "top": the five nobody ever used are
-- deleted; the ones with check-ins, moments or meets stay as ordinary spots
-- (their history stays intact) and can still climb back through activity.
-- Coordinates: Google Geocoding, rooftop precision, 2026-09-28. Hours come
-- from the venues' own posts and may change.

update public.places set recommended = false, top_override = null where recommended;

delete from public.places p
 where p.name in ('Kuala Kubu Bharu to Fraser''s Hill', 'MAEPS Serdang', 'Pavilion Bukit Bintang', 'Putrajaya Boulevard', 'Stadium Bukit Jalil Carpark B')
   and not exists (select 1 from public.place_checkins c where c.place_id = p.id)
   and not exists (select 1 from public.spot_verifications v where v.place_id = p.id)
   and not exists (select 1 from public.events e where e.place_id = p.id)
   and not exists (select 1 from public.stories s where s.place_id = p.id)
   and not exists (select 1 from public.posts o where o.place_id = p.id);

insert into public.places (name, kind, lat, lng, recommended, top_override, description, tags)
select v.name, 'cafe', v.lat, v.lng, true, 'top', v.description, v.tags
from (values
  ('BWB Cafe', 3.1898982, 101.7055884,
   'Car-crowd café in Setapak. Wed–Sun 7 PM–12 AM, closed Mon–Tue. 2, Jalan Gombak, Taman Setapak, KL. Hours from the venue''s post; check before you drive.',
   array['car cafe','coffee','KL','Setapak','late night']),
  ('Togeya', 3.1873872, 101.6694565,
   'Late-night car café on Jalan Kuching, Segambut. Open daily from 1 PM: till 1 AM Mon–Thu, 2 AM Fri–Sun. 1471, Jalan Kuching, Kampung Pasir Segambut, KL.',
   array['car cafe','coffee','KL','Segambut','late night']),
  ('Carfe', 3.1243066, 101.6130135,
   'Car-themed café in Taman Sea, PJ. Tue–Fri 8 AM–9 PM, Sat–Sun 10 AM–9 PM, closed Mon. 1067, Jalan Jenjarum, Taman Sea, Petaling Jaya.',
   array['car cafe','coffee','Selangor','PJ','daytime']),
  ('Club de Piston', 3.0412746, 101.4517964,
   'Motoring hangout in Klang. Tue–Fri 5:30 PM–12 AM, Sat–Sun 2 PM–12 AM, closed Mon. 56, Jalan Raya Timur, Kawasan 1, Klang.',
   array['car cafe','coffee','Selangor','Klang','late night']),
  ('Johara Coffee & Matcha', 1.4961076, 103.8722857,
   'Late-night coffee and matcha spot in Seri Alam, Masai. Open daily 1 PM–3 AM. 6J, Jalan Suria, Bandar Baru Seri Alam, Masai, Johor.',
   array['car cafe','coffee','matcha','Johor','JB','late night']),
  ('Pedal & Rolls', 5.4652585, 100.2918107,
   'Café by the sea in Tanjung Bungah. Sun–Tue and Thu 12–4 PM and 5–10 PM; Fri–Sat 12–4 PM and 5 PM–12 AM; closed Wed. 1, Jalan Tanjung Bungah, Penang.',
   array['car cafe','coffee','Penang','seaside'])
) as v(name, lat, lng, description, tags)
where not exists (select 1 from public.places p where p.name = v.name);
