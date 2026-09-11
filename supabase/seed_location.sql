-- Demo data for the location layer. Run AFTER seed.sql and seed_social.sql.
-- Safe to re-run: everything is keyed on fixed ids or uses on conflict.

-- ------------------------------------------------------------------ users ---
-- amir    11111111-1111-1111-1111-111111111111
-- weiling 22222222-2222-2222-2222-222222222222
-- kumar   33333333-3333-3333-3333-333333333333
-- farah   44444444-4444-4444-4444-444444444444
-- jason   55555555-5555-5555-5555-555555555555
-- testing 66666666-6666-6666-6666-666666666666

-- ------------------------------------------------------------ friendships ---
insert into public.friendships (requester_id, addressee_id, status, accepted_at) values
  ('11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666', 'accepted', now() - interval '20 days'),
  ('66666666-6666-6666-6666-666666666666', '55555555-5555-5555-5555-555555555555', 'accepted', now() - interval '12 days'),
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted', now() - interval '40 days'),
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'accepted', now() - interval '30 days'),
  ('44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555', 'accepted', now() - interval '10 days'),
  ('33333333-3333-3333-3333-333333333333', '66666666-6666-6666-6666-666666666666', 'accepted', now() - interval '3 days'),
  ('22222222-2222-2222-2222-222222222222', '66666666-6666-6666-6666-666666666666', 'pending', null)
on conflict do nothing;

-- ------------------------------------------------------------- past meets ---
-- Six meets over the last eight weeks at three places the seed already has.
insert into public.events (id, organizer_id, title, description, event_type, cover_url, starts_at, venue_name, lat, lng, status) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'TTDI Thursday TT', 'Weekly teh tarik. Same table as always.', 'tt',
   'https://picsum.photos/seed/ttdi1/800/600', now() - interval '7 days 2 hours', 'Mamak Sri Melur, TTDI', 3.1390, 101.6300, 'active'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'TTDI Thursday TT', 'Weekly teh tarik.', 'tt',
   'https://picsum.photos/seed/ttdi2/800/600', now() - interval '14 days 2 hours', 'Mamak Sri Melur, TTDI', 3.1390, 101.6300, 'active'),
  ('cccccccc-0000-0000-0000-000000000003', '55555555-5555-5555-5555-555555555555', 'TTDI Thursday TT', 'Weekly teh tarik.', 'tt',
   'https://picsum.photos/seed/ttdi3/800/600', now() - interval '21 days 2 hours', 'Mamak Sri Melur, TTDI', 3.1390, 101.6300, 'active'),
  ('cccccccc-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'Sunway Saturday Night', 'Open carpark, all makes welcome.', 'meet',
   'https://picsum.photos/seed/sunway1/800/600', now() - interval '9 days 3 hours', 'Sunway Pyramid Open Carpark', 3.0733, 101.6067, 'active'),
  ('cccccccc-0000-0000-0000-000000000005', '22222222-2222-2222-2222-222222222222', 'Sunway Saturday Night', 'Open carpark, all makes welcome.', 'meet',
   'https://picsum.photos/seed/sunway2/800/600', now() - interval '37 days 3 hours', 'Sunway Pyramid Open Carpark', 3.0733, 101.6067, 'active'),
  ('cccccccc-0000-0000-0000-000000000006', '33333333-3333-3333-3333-333333333333', 'Bukit Jalil Midnight Run', 'Rolling shots after 11.', 'meet',
   'https://picsum.photos/seed/bj1/800/600', now() - interval '16 days 5 hours', 'Stadium Bukit Jalil Carpark B', 3.0580, 101.6910, 'active')
on conflict (id) do nothing;

-- A meet happening right now so the "Now" layer has something live.
insert into public.events (id, organizer_id, title, description, event_type, starts_at, ends_at, venue_name, lat, lng, status, is_instant) values
  ('cccccccc-0000-0000-0000-000000000010', '11111111-1111-1111-1111-111111111111', 'TT now @ Mamak Sri Melur, TTDI', null, 'tt',
   now() - interval '35 minutes', now() + interval '2 hours 25 minutes', 'Mamak Sri Melur, TTDI', 3.1390, 101.6300, 'active', true)
on conflict (id) do nothing;

-- RSVPs for the past meets
insert into public.event_attendees (event_id, user_id)
select e.id, u.id
from public.events e
cross join (values
  ('11111111-1111-1111-1111-111111111111'::uuid), ('22222222-2222-2222-2222-222222222222'), ('33333333-3333-3333-3333-333333333333'),
  ('44444444-4444-4444-4444-444444444444'), ('55555555-5555-5555-5555-555555555555'), ('66666666-6666-6666-6666-666666666666')) as u(id)
