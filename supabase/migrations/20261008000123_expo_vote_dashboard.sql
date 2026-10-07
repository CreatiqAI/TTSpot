-- =============================================================================
-- Expo mode, track E: the show car vote (People's Choice) and the organizer's
-- live dashboard + CSV exports (docs/expo-mode-plan.md items 14 and 15).
-- Tables are in 0118. Everything here is an RPC.
-- =============================================================================

-- ------------------------------------------------------------- helpers ---

-- A contest has ended: closed by the host, or its closing time passed.
create or replace function public.contest_ended(p_status text, p_closes_at timestamptz)
returns boolean language sql stable set search_path = public as $$
  select p_status = 'closed' or (p_status = 'open' and p_closes_at is not null and p_closes_at <= now());
$$;

-- Malaysia clock time for messages ("7:30 PM").
create or replace function public.contest_time_label(p_at timestamptz)
returns text language sql stable set search_path = public as $$
  select trim(to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MI AM'));
$$;

-- The lowest number not taken yet in a contest (1, 2, 3…, filling gaps).
create or replace function public.contest_next_number(p_contest uuid)
returns int language sql stable security definer set search_path = public as $$
  select min(n)::int from generate_series(1, coalesce((select max(number) from public.event_contest_entries
                                                        where contest_id = p_contest), 0) + 1) n
  where not exists (select 1 from public.event_contest_entries e where e.contest_id = p_contest and e.number = n);
$$;

-- "Honda Civic", or "a car".
create or replace function public.contest_car_label(p_car uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select nullif(trim(coalesce(k.make, '') || ' ' || coalesce(k.model, '')), '') from public.cars k where k.id = p_car), 'a car');
$$;

-- ------------------------------------------------------------ contests ---

create or replace function public.create_contest(
  p_event uuid,
  p_title text,
  p_about text default null,
  p_opens_at timestamptz default null,
  p_closes_at timestamptz default null,
  p_members_enter boolean default true
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_title text := trim(coalesce(p_title, ''));
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the organizer can set up a vote'; end if;
  if char_length(v_title) < 2 then raise exception 'Give the vote a name'; end if;
  if char_length(v_title) > 80 then raise exception 'Keep the name under 80 characters'; end if;
  if p_opens_at is not null and p_closes_at is not null and p_closes_at <= p_opens_at then
    raise exception 'The vote has to close after it opens';
  end if;
  insert into public.event_contests (event_id, title, about, opens_at, closes_at, members_enter, created_by)
  values (p_event, v_title, nullif(left(trim(coalesce(p_about, '')), 500), ''), p_opens_at, p_closes_at,
          coalesce(p_members_enter, true), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.update_contest(
  p_contest uuid,
  p_title text,
  p_about text default null,
  p_opens_at timestamptz default null,
  p_closes_at timestamptz default null,
  p_members_enter boolean default true
) returns void
language plpgsql security definer set search_path = public as $$
declare
  c public.event_contests;
  v_title text := trim(coalesce(p_title, ''));
begin
  select * into c from public.event_contests where id = p_contest;
  if c.id is null then raise exception 'Vote not found'; end if;
  if not public.is_meet_host(c.event_id) then raise exception 'Only the organizer can change the vote'; end if;
  if c.status = 'cancelled' then raise exception 'This vote was cancelled'; end if;
  if char_length(v_title) < 2 then raise exception 'Give the vote a name'; end if;
  if char_length(v_title) > 80 then raise exception 'Keep the name under 80 characters'; end if;
  if p_opens_at is not null and p_closes_at is not null and p_closes_at <= p_opens_at then
    raise exception 'The vote has to close after it opens';
  end if;
  update public.event_contests
     set title = v_title,
         about = nullif(left(trim(coalesce(p_about, '')), 500), ''),
         opens_at = p_opens_at,
         closes_at = p_closes_at,
         members_enter = coalesce(p_members_enter, true)
   where id = p_contest;
end;
$$;

-- Close now: results go public. Approved entrants hear about it.
create or replace function public.close_contest(p_contest uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.event_contests;
begin
  select * into c from public.event_contests where id = p_contest for update;
  if c.id is null then raise exception 'Vote not found'; end if;
  if not public.is_meet_host(c.event_id) then raise exception 'Only the organizer can close the vote'; end if;
  if c.status = 'cancelled' then raise exception 'This vote was cancelled'; end if;
  if c.status = 'closed' then return; end if;
  update public.event_contests
     set status = 'closed',
         closes_at = case when closes_at is null or closes_at > now() then now() else closes_at end
   where id = p_contest;
  insert into public.notifications (user_id, type, event_id, body)
  select e.user_id, 'announcement'::public.notification_type, c.event_id, c.title || E'\nVoting is closed. See the results.'
  from public.event_contest_entries e where e.contest_id = p_contest and e.status = 'approved';
end;
$$;

create or replace function public.cancel_contest(p_contest uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.event_contests;
begin
  select * into c from public.event_contests where id = p_contest;
  if c.id is null then raise exception 'Vote not found'; end if;
  if not public.is_meet_host(c.event_id) then raise exception 'Only the organizer can cancel the vote'; end if;
  update public.event_contests set status = 'cancelled' where id = p_contest;
end;
$$;

-- -------------------------------------------------------------- entries ---

-- A member enters their own car. Pending until the host approves.
create or replace function public.enter_contest(p_contest uuid, p_car uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  c public.event_contests;
  k public.cars;
  v_prev public.event_contest_entries;
  v_id uuid;
  v_host uuid;
  v_handle text;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into c from public.event_contests where id = p_contest;
  if c.id is null then raise exception 'Vote not found'; end if;
  if c.status = 'cancelled' then raise exception 'This vote was cancelled'; end if;
  if public.contest_ended(c.status, c.closes_at) then raise exception 'This vote is closed'; end if;
  if not c.members_enter then raise exception 'The organizer picks the cars for this vote'; end if;
  if not exists (select 1 from public.checkins where event_id = c.event_id and user_id = me)
     and not exists (select 1 from public.event_attendees where event_id = c.event_id and user_id = me) then
    raise exception 'Tap Going or check in first to enter your car';
  end if;
  select * into k from public.cars where id = p_car and owner_id = me;
  if k.id is null then raise exception 'Pick one of your own cars'; end if;

  select * into v_prev from public.event_contest_entries where contest_id = p_contest and user_id = me;
  if v_prev.id is not null then
    if v_prev.status = 'rejected' then raise exception 'The organizer passed on your entry this time'; end if;
    if v_prev.status = 'approved' then raise exception 'Your car is already in as #%', v_prev.number; end if;
    -- Still pending: swap the car.
    update public.event_contest_entries set car_id = k.id where id = v_prev.id;
    return json_build_object('id', v_prev.id, 'status', 'pending');
  end if;

  insert into public.event_contest_entries (contest_id, user_id, car_id, status)
  values (p_contest, me, k.id, 'pending')
  returning id into v_id;

  select e.organizer_id into v_host from public.events e where e.id = c.event_id;
  if v_host is not null and v_host <> me then
    select coalesce('@' || p.username::text, p.display_name, 'A member') into v_handle from public.profiles p where p.id = me;
    insert into public.notifications (user_id, type, event_id, body)
    values (v_host, 'announcement', c.event_id,
            'New show car entry' || E'\n' || coalesce(v_handle, 'A member') || ' · ' || public.contest_car_label(k.id));
  end if;
  return json_build_object('id', v_id, 'status', 'pending');
end;
$$;

-- Approve: the next free number and a push. Reject: out (any votes on it go
-- back to their voters).
create or replace function public.review_contest_entry(p_entry uuid, p_approve boolean)
returns json language plpgsql security definer set search_path = public as $$
declare
  en public.event_contest_entries;
  c public.event_contests;
  v_no int;
begin
  select * into en from public.event_contest_entries where id = p_entry;
  if en.id is null then raise exception 'Entry not found'; end if;
  select * into c from public.event_contests where id = en.contest_id for update;  -- one number at a time
  if not public.is_meet_host(c.event_id) then raise exception 'Only the organizer can review entries'; end if;
  if c.status = 'cancelled' then raise exception 'This vote was cancelled'; end if;

  if coalesce(p_approve, false) then
    if en.status = 'approved' then return json_build_object('id', en.id, 'status', 'approved', 'number', en.number); end if;
    v_no := public.contest_next_number(c.id);
    update public.event_contest_entries set status = 'approved', number = v_no where id = en.id;
    insert into public.notifications (user_id, type, event_id, body)
    values (en.user_id, 'announcement', c.event_id, 'You''re in the show car vote' || E'\n' || 'Your number is ' || v_no || '.');
    return json_build_object('id', en.id, 'status', 'approved', 'number', v_no);
  end if;

  delete from public.event_contest_votes where entry_id = en.id;
  update public.event_contest_entries set status = 'rejected', number = null where id = en.id;
  return json_build_object('id', en.id, 'status', 'rejected', 'number', null);
end;
$$;

-- The host adds a car straight in (approved). No car given: the member's
-- default car (else their newest).
create or replace function public.host_add_contest_entry(p_contest uuid, p_username text, p_car uuid default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  c public.event_contests;
  v_handle text := lower(trim(both from replace(coalesce(p_username, ''), '@', '')));
  v_user uuid;
  v_car uuid;
  v_prev public.event_contest_entries;
  v_id uuid;
  v_no int;
begin
  select * into c from public.event_contests where id = p_contest for update;
  if c.id is null then raise exception 'Vote not found'; end if;
  if not public.is_meet_host(c.event_id) then raise exception 'Only the organizer can add cars'; end if;
  if c.status = 'cancelled' then raise exception 'This vote was cancelled'; end if;
  if public.contest_ended(c.status, c.closes_at) then raise exception 'This vote is closed'; end if;
  if v_handle = '' then raise exception 'Type their @handle'; end if;

  select p.id into v_user from public.profiles p where lower(p.username::text) = v_handle;
  if v_user is null then raise exception 'No one goes by @%', v_handle; end if;

  if p_car is not null then
    select k.id into v_car from public.cars k where k.id = p_car and k.owner_id = v_user;
    if v_car is null then raise exception 'That car is not in @%''s garage', v_handle; end if;
  else
    select k.id into v_car from public.cars k where k.owner_id = v_user
    order by k.is_default desc, k.created_at desc limit 1;
    if v_car is null then raise exception '@% has no car in their garage yet', v_handle; end if;
  end if;

  select * into v_prev from public.event_contest_entries where contest_id = p_contest and user_id = v_user;
  if v_prev.id is not null and v_prev.status = 'approved' then
    raise exception '@% is already in as #%', v_handle, v_prev.number;
  end if;

  v_no := public.contest_next_number(p_contest);
  if v_prev.id is not null then
    update public.event_contest_entries set status = 'approved', number = v_no, car_id = v_car where id = v_prev.id;
    v_id := v_prev.id;
  else
    insert into public.event_contest_entries (contest_id, user_id, car_id, number, status)
    values (p_contest, v_user, v_car, v_no, 'approved')
    returning id into v_id;
  end if;

  insert into public.notifications (user_id, type, event_id, body)
  values (v_user, 'announcement', c.event_id, 'You''re in the show car vote' || E'\n' || 'Your number is ' || v_no || '.');
  return json_build_object('id', v_id, 'status', 'approved', 'number', v_no);
end;
$$;

-- The member takes their own car out (its votes go back to the voters).
create or replace function public.withdraw_contest_entry(p_entry uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  en public.event_contest_entries;
  c public.event_contests;
begin
  select * into en from public.event_contest_entries where id = p_entry;
  if en.id is null then raise exception 'Entry not found'; end if;
  if en.user_id is distinct from auth.uid() then raise exception 'You can only take out your own car'; end if;
  select * into c from public.event_contests where id = en.contest_id;
  if public.contest_ended(c.status, c.closes_at) then raise exception 'This vote is closed'; end if;
  delete from public.event_contest_entries where id = en.id;
end;
$$;

-- ---------------------------------------------------------------- votes ---

create or replace function public.cast_contest_vote(p_entry uuid)
returns json language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  en public.event_contest_entries;
  c public.event_contests;
  v_prev int;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into en from public.event_contest_entries where id = p_entry;
  if en.id is null or en.status <> 'approved' then raise exception 'That car is not in the vote'; end if;
  select * into c from public.event_contests where id = en.contest_id;
  if c.status = 'cancelled' then raise exception 'This vote was cancelled'; end if;
  if public.contest_ended(c.status, c.closes_at) then raise exception 'Voting has closed'; end if;
  if c.opens_at is not null and c.opens_at > now() then
    raise exception 'Voting opens at %', public.contest_time_label(c.opens_at);
  end if;
  if not exists (select 1 from public.checkins where event_id = c.event_id and user_id = me) then
    raise exception 'Check in at the event first, then vote';
  end if;
  if en.user_id = me then raise exception 'You can''t vote for your own car'; end if;

  select x.number into v_prev from public.event_contest_votes v join public.event_contest_entries x on x.id = v.entry_id
  where v.contest_id = c.id and v.voter_id = me;
  if found then raise exception 'You already voted for #%. Votes are final.', v_prev; end if;

  begin
    insert into public.event_contest_votes (contest_id, voter_id, entry_id) values (c.id, me, en.id);
  exception when unique_violation then
    raise exception 'You already voted. Votes are final.';
  end;
  return json_build_object('entry_id', en.id, 'number', en.number, 'contest_id', c.id);
end;
$$;

-- -------------------------------------------------------------- reading ---

-- Where a vote QR (ttspot://vote/<entry>) leads.
create or replace function public.contest_entry_info(p_entry uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v json;
begin
  select json_build_object('entry_id', en.id, 'contest_id', c.id, 'event_id', c.event_id,
                           'number', en.number, 'status', en.status, 'contest_status', c.status,
                           'title', c.title, 'car', public.contest_car_label(en.car_id))
    into v
  from public.event_contest_entries en join public.event_contests c on c.id = en.contest_id
  where en.id = p_entry;
  if v is null then raise exception 'That vote code is not valid any more'; end if;
  return v;
end;
$$;

-- Everything the vote screen needs. Counts: the host always, everyone once
-- it has ended. Pending entries: the host only.
create or replace function public.contest_board(p_contest uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  c public.event_contests;
  v_host boolean;
  v_ended boolean;
  v_counts boolean;
  v_not_yet boolean;
  v_checked_in boolean;
  v_going boolean;
  v_my_vote uuid;
  v_my_entry json;
  v_can_vote boolean := false;
  v_reason text;
  v_entries json;
  v_total int;
begin
  select * into c from public.event_contests where id = p_contest;
  if c.id is null then raise exception 'Vote not found'; end if;
  v_host := public.is_meet_host(c.event_id);
  v_ended := public.contest_ended(c.status, c.closes_at);
  v_counts := v_host or v_ended;
  v_not_yet := c.opens_at is not null and c.opens_at > now();
  v_checked_in := me is not null and exists (select 1 from public.checkins where event_id = c.event_id and user_id = me);
  v_going := me is not null and exists (select 1 from public.event_attendees where event_id = c.event_id and user_id = me);

  select v.entry_id into v_my_vote from public.event_contest_votes v where v.contest_id = c.id and v.voter_id = me;

  select json_build_object('id', en.id, 'status', en.status, 'number', en.number, 'car_id', en.car_id,
                           'make', k.make, 'model', k.model, 'toy_url', k.toy_url,
                           'cover', coalesce(k.portrait_url, k.photo_urls[1]))
    into v_my_entry
  from public.event_contest_entries en left join public.cars k on k.id = en.car_id
  where en.contest_id = c.id and en.user_id = me;

  if me is null then v_reason := 'Sign in to vote';
  elsif c.status = 'cancelled' then v_reason := 'This vote was cancelled';
  elsif v_ended then v_reason := 'Voting has closed';
  elsif v_my_vote is not null then v_reason := 'You voted';
  elsif v_not_yet then v_reason := 'Voting opens at ' || public.contest_time_label(c.opens_at);
  elsif not v_checked_in then v_reason := 'Check in at the event to vote';
  else v_can_vote := true;
  end if;

  with counts as (
    select v.entry_id, count(*)::int n from public.event_contest_votes v where v.contest_id = c.id group by v.entry_id
  ), rows as (
    select en.id, en.number, en.status, en.user_id, en.car_id, en.created_at,
           p.username::text as username, p.display_name, p.avatar_url,
           k.make, k.model, k.year, k.toy_url, coalesce(k.portrait_url, k.photo_urls[1]) as cover,
           coalesce(ct.n, 0) as votes
    from public.event_contest_entries en
    join public.profiles p on p.id = en.user_id
    left join public.cars k on k.id = en.car_id
    left join counts ct on ct.entry_id = en.id
    where en.contest_id = c.id and (en.status = 'approved' or (v_host and en.status = 'pending'))
  )
  select json_agg(json_build_object(
           'id', r.id, 'number', r.number, 'status', r.status, 'user_id', r.user_id, 'car_id', r.car_id,
           'username', r.username, 'display_name', r.display_name, 'avatar_url', r.avatar_url,
           'make', r.make, 'model', r.model, 'year', r.year, 'toy_url', r.toy_url, 'cover', r.cover,
           'votes', case when v_counts then r.votes end,
           'mine', r.user_id = me, 'created_at', r.created_at)
         order by (r.status = 'approved') desc, r.number nulls last, r.created_at)
    into v_entries
  from rows r;

  if v_counts then
    select count(*)::int into v_total from public.event_contest_votes where contest_id = c.id;
  end if;

  return json_build_object(
    'contest', json_build_object('id', c.id, 'event_id', c.event_id, 'title', c.title, 'about', c.about,
                                 'opens_at', c.opens_at, 'closes_at', c.closes_at, 'members_enter', c.members_enter,
                                 'status', c.status, 'ended', v_ended, 'not_yet', v_not_yet, 'created_at', c.created_at),
    'entries', coalesce(v_entries, '[]'::json),
    'is_host', v_host,
    'counts_visible', v_counts,
    'total_votes', v_total,
    'me', json_build_object(
      'my_vote_entry_id', v_my_vote,
      'my_entry', v_my_entry,
      'can_vote', v_can_vote,
      'reason', v_reason,
      'checked_in', v_checked_in,
      'going', v_going,
      'can_enter', me is not null and c.members_enter and c.status = 'open' and not v_ended
                   and v_my_entry is null and (v_checked_in or v_going)
    )
  );
end;
$$;

-- ------------------------------------------------------------ dashboard ---

create or replace function public.expo_dashboard(p_event uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v json;
begin
  if not exists (select 1 from public.events where id = p_event) then raise exception 'Event not found'; end if;
  if not public.is_meet_host(p_event) then raise exception 'Only the organizer can see the dashboard'; end if;

  with ch as (
    select c.user_id, c.checked_in_at, public.outing_car(p_event, c.user_id) as car_id
    from public.checkins c where c.event_id = p_event
  ),
  bv as (select * from public.event_booth_visits where event_id = p_event),
  ex as (select * from public.event_exhibitors where event_id = p_event),
  ld as (select l.* from public.event_leads l join ex on ex.id = l.exhibitor_id),
  ct as (select * from public.event_contests where event_id = p_event and status <> 'cancelled')
  select json_build_object(
    'generated_at', now(),
    'totals', json_build_object(
      'checked_in', (select count(*) from ch),
      'going', (select count(*) from public.event_attendees where event_id = p_event),
      'registrations', (select count(*) from public.event_registrations where event_id = p_event),
      'contact_ok', (select count(*) from public.event_registrations where event_id = p_event and contact_ok),
      'stamps', (select count(*) from bv),
      'stampers', (select count(distinct user_id) from bv),
      'freebies', (select count(*) from bv where freebie_redeemed_at is not null),
      'rally_completed', (select count(*) from public.event_rally_claims where event_id = p_event),
      'rally_redeemed', (select count(*) from public.event_rally_claims where event_id = p_event and redeemed_at is not null),
      'leads', (select count(*) from ld),
      'votes', (select count(*) from public.event_contest_votes v join ct on ct.id = v.contest_id),
      'exhibitors', (select count(*) from ex)
    ),
    'arrivals', coalesce((
      select json_agg(json_build_object('hour', to_char(h, 'YYYY-MM-DD"T"HH24:00:00'), 'count', n) order by h)
      from (select date_trunc('hour', checked_in_at at time zone 'Asia/Kuala_Lumpur') h, count(*) n from ch group by 1) a
    ), '[]'::json),
    'makes', coalesce((
      select json_agg(json_build_object('label', make, 'count', n) order by n desc, make)
      from (select initcap(trim(k.make)) make, count(*) n
            from ch join public.cars k on k.id = ch.car_id
            where nullif(trim(k.make), '') is not null
            group by 1 order by 2 desc, 1 limit 8) m
    ), '[]'::json),
    'states', coalesce((
      select json_agg(json_build_object('label', st, 'count', n) order by n desc, st)
      from (select coalesce(nullif(trim(p.home_state), ''), 'Not set') st, count(*) n
            from ch join public.profiles p on p.id = ch.user_id
            group by 1 order by 2 desc, 1 limit 8) s
    ), '[]'::json),
    'booths', coalesce((
      select json_agg(b order by b.stamps desc, b.leads desc, b.name)
      from (select * from (
              select ex.id, ex.name, ex.booths, ex.stamp_stop,
                     (select count(*) from bv where bv.exhibitor_id = ex.id)::int as stamps,
                     (select count(*) from bv where bv.exhibitor_id = ex.id and bv.freebie_redeemed_at is not null)::int as freebies,
                     (select count(*) from ld where ld.exhibitor_id = ex.id)::int as leads
              from ex) b0
            where b0.stamps > 0 or b0.leads > 0 or b0.freebies > 0
            order by b0.stamps desc, b0.leads desc, b0.name
            limit 15) b
    ), '[]'::json),
    'draws', coalesce((
      select json_agg(json_build_object(
               'id', d.id, 'title', d.title, 'status', d.status, 'draw_at', d.draw_at,
               'presence_minutes', d.presence_minutes,
               'entrants', case when d.status = 'drawn' then d.entrant_count
                                when d.presence_minutes is null then (select count(*) from ch) end,
               'confirmed', (select count(*) from public.lucky_draw_presence pr where pr.draw_id = d.id))
             order by d.draw_at)
      from public.lucky_draws d where d.event_id = p_event and d.status <> 'cancelled'
    ), '[]'::json),
    'contests', coalesce((
      select json_agg(json_build_object(
               'id', ct.id, 'title', ct.title, 'status', ct.status,
               'ended', public.contest_ended(ct.status, ct.closes_at),
               'entries', (select count(*) from public.event_contest_entries e where e.contest_id = ct.id and e.status = 'approved'),
               'pending', (select count(*) from public.event_contest_entries e where e.contest_id = ct.id and e.status = 'pending'),
               'votes', (select count(*) from public.event_contest_votes v where v.contest_id = ct.id))
             order by ct.created_at desc)
      from ct
    ), '[]'::json)
  ) into v;
  return v;
end;
$$;

-- Check-ins as rows for a CSV (the app builds the file).
create or replace function public.expo_export_checkins(p_event uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v json;
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the organizer can export this'; end if;
  select coalesce(json_agg(json_build_object(
           'entry_no', c.entry_no,
           'name', p.display_name,
           'username', p.username::text,
           'state', p.home_state,
           'car', nullif(trim(coalesce(k.make, '') || ' ' || coalesce(k.model, '')), ''),
           'checked_in_at', c.checked_in_at,
           'source', c.source)
         order by c.entry_no nulls last, c.checked_in_at), '[]'::json)
    into v
  from public.checkins c
  join public.profiles p on p.id = c.user_id
  left join public.cars k on k.id = public.outing_car(p_event, c.user_id)
  where c.event_id = p_event;
  return v;
end;
$$;

create or replace function public.expo_export_booth_visits(p_event uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v json;
begin
  if not public.is_meet_host(p_event) then raise exception 'Only the organizer can export this'; end if;
  select coalesce(json_agg(json_build_object(
           'exhibitor', x.name,
           'booths', array_to_string(x.booths, ' '),
           'username', p.username::text,
           'stamped_at', b.stamped_at,
           'freebie_redeemed_at', b.freebie_redeemed_at)
         order by x.name, b.stamped_at), '[]'::json)
    into v
  from public.event_booth_visits b
  join public.event_exhibitors x on x.id = b.exhibitor_id
  join public.profiles p on p.id = b.user_id
  where b.event_id = p_event;
  return v;
end;
$$;

-- ---------------------------------------------------------------- grants ---

revoke execute on function public.contest_next_number(uuid) from public, anon;
grant execute on function public.create_contest(uuid, text, text, timestamptz, timestamptz, boolean) to authenticated;
grant execute on function public.update_contest(uuid, text, text, timestamptz, timestamptz, boolean) to authenticated;
grant execute on function public.close_contest(uuid) to authenticated;
grant execute on function public.cancel_contest(uuid) to authenticated;
grant execute on function public.enter_contest(uuid, uuid) to authenticated;
grant execute on function public.review_contest_entry(uuid, boolean) to authenticated;
grant execute on function public.host_add_contest_entry(uuid, text, uuid) to authenticated;
grant execute on function public.withdraw_contest_entry(uuid) to authenticated;
grant execute on function public.cast_contest_vote(uuid) to authenticated;
grant execute on function public.contest_entry_info(uuid) to authenticated;
grant execute on function public.contest_board(uuid) to authenticated;
grant execute on function public.expo_dashboard(uuid) to authenticated;
grant execute on function public.expo_export_checkins(uuid) to authenticated;
grant execute on function public.expo_export_booth_visits(uuid) to authenticated;
