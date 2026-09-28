-- event_checkin_list declared username as text but profiles.username is citext.
create or replace function public.event_checkin_list(p_event uuid)
returns table (
  user_id        uuid,
  username       text,
  display_name   text,
  avatar_url     text,
  car            text,
  checked_in_at  timestamptz,
  source         text,
  stayed_min     int,
  stayed         boolean,
  confirmed      boolean,
  rejected       boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the host can see who is here'; end if;
  return query
    select c.user_id, p.username::text, p.display_name, p.avatar_url,
           (select nullif(trim(concat_ws(' ', k.make, k.model)), '')
              from public.cars k where k.owner_id = c.user_id
             order by k.is_default desc, k.created_at desc limit 1),
           c.checked_in_at, c.source,
           coalesce(public.stayed_min(p_event, c.user_id), 0),
           public.has_stayed(p_event, c.user_id),
           c.confirmed_at is not null,
           c.confirmed_at is null and c.confirmed_by is not null
      from public.checkins c
      join public.profiles p on p.id = c.user_id
      join public.events e on e.id = c.event_id
     where c.event_id = p_event and c.user_id <> e.organizer_id
     order by c.checked_in_at desc;
end;
$$;
