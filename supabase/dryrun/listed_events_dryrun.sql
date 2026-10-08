-- Dry run for 20261009000127_listed_events.sql. Run AFTER the migration, inside
-- one transaction that is rolled back:
--   python q.py --tx supabase/migrations/20261009000127_listed_events.sql supabase/dryrun/listed_events_dryrun.sql
-- Proves: a past listing by TiTi adds no 'organizer' count or tier (a normal
-- meet by the same account does); the view carries the three columns and
-- keeps security_invoker and its grants; bad urls and long names are
-- rejected; a signed-in non-admin can't create a listing or change listing
-- columns but can still insert and edit a plain event; profile_meets still
-- runs. The last statement selects every check.
-- 2026-10-09 result: 0/0, none, row ok, place made, 1, 1, rejected x4, ok x2.
create temp table _out (k text, v text);
grant all on _out to authenticated;

-- A fresh throwaway user with no badges, and TiTi.
do $$
declare
  v_titi uuid := '1abc1b14-0628-4bbf-bf19-138bb5968d4b';
  v_user uuid;
  v_ev uuid;
  v_ev2 uuid;
  v_before int;
begin
  -- A past listing by TiTi: no organizer count, no tier.
  v_before := public.badge_count(v_titi, 'organizer');
  insert into public.events (organizer_id, title, event_type, starts_at, ends_at, venue_name, lat, lng, is_listing, organiser_name, source_url)
  values (v_titi, 'Test MotoGP listing', 'trackday', now() - interval '2 hours', now() + interval '6 hours', 'Sepang International Circuit', 2.7608, 101.7382, true, 'Sepang International Circuit', 'https://www.sepangcircuit.com')
  returning id into v_ev;
  insert into _out values ('listing organizer count before/after', v_before || '/' || public.badge_count(v_titi, 'organizer'));
  insert into _out values ('listing tier for titi', coalesce((select tier::text from public.badge_tiers where user_id = v_titi and badge_id = 'organizer'), 'none'));
  insert into _out values ('view row', (select json_build_object('is_listing', is_listing, 'organiser_name', organiser_name, 'source_url', source_url, 'host_is_organizer', host_is_organizer)::text from public.events_with_counts where id = v_ev));
  insert into _out values ('place made', (select (place_id is not null)::text from public.events where id = v_ev));

  -- Control: a normal past meet by the same account does count.
  insert into public.events (organizer_id, title, event_type, starts_at, venue_name, lat, lng)
  values (v_titi, 'Test normal meet', 'meet', now() - interval '1 hour', 'Test carpark', 3.1, 101.6)
  returning id into v_ev2;
  insert into _out values ('normal meet organizer count', public.badge_count(v_titi, 'organizer')::text);
  insert into _out values ('normal meet tier for titi', coalesce((select tier::text from public.badge_tiers where user_id = v_titi and badge_id = 'organizer'), 'none'));

  -- Bad url / long name rejected.
  begin
    insert into public.events (organizer_id, title, event_type, starts_at, venue_name, lat, lng, is_listing, source_url)
    values (v_titi, 'x', 'meet', now() + interval '1 day', 'x', 3, 101, true, 'javascript:alert(1)');
    insert into _out values ('bad url', 'ACCEPTED (bad)');
  exception when check_violation then insert into _out values ('bad url', 'rejected');
  end;
  begin
    insert into public.events (organizer_id, title, event_type, starts_at, venue_name, lat, lng, is_listing, organiser_name)
    values (v_titi, 'x', 'meet', now() + interval '1 day', 'x', 3, 101, true, repeat('a', 121));
    insert into _out values ('long name', 'ACCEPTED (bad)');
  exception when check_violation then insert into _out values ('long name', 'rejected');
  end;
end $$;

-- As a signed-in member (TiTi is not an admin): can't list or turn a meet into a listing.
select set_config('request.jwt.claims', json_build_object('sub', '1abc1b14-0628-4bbf-bf19-138bb5968d4b', 'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare v_id uuid;
begin
  begin
    insert into public.events (organizer_id, title, event_type, starts_at, venue_name, lat, lng, is_instant, is_listing)
    values ('1abc1b14-0628-4bbf-bf19-138bb5968d4b', 'x', 'tt', now(), 'x', 3, 101, true, true);
    insert into _out values ('member insert listing', 'ACCEPTED (bad)');
  exception when others then insert into _out values ('member insert listing', 'rejected: ' || sqlerrm);
  end;
  insert into public.events (organizer_id, title, event_type, starts_at, venue_name, lat, lng, is_instant)
  values ('1abc1b14-0628-4bbf-bf19-138bb5968d4b', 'Plain TT', 'tt', now(), 'x', 3, 101, true)
  returning id into v_id;
  insert into _out values ('member plain insert', 'ok');
  update public.events set title = 'Plain TT 2' where id = v_id;
  insert into _out values ('member plain update', 'ok');
  begin
    update public.events set organiser_name = 'Sepang' where id = v_id;
    insert into _out values ('member update organiser_name', 'ACCEPTED (bad)');
  exception when others then insert into _out values ('member update organiser_name', 'rejected: ' || sqlerrm);
  end;
  insert into _out values ('member reads view cols', (select count(*)::text from public.events_with_counts where is_listing));
end $$;
reset role;

insert into _out
select 'view opts', array_to_string(reloptions, ',') from pg_class where oid = 'public.events_with_counts'::regclass;
insert into _out
select 'view grants', string_agg(grantee || ':' || privilege_type, ' ' order by grantee, privilege_type)
  from information_schema.role_table_grants where table_schema = 'public' and table_name = 'events_with_counts' and grantee in ('anon', 'authenticated');
insert into _out
select 'profile_meets ok', (select count(*)::text from public.profile_meets('1abc1b14-0628-4bbf-bf19-138bb5968d4b'));

select * from _out;
