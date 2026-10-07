-- Dry-run test for supabase/migrations/20261008000119_expo_door.sql. Run the
-- migration and this file together inside begin ... rollback:
--   python -I q.py --tx supabase/migrations/20261008000119_expo_door.sql tool/expo_door_0119_dryrun.sql
-- Uses three existing members; everything is rolled back.
create temp table _out (n serial, k text, v text);
grant all on _out to authenticated;
grant all on sequence _out_n_seq to authenticated;

create temp table _ids (k text primary key, id uuid);
grant all on _ids to authenticated;
insert into _ids values
  ('host', '237c51b0-6931-4e9c-adab-8dce1597f077'),
  ('mem',  'ad72954f-905c-4e9c-a742-898f104d66ab'),
  ('mem2', 'db5c761c-b92d-46f9-8284-e31c23b56b1c');

-- a live event at 3.1, 101.6 and a future one
with x as (
  insert into public.events (organizer_id, title, event_type, starts_at, ends_at, venue_name, lat, lng, status)
  values ((select id from _ids where k='host'), 'Expo door test', 'meet', now() - interval '30 minutes', now() + interval '5 hours', 'Hall', 3.1, 101.6, 'active')
  returning id)
insert into _ids select 'ev', id from x;
with x as (
  insert into public.events (organizer_id, title, event_type, starts_at, ends_at, venue_name, lat, lng, status)
  values ((select id from _ids where k='host'), 'Expo later', 'meet', now() + interval '3 days', now() + interval '3 days 5 hours', 'Hall', 3.1, 101.6, 'active')
  returning id)
insert into _ids select 'ev2', id from x;
insert into public.referral_codes (code, user_id, event_id, created_by)
values ('ZZDR01', null, (select id from _ids where k='ev'), (select id from _ids where k='host')),
       ('ZZDR02', null, (select id from _ids where k='ev2'), (select id from _ids where k='host'));
insert into public.event_attendees (event_id, user_id) values ((select id from _ids where k='ev'), (select id from _ids where k='mem2'));

create or replace function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.try(p_k text, p_sql text) returns void language plpgsql as $$
declare r text;
begin
  execute p_sql into r;
  insert into _out (k, v) values (p_k, r);
exception when others then
  insert into _out (k, v) values (p_k, 'ERR: ' || sqlerrm);
end; $$;
grant execute on function pg_temp.try(text, text) to authenticated;
grant execute on function pg_temp.as_user(uuid) to authenticated;

set local role authenticated;

-- ---- host
select pg_temp.as_user((select id from _ids where k='host'));
select pg_temp.try('radius default', format('select public.event_checkin_radius(%L)::text', (select id from _ids where k='ev')));
select pg_temp.try('radius 2000', format('select public.set_event_checkin_radius(%L, 2000)::text', (select id from _ids where k='ev')));
select pg_temp.try('radius 6000 (host cap)', format('select public.set_event_checkin_radius(%L, 6000)::text', (select id from _ids where k='ev')));
select pg_temp.try('radius 10 (too small)', format('select public.set_event_checkin_radius(%L, 10)::text', (select id from _ids where k='ev')));
select pg_temp.try('form upsert via RLS', format($q$
  with x as (insert into public.event_forms (event_id, questions, consent_text, ask_contact, required)
  values (%L, '[{"id":"q1","label":"You are a","type":"one","options":["Trade buyer","Car owner"],"required":true},
                {"id":"q2","label":"Interests","type":"many","options":["Tyres","Audio","Paint"],"required":false},
                {"id":"q3","label":"Company","type":"text","required":false}]'::jsonb,
          'I agree to share these answers with the organizer.', true, true)
  on conflict (event_id) do update set questions = excluded.questions returning event_id) select count(*)::text from x$q$, (select id from _ids where k='ev')));

