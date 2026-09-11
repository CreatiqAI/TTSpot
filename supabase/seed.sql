-- =============================================================================
-- Dev seed: 5 fake organizers + 15 events around Klang Valley
-- Runs automatically with `supabase db reset` (local).
-- For a remote project: paste into SQL Editor (runs as postgres, bypasses RLS).
-- Dates are relative to now() so the map always looks alive.
-- Fake users: password is "password123" for all (only works locally).
-- =============================================================================

-- ---- fake auth users (fixed UUIDs so seed is idempotent) --------------------
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'amir@example.com',  crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Amir Hakim"}', now(), now()),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'weiling@example.com', crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Tan Wei Ling"}', now(), now()),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'kumar@example.com', crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Kumar Selvam"}', now(), now()),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'farah@example.com', crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Farah Nadia"}', now(), now()),
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'jason@example.com', crypt('password123', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Jason Lim"}', now(), now())
on conflict (id) do nothing;

-- Dev test account: log in as "testing" / 12341234 (debug builds expand it to testing@ttspot.my)
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'testing@ttspot.my', crypt('12341234', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"full_name":"Testing"}', now(), now())
on conflict (id) do nothing;

-- GoTrue expects these token columns to be '' not NULL, and password login
-- needs an identities row. Without this, sign-in returns HTTP 500.
update auth.users set
  confirmation_token = coalesce(confirmation_token, ''),
  recovery_token = coalesce(recovery_token, ''),
  email_change = coalesce(email_change, ''),
  email_change_token_new = coalesce(email_change_token_new, ''),
  email_change_token_current = coalesce(email_change_token_current, ''),
  phone_change = coalesce(phone_change, ''),
  phone_change_token = coalesce(phone_change_token, ''),
  reauthentication_token = coalesce(reauthentication_token, ''),
  is_sso_user = coalesce(is_sso_user, false),
  is_anonymous = coalesce(is_anonymous, false)
where email like '%@example.com' or email = 'testing@ttspot.my';

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text, 'email',
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       now(), now(), now()
from auth.users u
where (u.email like '%@example.com' or u.email = 'testing@ttspot.my')
  and not exists (select 1 from auth.identities i where i.user_id = u.id);

-- ---- profiles (trigger created bare rows; fill in onboarding fields) -------
insert into public.profiles (id, username, display_name, bio, avatar_url, home_state)
values
  ('11111111-1111-1111-1111-111111111111', 'amir_hakim',  'Amir Hakim',   'Myvi turbo enjoyer. TTDI regular.',            'https://i.pravatar.cc/200?img=12', 'Selangor'),
  ('22222222-2222-2222-2222-222222222222', 'weiling_gr',  'Tan Wei Ling', 'GR86 daily. Track day addict.',                 'https://i.pravatar.cc/200?img=47', 'Kuala Lumpur'),
  ('33333333-3333-3333-3333-333333333333', 'kumar_evo',   'Kumar Selvam', 'Evo IX since 2009. Convoy organiser.',          'https://i.pravatar.cc/200?img=33', 'Selangor'),
  ('44444444-4444-4444-4444-444444444444', 'farah_civic', 'Farah Nadia',  'FK8 Type R. Charity drives & TT sessions.',     'https://i.pravatar.cc/200?img=25', 'Putrajaya'),
  ('55555555-5555-5555-5555-555555555555', 'jason_s15',   'Jason Lim',    'S15 Silvia. JDM meets around Klang Valley.',    'https://i.pravatar.cc/200?img=53', 'Selangor'),
  ('66666666-6666-6666-6666-666666666666', 'testing',     'Testing',      'Dev test account.',                             null,                               'Kuala Lumpur')
on conflict (id) do update set
  username = excluded.username, display_name = excluded.display_name,
  bio = excluded.bio, avatar_url = excluded.avatar_url, home_state = excluded.home_state;

-- ---- a few cars so garages aren't empty -------------------------------------
insert into public.cars (owner_id, make, model, year, description, photo_urls) values
  ('11111111-1111-1111-1111-111111111111', 'Perodua', 'Myvi', 2019, '1.5 AV, GT Radial, custom exhaust.', array['https://picsum.photos/seed/myvi1/800/600']),
  ('22222222-2222-2222-2222-222222222222', 'Toyota', 'GR86', 2023, 'Stock-ish. Coilovers + RE71RS.', array['https://picsum.photos/seed/gr86/800/600']),
  ('33333333-3333-3333-3333-333333333333', 'Mitsubishi', 'Lancer Evolution IX', 2006, 'GT30R, 480whp, Cusco cage.', array['https://picsum.photos/seed/evo9/800/600', 'https://picsum.photos/seed/evo9b/800/600']),
  ('44444444-4444-4444-4444-444444444444', 'Honda', 'Civic Type R FK8', 2020, 'Championship White. Spoon N1.', array['https://picsum.photos/seed/fk8/800/600']),
  ('55555555-5555-5555-5555-555555555555', 'Nissan', 'Silvia S15', 2001, 'SR20DET, Garrett 2871R, Work Meisters.', array['https://picsum.photos/seed/s15/800/600']);

-- ---- 15 events around Klang Valley ------------------------------------------
-- Locations (lat, lng):
--   TTDI 3.1390,101.6300 | Sunway 3.0733,101.6067 | Putrajaya 2.9264,101.6964
--   Setia Alam 3.1024,101.4622 | Genting 3.4232,101.7936 | Bukit Jalil 3.0580,101.6910
--   Cyberjaya 2.9213,101.6559 | Sepang 2.7608,101.7380 | Bangsar 3.1290,101.6710
--   Shah Alam 3.0733,101.5185 | KLCC 3.1579,101.7123 | Ulu Yam 3.4180,101.6530

insert into public.events (organizer_id, title, description, event_type, cover_url, starts_at, venue_name, lat, lng, max_attendees, status) values
  -- today / tomorrow
  ('11111111-1111-1111-1111-111111111111', 'TTDI Thursday TT',
   'Weekly teh tarik session. All makes welcome. Park behind the mamak, don''t block the road.',
   'tt', 'https://picsum.photos/seed/ttdi-tt/600/800',
   date_trunc('day', now()) + interval '21 hours', 'Mamak Sri Melur, TTDI', 3.1390, 101.6300, null, 'active'),

  ('55555555-5555-5555-5555-555555555555', 'Sunway Night Meet',
   'JDM + Euro night meet at the open carpark. Bring your own chairs. No revving.',
   'meet', 'https://picsum.photos/seed/sunway-meet/600/800',
   date_trunc('day', now()) + interval '1 day 20 hours', 'Sunway Pyramid Open Carpark', 3.0733, 101.6067, 80, 'active'),

  -- this weekend (next Saturday / Sunday)
  ('33333333-3333-3333-3333-333333333333', 'Genting Sunrise Convoy',
   'Meet at Gombak R&R 5:30am, roll up Genting together. Spirited but safe. Breakfast at the top.',
   'convoy', 'https://picsum.photos/seed/genting-convoy/600/800',
   date_trunc('week', now()) + interval '5 days 5 hours 30 minutes', 'Gombak R&R (Genting bound)', 3.4232, 101.7936, 30, 'active'),

  ('22222222-2222-2222-2222-222222222222', 'Setia Alam Cars & Kopi',
   'Morning coffee meet. Family friendly, lots of parking. Photographers welcome.',
   'meet', 'https://picsum.photos/seed/setia-kopi/600/800',
   date_trunc('week', now()) + interval '6 days 8 hours', 'Setia City Mall, Setia Alam', 3.1024, 101.4622, null, 'active'),

  ('44444444-4444-4444-4444-444444444444', 'Putrajaya Charity Drive',
   'Donation drive for Rumah Kasih. RM50 entry goes fully to the home. Convoy leaves 9am sharp.',
   'charity', 'https://picsum.photos/seed/putrajaya-charity/600/800',
   date_trunc('week', now()) + interval '6 days 9 hours', 'Dataran Putrajaya', 2.9264, 101.6964, 60, 'active'),

  -- next 2 weeks
  ('22222222-2222-2222-2222-222222222222', 'Sepang Track Day (Open Pit)',
   'Open pit lane session, 3 x 20 min stints. Helmet + long sleeves mandatory. Register via organiser.',
   'trackday', 'https://picsum.photos/seed/sepang-track/600/800',
   now() + interval '9 days', 'Sepang International Circuit', 2.7608, 101.7380, 40, 'active'),

  ('55555555-5555-5555-5555-555555555555', 'Bukit Jalil Retro Meet',
   'Pre-2005 cars only. Kancil to Skyline, semua boleh. Best-in-show voted by attendees.',
   'meet', 'https://picsum.photos/seed/bj-retro/600/800',
   now() + interval '10 days', 'Stadium Bukit Jalil Carpark B', 3.0580, 101.6910, null, 'active'),

  ('11111111-1111-1111-1111-111111111111', 'Bangsar Late Night TT',
   'Post-midnight teh tarik run. Chill vibes, no drama.',
   'tt', 'https://picsum.photos/seed/bangsar-tt/600/800',
   now() + interval '12 days', 'Devi''s Corner, Bangsar', 3.1290, 101.6710, null, 'active'),

  ('33333333-3333-3333-3333-333333333333', 'Ulu Yam Touge Breakfast Run',
   'Early morning drive through Ulu Yam. Meet at Batu Caves Petronas 6am.',
   'convoy', 'https://picsum.photos/seed/uluyam/600/800',
   now() + interval '13 days', 'Petronas Batu Caves', 3.4180, 101.6530, 25, 'active'),

  -- this month-ish
  ('44444444-4444-4444-4444-444444444444', 'Cyberjaya EV & Hybrid Meet',
   'Tesla, BYD, Ioniq, Prius, whatever. Chargers available on site.',
   'meet', 'https://picsum.photos/seed/cyber-ev/600/800',
   now() + interval '16 days', 'Tamarind Square, Cyberjaya', 2.9213, 101.6559, null, 'active'),

  ('55555555-5555-5555-5555-555555555555', 'KLCC Supercar Sunday',
   'Official club gathering. Supercars & exotics. Public welcome to view from 10am.',
   'official', 'https://picsum.photos/seed/klcc-super/600/800',
   now() + interval '18 days', 'KLCC Park Carpark', 3.1579, 101.7123, 100, 'active'),

  ('22222222-2222-2222-2222-222222222222', 'Shah Alam Autokhana',
   'Cone course in the stadium carpark. Timed runs, any car. Bring a helmet.',
   'trackday', 'https://picsum.photos/seed/shahalam-auto/600/800',
   now() + interval '21 days', 'Stadium Shah Alam Carpark', 3.0733, 101.5185, 50, 'active'),

  ('11111111-1111-1111-1111-111111111111', 'Perodua Owners Mega Meet',
   'Myvi, Axia, Bezza, Ativa, Alza. Official Perodua club event with merch booth.',
   'official', 'https://picsum.photos/seed/perodua-mega/600/800',
   now() + interval '25 days', 'Setia Alam Convention Centre', 3.1050, 101.4650, 200, 'active'),

  -- one cancelled (to test filtering) and one past (to test "past" tab)
  ('33333333-3333-3333-3333-333333333333', 'Sunway Drift Demo (CANCELLED)',
   'Cancelled due to venue permit issue. Will reschedule.',
   'official', 'https://picsum.photos/seed/sunway-drift/600/800',
   now() + interval '5 days', 'Sunway Lagoon Carpark', 3.0700, 101.6080, null, 'cancelled'),

  ('44444444-4444-4444-4444-444444444444', 'Putrajaya Charity Drive (Last Month)',
   'Thanks to everyone who came! RM12,400 raised.',
   'charity', 'https://picsum.photos/seed/putrajaya-past/600/800',
   now() - interval '30 days', 'Dataran Putrajaya', 2.9264, 101.6964, null, 'active');

-- ---- RSVPs so attendee counts / avatars show up ------------------------------
insert into public.event_attendees (event_id, user_id)
select e.id, p.id
from public.events e
cross join public.profiles p
where e.status = 'active'
  and e.starts_at > now()
  and p.id <> e.organizer_id
  and (abs(hashtext(e.id::text || p.id::text)) % 3) <> 0   -- pseudo-random ~2/3 join
on conflict do nothing;

-- ---- a few comments ----------------------------------------------------------
insert into public.event_comments (event_id, user_id, body)
select e.id, '55555555-5555-5555-5555-555555555555', 'Confirm coming! Bringing 2 friends.'
from public.events e where e.title = 'TTDI Thursday TT';

insert into public.event_comments (event_id, user_id, body)
select e.id, '22222222-2222-2222-2222-222222222222', 'What time is rollout from Gombak? 5:30 sharp or 5:45?'
from public.events e where e.title = 'Genting Sunrise Convoy';

insert into public.event_comments (event_id, user_id, body)
select e.id, '33333333-3333-3333-3333-333333333333', '5:30 sharp. Latecomers can catch up at Gohtong.'
from public.events e where e.title = 'Genting Sunrise Convoy';
