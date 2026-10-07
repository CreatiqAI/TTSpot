-- Dry run for 20261009000125_ai_consent.sql. Run AFTER the migration, inside
-- one transaction that is rolled back:
--   python q.py --tx supabase/migrations/20261009000125_ai_consent.sql supabase/dryrun/ai_consent_dryrun.sql
-- Proves: titi_nudge_candidates skips members without ai_consent.titi; a new
-- car of a member without ai_consent.toy books no toy (status stays null, no
-- job); allow_toy_cars records the OK and books it; update_my_settings
-- merges ai_consent key by key. The last statement selects every check.

create temp table _out (check_name text, ok boolean, detail text) on commit drop;

-- Who would get a nudge without the consent rule (the 0116 body).
create temp table _old on commit drop as
  select p.id
    from public.profiles p
   where p.suspended_at is null
     and p.username is not null
     and not public.setting_off(p.settings, 'titi_tips')
     and exists (select 1 from public.push_tokens t where t.user_id = p.id);

-- Nobody has consent yet: every one of them is skipped now.
update public.profiles set settings = settings - 'ai_consent' where id in (select id from _old);
insert into _out
select 'nudge: no consent, no candidates',
       not exists (select 1 from public.titi_nudge_candidates(s, 20000) c join _old o on o.id = c.user_id),
       (select count(*) from _old)::text || ' members would have qualified before'
  from (values (1), (2), (3)) v(s)
 limit 1;

-- One of them says OK: only that one comes back (if not throttled today).
create temp table _pick on commit drop as select id from _old order by id limit 1;
update public.profiles set settings = coalesce(settings, '{}'::jsonb) || '{"ai_consent": {"titi": "2026-10-08T00:00:00Z"}}'::jsonb
 where id = (select id from _pick);
insert into _out
select 'nudge: consented member is a candidate, others are not',
       (select count(*) from public.titi_nudge_candidates(1, 20000) c join _old o on o.id = c.user_id where c.user_id <> (select id from _pick)) = 0
       and exists (select 1 from public.titi_nudge_candidates(1, 20000) c where c.user_id = (select id from _pick))
         = not exists (select 1 from public.titi_nudges n where n.user_id = (select id from _pick) and n.slot = 1
                         and n.day = (now() at time zone 'Asia/Kuala_Lumpur')::date),
       'picked ' || (select id from _pick)::text;

-- A member with a car and a toy already: drop any toy OK, add a new car.
create temp table _u on commit drop as
  select owner_id as id from public.cars where toy_url is not null order by created_at limit 1;
update public.profiles set settings = settings - 'ai_consent' where id = (select id from _u);
create temp table _toys_before on commit drop as
  select id, toy_url, toy_status from public.cars where owner_id = (select id from _u);

insert into public.cars (owner_id, make, model, photo_urls)
values ((select id from _u), 'Perodua', 'Consent Test', array['https://example.com/consent-test.jpg']);
create temp table _car on commit drop as
  select id from public.cars where owner_id = (select id from _u) and model = 'Consent Test';

insert into _out
select 'toy: no consent, new car books nothing',
       c.toy_status is null and c.toy_task is null
       and not exists (select 1 from public.car_toy_jobs j where j.car_id = c.id),
       'toy_status=' || coalesce(c.toy_status, 'null')
  from public.cars c where c.id = (select id from _car);

insert into _out
select 'toy: no consent, request_car_toy path (toy_book quiet) returns null',
       public.toy_book((select id from _car), false, true) is null, null;

-- Manual toy_book without consent says why (and still books nothing).
do $$
begin
  perform public.toy_book((select id from _car), true, false);
  insert into _out values ('toy: manual without consent raises', false, 'no error');
exception when others then
  insert into _out values ('toy: manual without consent raises', sqlerrm like 'Tap Make my toy car%', sqlerrm);
end $$;

insert into _out
select 'toy: still no job after the tries',
       not exists (select 1 from public.car_toy_jobs j where j.car_id = (select id from _car)), null;

-- allow_toy_cars as that member: records the OK and books the new car's toy.
select set_config('request.jwt.claims', json_build_object('sub', (select id from _u), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', (select id from _u)::text, true);

create temp table _allow on commit drop as select public.allow_toy_cars() as n;

insert into _out
select 'allow_toy_cars: records ai_consent.toy for the caller',
       coalesce(p.settings -> 'ai_consent' ->> 'toy', '') <> '',
       p.settings -> 'ai_consent' ->> 'toy'
  from public.profiles p where p.id = (select id from _u);

insert into _out
select 'allow_toy_cars: books the car without a toy',
       (select n from _allow) = 1 and c.toy_status = 'pending'
       and exists (select 1 from public.car_toy_jobs j where j.car_id = c.id and j.status = 'pending'),
       'booked=' || (select n from _allow)::text || ' toy_status=' || coalesce(c.toy_status, 'null')
  from public.cars c where c.id = (select id from _car);

insert into _out
select 'allow_toy_cars: cars with a toy are left as they were',
       not exists (
         select 1 from _toys_before b join public.cars c on c.id = b.id
          where b.toy_url is not null and (c.toy_url is distinct from b.toy_url or c.toy_status is distinct from b.toy_status)),
       null;

-- update_my_settings merges ai_consent key by key.
select public.update_my_settings('{"ai_consent": {"titi": "2026-10-09T01:02:03Z"}, "tips": true}'::jsonb);
insert into _out
select 'update_my_settings: ai_consent merges (toy kept, titi added)',
       coalesce(p.settings -> 'ai_consent' ->> 'toy', '') <> '' and p.settings -> 'ai_consent' ->> 'titi' = '2026-10-09T01:02:03Z'
       and (p.settings ->> 'tips') = 'true',
       (p.settings -> 'ai_consent')::text
  from public.profiles p where p.id = (select id from _u);

select public.update_my_settings('{"ai_consent": {"titi": null}}'::jsonb);
insert into _out
select 'update_my_settings: a null removes that key only',
       not (p.settings -> 'ai_consent' ? 'titi') and (p.settings -> 'ai_consent' ? 'toy'),
       (p.settings -> 'ai_consent')::text
  from public.profiles p where p.id = (select id from _u);

-- Another member can't be given consent: allow_toy_cars only writes the caller.
insert into _out
select 'allow_toy_cars: other members untouched',
       not exists (select 1 from public.profiles p where p.id not in ((select id from _u), (select id from _pick)) and p.settings ? 'ai_consent'),
       null;

select * from _out;