-- ---- member
select pg_temp.as_user((select id from _ids where k='mem'));
select pg_temp.try('mem sets radius', format('select public.set_event_checkin_radius(%L, 1000)::text', (select id from _ids where k='ev')));
select pg_temp.try('door not live', $q$select public.checkin_by_door('ZZDR02', null, null)::text$q$);
select pg_temp.try('door bad code', $q$select public.checkin_by_door('NOPE99', null, null)::text$q$);
select pg_temp.try('door no location', $q$select public.checkin_by_door('zzdr01', null, null)::text$q$);
select pg_temp.try('door far (5 km)', $q$select public.checkin_by_door('ZZDR01', 3.145, 101.6)::text$q$);
select pg_temp.try('door 1.5 km ok', $q$select public.checkin_by_door('ZZDR01', 3.1135, 101.6)::text$q$);
select pg_temp.try('door again', $q$select public.checkin_by_door('ZZDR01', null, null)::text$q$);
select pg_temp.try('hub', format('select public.event_hub(%L)::text', (select id from _ids where k='ev')));
select pg_temp.try('share on', format('select public.set_pass_share_contact(%L, true)::text', (select id from _ids where k='ev')));
select pg_temp.try('share on ev2 (not in)', format('select public.set_pass_share_contact(%L, true)::text', (select id from _ids where k='ev2')));
select pg_temp.try('read pass_code', format('select pass_code from public.checkins where event_id = %L limit 1', (select id from _ids where k='ev')));
select pg_temp.try('read entry_no', format('select string_agg(entry_no::text, %L) from public.checkins where event_id = %L', ',', (select id from _ids where k='ev')));
select pg_temp.try('insert own entry_no', format('insert into public.checkins (event_id, user_id, source, entry_no) values (%L, auth.uid(), %L, 7) returning 1', (select id from _ids where k='ev2'), 'qr'));
select pg_temp.try('reg missing required', format($q$select public.save_event_registration(%L, '{"q3":"ACME"}'::jsonb, true)::text$q$, (select id from _ids where k='ev')));
select pg_temp.try('reg bad option', format($q$select public.save_event_registration(%L, '{"q1":"Alien"}'::jsonb, true)::text$q$, (select id from _ids where k='ev')));
select pg_temp.try('reg ok', format($q$select public.save_event_registration(%L, '{"q1":"Car owner","q2":["Audio","Nope","Audio"],"q3":"  ACME  ","zz":"x"}'::jsonb, true)::text$q$, (select id from _ids where k='ev')));
select pg_temp.try('reg row', format('select answers::text || %L || contact_ok::text from public.event_registrations where event_id = %L and user_id = auth.uid()', ' ', (select id from _ids where k='ev')));
select pg_temp.try('hub after reg', format('select (public.event_hub(%L)->%L)::text', (select id from _ids where k='ev'), 'registration'));
select pg_temp.try('export as member', format('select count(*)::text from public.event_registrations_export(%L)', (select id from _ids where k='ev')));
select pg_temp.try('qr expired', format($q$select public.checkin_by_qr(%L, 'xx', 3.1, 101.6)::text$q$, (select id from _ids where k='ev')));

-- ---- member 2: going (not checked in) can register; door far
select pg_temp.as_user((select id from _ids where k='mem2'));
select pg_temp.try('mem2 reg (going)', format($q$select public.save_event_registration(%L, '{"q1":"Trade buyer"}'::jsonb, false)::text$q$, (select id from _ids where k='ev')));
select pg_temp.try('mem2 app insert (gps, 400 m)', format($q$with x as (insert into public.checkins (event_id, user_id, lat, lng, source) values (%L, auth.uid(), 3.1036, 101.6, 'manual')) select 'ok'$q$, (select id from _ids where k='ev')));
select pg_temp.try('mem2 delete own', format($q$with x as (delete from public.checkins where event_id = %L and user_id = auth.uid()) select 'ok'$q$, (select id from _ids where k='ev')));
select pg_temp.try('mem2 count via view', $q$select count(*)::text from public.events_with_counts limit 1$q$);
select pg_temp.try('mem2 hub', format('select public.event_hub(%L)::text', (select id from _ids where k='ev')));

-- ---- host export
select pg_temp.as_user((select id from _ids where k='host'));
select pg_temp.try('export', format('select json_agg(x)::text from public.event_registrations_export(%L) x', (select id from _ids where k='ev')));
select pg_temp.try('host hub', format('select public.event_hub(%L)::text', (select id from _ids where k='ev')));

reset role;
-- GPS self check-in uses greatest(500, area): 1.5 km away inside a 2 km area
select pg_temp.try('manual 1.5 km', format($q$insert into public.checkins (event_id, user_id, lat, lng, source) values (%L, %L, 3.1135, 101.6, 'manual') returning entry_no::text$q$,
  (select id from _ids where k='ev'), (select id from _ids where k='host')));
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
set local role authenticated;
select pg_temp.try('admin radius 60 km', format('select public.set_event_checkin_radius(%L, 60000)::text', (select id from _ids where k='ev')));
select pg_temp.try('admin radius null', format('select public.set_event_checkin_radius(%L, null)::text', (select id from _ids where k='ev')));
reset role;
select pg_temp.try('format_distance', $q$select public.format_distance(1234.5) || ' / ' || public.format_distance(349.6) || ' / ' || public.format_distance(5000)$q$);

select k, v from _out order by n;
