-- 0.3.64: hosts can end a live event, cancel one before it starts, and old
-- app versions can be told to update.
--
-- 1. end_event_now(p_event): the host circle (public.is_meet_host: host,
--    co-hosts, club officers, admins) ends a live event now: ends_at = now().
--    Check-ins, the map and the lock screen Live Activity all read ends_at
--    (event_live_window, Event.closesAt), so the event is over everywhere.
-- 2. cancel_event(p_event): the same circle cancels an event before it ends.
--    The old app path was a direct update, which RLS only allows the
--    organizer; co-hosts need this. on_event_cancel still notifies everyone.
-- 3. min_app_version (platform_settings, text) + app_min_version(): the
--    oldest app version allowed to run. '0.0.0' blocks nobody. Readable
--    before sign-in (anon).

-- 1. End now --------------------------------------------------------------

create or replace function public.end_event_now(p_event uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.events;
  v_now timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  select * into e from public.events where id = p_event for update;
  if e.id is null then
    raise exception 'Event not found.';
  end if;
  if not public.is_meet_host(p_event) then
    raise exception 'Only the organizer can end this event.';
  end if;
  if e.status = 'cancelled' then
    raise exception 'This event was cancelled.';
  end if;
  if e.starts_at > v_now then
    raise exception 'It has not started yet. Cancel it instead.';
  end if;
  if coalesce(e.ends_at, e.starts_at + interval '6 hours') <= v_now then
    raise exception 'This event has already ended.';
  end if;
  update public.events set ends_at = v_now where id = p_event;
  return v_now;
end;
$$;

revoke execute on function public.end_event_now(uuid) from public, anon;
grant execute on function public.end_event_now(uuid) to authenticated;

-- 2. Cancel ---------------------------------------------------------------

create or replace function public.cancel_event(p_event uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.events;
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  select * into e from public.events where id = p_event for update;
  if e.id is null then
    raise exception 'Event not found.';
  end if;
  if not public.is_meet_host(p_event) then
    raise exception 'Only the organizer can cancel this event.';
  end if;
  if e.status = 'cancelled' then
    raise exception 'This event is already cancelled.';
  end if;
  if coalesce(e.ends_at, e.starts_at + interval '6 hours') <= now() then
    raise exception 'This event has already ended.';
  end if;
  -- events_after_update (on_event_cancel) notifies everyone who joined.
  update public.events set status = 'cancelled' where id = p_event;
end;
$$;

revoke execute on function public.cancel_event(uuid) from public, anon;
grant execute on function public.cancel_event(uuid) to authenticated;

-- 3. Minimum app version ---------------------------------------------------

insert into public.platform_settings (key, value, description)
values ('min_app_version', to_jsonb('0.0.0'::text),
        'Oldest app version (x.y.z) allowed to run. Older apps show "Time for an update". 0.0.0 = nobody blocked.')
on conflict (key) do nothing;

create or replace function public.app_min_version()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(trim((select value #>> '{}' from public.platform_settings where key = 'min_app_version')), ''), '0.0.0');
$$;

grant execute on function public.app_min_version() to anon, authenticated;
