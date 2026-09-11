-- =============================================================================
-- Dev seed: social content on top of seed.sql (posts, follows, likes, comments,
-- stories, a club, build log). Safe to re-run: guarded by "not exists" checks.
-- =============================================================================

-- ---- follows -----------------------------------------------------------------
insert into public.follows (follower_id, followee_id) values
  ('66666666-6666-6666-6666-666666666666', '11111111-1111-1111-1111-111111111111'),
  ('66666666-6666-6666-6666-666666666666', '22222222-2222-2222-2222-222222222222'),
  ('66666666-6666-6666-6666-666666666666', '55555555-5555-5555-5555-555555555555'),
  ('11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666'),
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111'),
  ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222'),
  ('55555555-5555-5555-5555-555555555555', '66666666-6666-6666-6666-666666666666')
on conflict do nothing;

-- ---- club --------------------------------------------------------------------
insert into public.clubs (id, name, handle, description, avatar_url, home_state, owner_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Myvi Owners KL', 'myvi_kl', 'Daily drivers, turbo builds, kopi every Thursday. Respect the carpark.', 'https://picsum.photos/seed/myviclub/300/300', 'Kuala Lumpur', '11111111-1111-1111-1111-111111111111')
on conflict (id) do nothing;
insert into public.club_members (club_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '66666666-6666-6666-6666-666666666666', 'member'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555', 'member')
on conflict do nothing;
update public.events set club_id = 'aaaaaaaa-0000-0000-0000-000000000001'
where title = 'Perodua Owners Mega Meet' and club_id is null;

-- ---- posts -------------------------------------------------------------------
-- regular posts (car-tagged, so Car of the Week has candidates)
insert into public.posts (id, author_id, kind, caption, photo_urls, cover_aspect, car_id, place_id, created_at)
select 'bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'post',
       'New Rota wheels on the Myvi. 15x7 +35, fits without rubbing. Next up: coilovers.',
       array['https://picsum.photos/seed/myvipost1/900/1125', 'https://picsum.photos/seed/myvipost2/900/1125'], 0.8,
       (select id from public.cars where owner_id = '11111111-1111-1111-1111-111111111111' limit 1),
       (select id from public.places where lower(name) like 'mamak sri melur%' limit 1),
       now() - interval '2 days'
where not exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000001');

insert into public.posts (id, author_id, kind, caption, photo_urls, cover_aspect, car_id, created_at)
select 'bbbbbbbb-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'post',
       'Sepang open pit last weekend. 2:38 on RE71RS, still lots to find in T4. Who else was there?',
       array['https://picsum.photos/seed/gr86track/1200/800'], 1.5,
       (select id from public.cars where owner_id = '22222222-2222-2222-2222-222222222222' limit 1),
       now() - interval '1 day 4 hours'
where not exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000002');

insert into public.posts (id, author_id, kind, caption, photo_urls, cover_aspect, car_id, created_at)
select 'bbbbbbbb-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 'post',
       'Evo IX, 17 years and counting. GT30R finally dialled in at 1.4 bar. 480whp on the Dynojet.',
       array['https://picsum.photos/seed/evo9dyno/1000/1000'], 1.0,
       (select id from public.cars where owner_id = '33333333-3333-3333-3333-333333333333' limit 1),
       now() - interval '20 hours'
where not exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000003');

insert into public.posts (id, author_id, kind, caption, photo_urls, cover_aspect, car_id, created_at)
select 'bbbbbbbb-0000-0000-0000-000000000004', '44444444-4444-4444-4444-444444444444', 'post',
       'Championship White never gets old. Detailed for the charity drive this weekend.',
       array['https://picsum.photos/seed/fk8white/900/1200'], 0.75,
       (select id from public.cars where owner_id = '44444444-4444-4444-4444-444444444444' limit 1),
       now() - interval '9 hours'
where not exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000004');

insert into public.posts (id, author_id, kind, caption, photo_urls, cover_aspect, car_id, event_id, created_at)
select 'bbbbbbbb-0000-0000-0000-000000000005', '55555555-5555-5555-5555-555555555555', 'post',
       'S15 at Sunway last night. Thanks everyone who came, 40+ cars and zero drama.',
       array['https://picsum.photos/seed/s15night/1000/1250', 'https://picsum.photos/seed/s15night2/1000/1250', 'https://picsum.photos/seed/s15night3/1000/1250'], 0.8,
       (select id from public.cars where owner_id = '55555555-5555-5555-5555-555555555555' limit 1),
       (select id from public.events where title = 'Sunway Night Meet' limit 1),
       now() - interval '5 hours'
where not exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000005');

-- spotted
insert into public.posts (id, author_id, kind, caption, photo_urls, cover_aspect, lat, lng, created_at)
select 'bbbbbbbb-0000-0000-0000-000000000006', '55555555-5555-5555-5555-555555555555', 'spotted',
       'Clean E46 M3 at Bangsar Village this evening. Owner, claim it!',
       array['https://picsum.photos/seed/spottedm3/1000/750'], 1.33, 3.1290, 101.6710,
       now() - interval '3 hours'
where not exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000006');

-- poll
insert into public.posts (id, author_id, kind, title, caption, poll_options, poll_ends_at, created_at)
select 'bbbbbbbb-0000-0000-0000-000000000007', '22222222-2222-2222-2222-222222222222', 'poll',
       'Track tyre for a street GR86?', 'Daily driven, 4 track days a year. Budget is not unlimited.',
       '[{"text":"Bridgestone RE71RS","photo_url":null},{"text":"Yokohama AD09","photo_url":null},{"text":"Michelin PS4S (all-rounder)","photo_url":null}]'::jsonb,
       now() + interval '2 days',
       now() - interval '12 hours'
where not exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000007');

-- guide
insert into public.posts (id, author_id, kind, title, caption, photo_urls, cover_aspect, guide_stops, created_at)
select 'bbbbbbbb-0000-0000-0000-000000000008', '33333333-3333-3333-3333-333333333333', 'guide',
       'Ulu Yam sunrise loop (2.5 hours from KL)',
       E'Leave KL by 6am. Petronas Batu Caves for fuel and coffee, then the B-road through Ulu Yam. Breakfast at Ulu Yam town (the loh mee place opens 7am). Back down via Batang Kali by 9 before the traffic.\n\nKeep it sane on the touge. Locals use this road.',
       array['https://picsum.photos/seed/uluyam1/1200/800', 'https://picsum.photos/seed/uluyam2/1200/800'], 1.5,
       '[{"name":"Petronas Batu Caves","lat":3.2379,"lng":101.6841},{"name":"Ulu Yam Bharu","lat":3.4180,"lng":101.6530},{"name":"Batang Kali","lat":3.4650,"lng":101.6360}]'::jsonb,
       now() - interval '1 day'
where not exists (select 1 from public.posts where id = 'bbbbbbbb-0000-0000-0000-000000000008');

-- ---- likes / saves / votes / comments ---------------------------------------
insert into public.post_likes (post_id, user_id)
select p.id, u.id
from public.posts p
cross join (values ('11111111-1111-1111-1111-111111111111'::uuid),('22222222-2222-2222-2222-222222222222'),('33333333-3333-3333-3333-333333333333'),('44444444-4444-4444-4444-444444444444'),('55555555-5555-5555-5555-555555555555'),('66666666-6666-6666-6666-666666666666')) as u(id)
where p.id::text like 'bbbbbbbb-%' and p.author_id <> u.id
  and (abs(hashtext(p.id::text || u.id::text)) % 3) <> 0
on conflict do nothing;

insert into public.post_saves (post_id, user_id) values
  ('bbbbbbbb-0000-0000-0000-000000000008', '66666666-6666-6666-6666-666666666666')
on conflict do nothing;

insert into public.poll_votes (post_id, user_id, option_index) values
  ('bbbbbbbb-0000-0000-0000-000000000007', '11111111-1111-1111-1111-111111111111', 0),
  ('bbbbbbbb-0000-0000-0000-000000000007', '33333333-3333-3333-3333-333333333333', 0),
  ('bbbbbbbb-0000-0000-0000-000000000007', '44444444-4444-4444-4444-444444444444', 2),
  ('bbbbbbbb-0000-0000-0000-000000000007', '55555555-5555-5555-5555-555555555555', 1)
on conflict do nothing;

insert into public.post_comments (post_id, user_id, body)
select 'bbbbbbbb-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555', 'Fitment looks spot on. What tyre size?'
where not exists (select 1 from public.post_comments where post_id = 'bbbbbbbb-0000-0000-0000-000000000001');
insert into public.post_comments (post_id, user_id, body)
select 'bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '195/50. Slight stretch, no rub.'
where (select count(*) from public.post_comments where post_id = 'bbbbbbbb-0000-0000-0000-000000000001') < 2;
insert into public.post_comments (post_id, user_id, body)
select 'bbbbbbbb-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'That is a serious number. See you at Sepang.'
where not exists (select 1 from public.post_comments where post_id = 'bbbbbbbb-0000-0000-0000-000000000003');
insert into public.post_comments (post_id, user_id, body)
select 'bbbbbbbb-0000-0000-0000-000000000006', '44444444-4444-4444-4444-444444444444', 'I know this car! Tagging the owner.'
where not exists (select 1 from public.post_comments where post_id = 'bbbbbbbb-0000-0000-0000-000000000006');

-- ---- stories (24h) -----------------------------------------------------------
insert into public.stories (author_id, photo_url, caption)
select '11111111-1111-1111-1111-111111111111', 'https://picsum.photos/seed/story-amir/900/1600', 'TTDI tonight 9pm, who is in?'
where not exists (select 1 from public.stories where author_id = '11111111-1111-1111-1111-111111111111' and expires_at > now());
insert into public.stories (author_id, photo_url, caption)
select '44444444-4444-4444-4444-444444444444', 'https://picsum.photos/seed/story-farah/900/1600', 'Charity drive prep 🧼'
where not exists (select 1 from public.stories where author_id = '44444444-4444-4444-4444-444444444444' and expires_at > now());
insert into public.stories (author_id, photo_url, caption)
select '22222222-2222-2222-2222-222222222222', 'https://picsum.photos/seed/story-weiling/900/1600', null
where not exists (select 1 from public.stories where author_id = '22222222-2222-2222-2222-222222222222' and expires_at > now());

-- ---- build log for Amir's Myvi ----------------------------------------------
insert into public.car_mods (car_id, title, description, cost, done_on, photo_urls)
select c.id, 'Rota Grid 15x7 +35', 'Gunmetal. 195/50 GT Radial Champiro SX2.', 2800, current_date - 40, array['https://picsum.photos/seed/rota/800/600']
from public.cars c where c.owner_id = '11111111-1111-1111-1111-111111111111'
  and not exists (select 1 from public.car_mods m where m.car_id = c.id and m.title like 'Rota%')
limit 1;
insert into public.car_mods (car_id, title, description, cost, done_on, photo_urls)
select c.id, 'Custom cat-back exhaust', 'Stainless, 2-inch piping, single tip. Not loud, just deeper.', 1200, current_date - 120, '{}'
from public.cars c where c.owner_id = '11111111-1111-1111-1111-111111111111'
  and not exists (select 1 from public.car_mods m where m.car_id = c.id and m.title like 'Custom cat-back%')
limit 1;
insert into public.car_mods (car_id, title, description, cost, done_on, photo_urls)
select c.id, 'Stock', 'Picked up brand new from Perodua Glenmarie.', null, current_date - 400, '{}'
from public.cars c where c.owner_id = '11111111-1111-1111-1111-111111111111'
  and not exists (select 1 from public.car_mods m where m.car_id = c.id and m.title = 'Stock')
limit 1;

-- ---- a DM so the inbox isn't empty ------------------------------------------
do $$
declare conv uuid;
begin
  select c.id into conv from public.conversations c
  where c.kind = 'dm'
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = '11111111-1111-1111-1111-111111111111')
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = '66666666-6666-6666-6666-666666666666');
  if conv is null then
    insert into public.conversations (kind) values ('dm') returning id into conv;
    insert into public.conversation_members (conversation_id, user_id) values (conv, '11111111-1111-1111-1111-111111111111'), (conv, '66666666-6666-6666-6666-666666666666');
    insert into public.messages (conversation_id, sender_id, body, created_at) values
      (conv, '11111111-1111-1111-1111-111111111111', 'Bro you coming TTDI Thursday?', now() - interval '3 hours'),
      (conv, '11111111-1111-1111-1111-111111111111', 'Parking behind the mamak, dont block the lane', now() - interval '2 hours 55 minutes');
  end if;
end $$;
