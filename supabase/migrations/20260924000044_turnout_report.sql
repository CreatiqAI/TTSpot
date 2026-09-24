-- Post-event turnout report for hosts (organizer strategy phase 0): verified
-- check-ins, show rate, first-timers, cars by make/model, arrival curve, clubs.
-- Readable by the host, the officers of the hosting club, and admins.

create or replace function public.event_turnout_report(p_event uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  e public.events;
  v jsonb;
begin
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  if not (e.organizer_id = auth.uid() or public.is_admin()
          or (e.club_id is not null and exists (select 1 from public.club_members m
                where m.club_id = e.club_id and m.user_id = auth.uid() and m.role in ('owner', 'vp', 'secretary')))) then
    raise exception 'Only the host can see this report';
  end if;

  with c as (
    select ch.user_id, ch.checked_in_at, ch.source,
      exists (select 1 from public.event_attendees a where a.event_id = p_event and a.user_id = ch.user_id) as rsvped,
      not exists (select 1 from public.checkins o where o.user_id = ch.user_id and o.checked_in_at < ch.checked_in_at) as first_ever
    from public.checkins ch where ch.event_id = p_event
  ),
  car as (
    select c.user_id, k.make, k.model
    from c cross join lateral (
      select make, model from public.cars where owner_id = c.user_id order by created_at desc limit 1
    ) k
  )
  select jsonb_build_object(
    'title', e.title,
    'starts_at', e.starts_at,
    'rsvps', (select count(*) from public.event_attendees where event_id = p_event),
    'checked_in', (select count(*) from c),
    'rsvp_showed', (select count(*) from c where rsvped),
    'walk_ins', (select count(*) from c where not rsvped),
    'first_timers', (select count(*) from c where first_ever),
    'by_source', coalesce((select jsonb_object_agg(source, n) from (select source, count(*) n from c group by source) s), '{}'::jsonb),
    'by_make', coalesce((select jsonb_agg(jsonb_build_object('make', make, 'count', n) order by n desc, make)
                          from (select initcap(trim(make)) make, count(*) n from car group by 1) m), '[]'::jsonb),
    'top_models', coalesce((select jsonb_agg(jsonb_build_object('make', make, 'model', model, 'count', n) order by n desc)
                          from (select initcap(trim(make)) make, trim(model) model, count(*) n from car group by 1, 2 order by 3 desc limit 10) m), '[]'::jsonb),
    'no_car', (select count(*) from c where not exists (select 1 from car where car.user_id = c.user_id)),
    'arrivals', coalesce((select jsonb_agg(jsonb_build_object('at', b, 'count', n) order by b)
                          from (select date_bin('15 minutes', checked_in_at, e.starts_at) b, count(*) n from c group by 1) a), '[]'::jsonb),
    'clubs', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'count', n) order by n desc)
                          from (select cl.name, count(distinct c.user_id) n
                                from c join public.club_members m on m.user_id = c.user_id join public.clubs cl on cl.id = m.club_id
                                group by cl.name order by 2 desc limit 5) k), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

revoke execute on function public.event_turnout_report(uuid) from public, anon;
grant execute on function public.event_turnout_report(uuid) to authenticated;