where e.id::text like 'cccccccc-%'
  and not (e.id = 'cccccccc-0000-0000-0000-000000000005' and u.id in ('66666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444'))
  and not (e.id = 'cccccccc-0000-0000-0000-000000000006' and u.id in ('22222222-2222-2222-2222-222222222222'))
on conflict do nothing;

-- Check-ins (bypass the time-window trigger: seed data is historical)
alter table public.checkins disable trigger checkins_before_insert;
insert into public.checkins (event_id, user_id, checked_in_at, lat, lng, source)
select a.event_id, a.user_id, e.starts_at + interval '20 minutes', e.lat, e.lng, 'auto'
from public.event_attendees a
join public.events e on e.id = a.event_id
where e.id::text like 'cccccccc-%'
  and not (e.id = 'cccccccc-0000-0000-0000-000000000003' and a.user_id = '66666666-6666-6666-6666-666666666666')  -- testing RSVP'd but skipped this one
  and not (e.id = 'cccccccc-0000-0000-0000-000000000010' and a.user_id <> '11111111-1111-1111-1111-111111111111')
on conflict do nothing;
alter table public.checkins enable trigger checkins_before_insert;

-- Moments from those meets (expired on the map, kept in the album)
insert into public.stories (id, author_id, photo_url, caption, created_at, expires_at, event_id) values
  ('dddddddd-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'https://picsum.photos/seed/m1/720/1280', 'Full house tonight', now() - interval '7 days 1 hour', now() - interval '6 days 1 hour', 'cccccccc-0000-0000-0000-000000000001'),
  ('dddddddd-0000-0000-0000-000000000002', '55555555-5555-5555-5555-555555555555', 'https://picsum.photos/seed/m2/720/1280', 'S15 finally out of the workshop', now() - interval '7 days 30 minutes', now() - interval '6 days 30 minutes', 'cccccccc-0000-0000-0000-000000000001'),
  ('dddddddd-0000-0000-0000-000000000003', '66666666-6666-6666-6666-666666666666', 'https://picsum.photos/seed/m3/720/1280', null, now() - interval '7 days', now() - interval '6 days', 'cccccccc-0000-0000-0000-000000000001'),
  ('dddddddd-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'https://picsum.photos/seed/m4/720/1280', 'Row of GR86s', now() - interval '9 days 2 hours', now() - interval '8 days 2 hours', 'cccccccc-0000-0000-0000-000000000004'),
  ('dddddddd-0000-0000-0000-000000000005', '33333333-3333-3333-3333-333333333333', 'https://picsum.photos/seed/m5/720/1280', 'Rolling shot practice', now() - interval '16 days 4 hours', now() - interval '15 days 4 hours', 'cccccccc-0000-0000-0000-000000000006'),
  ('dddddddd-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', 'https://picsum.photos/seed/m6/720/1280', 'Teh tarik o clock', now() - interval '20 minutes', now() + interval '23 hours 40 minutes', 'cccccccc-0000-0000-0000-000000000010')
on conflict (id) do nothing;

-- ------------------------------------------------------------- live pins ---
insert into public.user_locations (user_id, lat, lng, ghost, place_id, event_id, updated_at, expires_at) values
  ('11111111-1111-1111-1111-111111111111', 3.1391, 101.6302, false,
   (select id from public.places where lower(name) = lower('Mamak Sri Melur, TTDI') limit 1),
   'cccccccc-0000-0000-0000-000000000010', now() - interval '4 minutes', now() + interval '23 hours'),
  ('55555555-5555-5555-5555-555555555555', 3.0735, 101.6070, false,
   (select id from public.places where lower(name) = lower('Sunway Pyramid Open Carpark') limit 1),
   null, now() - interval '48 minutes', now() + interval '23 hours'),
  ('33333333-3333-3333-3333-333333333333', 3.1579, 101.7123, false, null, null, now() - interval '3 hours', now() + interval '21 hours'),
  ('22222222-2222-2222-2222-222222222222', 3.1024, 101.4622, true, null, null, now() - interval '10 minutes', now() + interval '23 hours')
on conflict (user_id) do update
  set lat = excluded.lat, lng = excluded.lng, ghost = excluded.ghost, place_id = excluded.place_id,
      event_id = excluded.event_id, updated_at = excluded.updated_at, expires_at = excluded.expires_at;
