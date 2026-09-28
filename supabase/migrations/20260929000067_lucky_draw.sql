-- =============================================================================
-- Organizer tools, part two: the lucky draw.
--
-- Rules the owner set (reports/Event organizer features for TT Spot.md):
--   * only meets hosted by a verified organizer (is_organizer) can have one;
--     the host and co-hosts create, edit, run and cancel it;
--   * free entry only: one entry per member, never more for points, cards,
--     purchases or anything else. There is no way to buy or earn an entry;
--   * eligible = checked in at or before the cut-off with evidence: a QR
--     check-in the host did not mark "Not here", or a host-confirmed check-in.
--     The host, co-hosts and crew are left out;
--   * prizes are the organizer's own; TT Spot only provides the platform;
--   * whether winners must be present, and the claim window, are the
--     organizer's call. Unclaimed prizes pass to the next alternate.
--
-- Credibility (order of operations):
--   1. when the draw is scheduled, a secret 32-byte seed is made with
--      gen_random_bytes and only its sha256 (seed_hash) is published;
--   2. at the draw, the eligible list is frozen into lucky_draw_entrants and
--      its count + sha256 are stored (entrant_count, entrants_hash);
--   3. entrants are ranked by sha256(seed || user_id). The first N take the
--      prizes (in prize order), the next 3 are ranked alternates;
--   4. the seed is revealed (seed_reveal) so anyone can recompute the order,
--      and every step is written to lucky_draw_audit.
--
-- pg_cron ('ttspot-lucky-draws', every minute) sends the 30-min and 5-min
-- reminders to checked-in members, "starting now" at draw_at, runs the draw if
-- the host has not, and hands expired prizes to the next alternate. Winners
-- get a personal "You won" push, everyone else checked in a "results are out".
-- =============================================================================

-- =============================================================================
-- schema
-- =============================================================================
create table if not exists public.lucky_draws (
  id                   uuid primary key default gen_random_uuid(),
  event_id             uuid not null references public.events (id) on delete cascade,
  title                text not null check (char_length(title) between 2 and 80),
  draw_at              timestamptz not null,
  cutoff_at            timestamptz,                 -- filled from draw_at when left empty
  must_be_present      boolean not null default true,
  claim_minutes        int not null default 15 check (claim_minutes between 1 and 240),
  status               text not null default 'scheduled' check (status in ('scheduled', 'drawn', 'cancelled')),
  seed_hash            text,                        -- sha256 of the secret seed, published at scheduling
  seed_reveal          text,                        -- the seed (hex), published after the draw
  entrant_count        int,
  entrants_hash        text,                        -- sha256 of the frozen entrant ids, sorted, comma-joined
  drawn_at             timestamptz,
  drawn_by             uuid references public.profiles (id) on delete set null,   -- null = the scheduler
  created_by           uuid references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now(),
  reminded_30_at       timestamptz,
  reminded_5_at        timestamptz,
  start_notified_at    timestamptz
);
create index if not exists lucky_draws_event_idx on public.lucky_draws (event_id, draw_at);
create index if not exists lucky_draws_due_idx on public.lucky_draws (draw_at) where status = 'scheduled';

create or replace function public.lucky_draw_fill_cutoff() returns trigger
language plpgsql as $$
begin
  new.cutoff_at := least(coalesce(new.cutoff_at, new.draw_at), new.draw_at);
  return new;
end;
$$;
drop trigger if exists lucky_draws_fill_cutoff on public.lucky_draws;
create trigger lucky_draws_fill_cutoff before insert or update of draw_at, cutoff_at on public.lucky_draws
  for each row execute function public.lucky_draw_fill_cutoff();

create table if not exists public.lucky_draw_prizes (
  id        uuid primary key default gen_random_uuid(),
  draw_id   uuid not null references public.lucky_draws (id) on delete cascade,
  name      text not null check (char_length(name) between 1 and 80),
  quantity  int not null default 1 check (quantity between 1 and 50),
  sort      int not null default 0
);
create index if not exists lucky_draw_prizes_draw_idx on public.lucky_draw_prizes (draw_id, sort);

-- The frozen entrant list (written once, at the draw).
create table if not exists public.lucky_draw_entrants (
  draw_id  uuid not null references public.lucky_draws (id) on delete cascade,
  user_id  uuid not null references public.profiles (id) on delete cascade,
  primary key (draw_id, user_id)
);

create table if not exists public.lucky_draw_winners (
  id            uuid primary key default gen_random_uuid(),
  draw_id       uuid not null references public.lucky_draws (id) on delete cascade,
  prize_id      uuid references public.lucky_draw_prizes (id) on delete set null,  -- null = alternate on standby
  user_id       uuid not null references public.profiles (id) on delete cascade,
  rank          int not null,
  is_alternate  boolean not null default false,
  claim_code    text not null unique,
  claimed_at    timestamptz,
  claimed_by    uuid references public.profiles (id) on delete set null,
  expires_at    timestamptz,                         -- null = no claim window (winner need not be present)
  status        text not null default 'pending' check (status in ('pending', 'claimed', 'expired', 'forfeited')),
  promoted_at   timestamptz,                         -- an alternate who took over a prize
  created_at    timestamptz not null default now(),
  unique (draw_id, user_id),
  unique (draw_id, rank)
);
create index if not exists lucky_draw_winners_user_idx on public.lucky_draw_winners (user_id);
create index if not exists lucky_draw_winners_open_idx on public.lucky_draw_winners (expires_at) where status = 'pending';

-- The seed. No policies: only security-definer functions can read it.
create table if not exists public.lucky_draw_secrets (
  draw_id  uuid primary key references public.lucky_draws (id) on delete cascade,
  seed     bytea not null
);

create table if not exists public.lucky_draw_audit (
  id              bigint generated always as identity primary key,
  draw_id         uuid not null references public.lucky_draws (id) on delete cascade,
  action          text not null,   -- scheduled | edited | drawn | expired | promoted | no_alternate | forfeited | claimed | cancelled | auto_run_failed
  actor_id        uuid references public.profiles (id) on delete set null,
  entrant_count   int,
  entrants_hash   text,
  seed_hash       text,
  detail          jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists lucky_draw_audit_draw_idx on public.lucky_draw_audit (draw_id, created_at);

alter table public.lucky_draws enable row level security;
alter table public.lucky_draw_prizes enable row level security;
alter table public.lucky_draw_entrants enable row level security;
alter table public.lucky_draw_winners enable row level security;
alter table public.lucky_draw_secrets enable row level security;
alter table public.lucky_draw_audit enable row level security;

-- Draw details and prizes are public (they are the rules members see).
create policy "lucky draws: read" on public.lucky_draws for select to authenticated using (true);
create policy "lucky draw prizes: read" on public.lucky_draw_prizes for select to authenticated using (true);
create policy "lucky draw entrants: own or crew" on public.lucky_draw_entrants for select to authenticated
  using (user_id = auth.uid() or public.is_event_crew((select d.event_id from public.lucky_draws d where d.id = draw_id)));
create policy "lucky draw winners: own or crew" on public.lucky_draw_winners for select to authenticated
  using (user_id = auth.uid() or public.is_event_crew((select d.event_id from public.lucky_draws d where d.id = draw_id)));
create policy "lucky draw audit: host circle" on public.lucky_draw_audit for select to authenticated
  using (public.is_meet_host((select d.event_id from public.lucky_draws d where d.id = draw_id)));
-- writes only through the functions below

-- =============================================================================
-- helpers
-- =============================================================================

-- Who is in the draw right now: QR check-in (not marked "Not here") or a
-- host-confirmed check-in, at or before the cut-off. Host, co-hosts and crew
-- are out. One row per member (checkins has one row per member per meet).
create or replace function public.lucky_draw_eligible(p_draw uuid)
returns table (user_id uuid)
language sql stable security definer set search_path = public as $$
  select c.user_id
  from public.lucky_draws d
  join public.events e on e.id = d.event_id
  join public.checkins c on c.event_id = d.event_id
  where d.id = p_draw
    and c.checked_in_at <= coalesce(d.cutoff_at, d.draw_at)
    and (c.confirmed_at is not null or (c.source = 'qr' and c.confirmed_by is null))
    and c.user_id <> e.organizer_id
    and not exists (select 1 from public.event_crew k where k.event_id = d.event_id and k.user_id = c.user_id);
$$;

-- Who hears the reminders: everyone checked in to the meet (some are not
-- confirmed yet and still can be), minus host and crew.
create or replace function public.lucky_draw_audience(p_draw uuid)
returns table (user_id uuid)
language sql stable security definer set search_path = public as $$
  select c.user_id
  from public.lucky_draws d
  join public.events e on e.id = d.event_id
  join public.checkins c on c.event_id = d.event_id
  where d.id = p_draw
    and c.user_id <> e.organizer_id
    and not exists (select 1 from public.event_crew k where k.event_id = d.event_id and k.user_id = c.user_id);
$$;

-- "9:30 PM", Malaysian time, for push text.
create or replace function public.lucky_draw_time(p_at timestamptz) returns text
language sql stable as $$
  select to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MI AM');
$$;

create or replace function public.lucky_draw_claim_code() returns text
language sql volatile set search_path = public as $$
  select upper(encode(extensions.gen_random_bytes(6), 'hex'));
$$;

create or replace function public.lucky_draw_notify(p_users uuid[], p_event uuid, p_body text) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.notifications (user_id, type, event_id, body)
  select distinct u, 'lucky_draw'::public.notification_type, p_event, p_body from unnest(p_users) u where u is not null;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- The claim sentence for a winner, from the draw's settings.
create or replace function public.lucky_draw_claim_text(p_must_be_present boolean, p_minutes int) returns text
language sql immutable as $$
  select case when p_must_be_present
    then 'Show your claim QR at the stage within ' || p_minutes || ' min.'
    else 'Open the meet to see your claim QR.' end;
$$;

-- =============================================================================
-- organizer: create / edit / cancel
-- =============================================================================
create or replace function public.save_lucky_draw(
  p_event uuid,
  p_draw uuid,
  p_title text,
  p_draw_at timestamptz,
  p_cutoff_at timestamptz default null,
  p_must_be_present boolean default true,
  p_claim_minutes int default 15,
  p_prizes jsonb default '[]'::jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  e public.events;
  d public.lucky_draws;
  v_open timestamptz;
  v_close timestamptz;
  v_cutoff timestamptz := coalesce(p_cutoff_at, p_draw_at);
  v_id uuid;
  v_seed bytea;
  v_prize jsonb;
  v_total int := 0;
  v_i int := 0;
begin
  select * into e from public.events where id = p_event;
  if e.id is null then raise exception 'Meet not found'; end if;
  if e.status = 'cancelled' then raise exception 'This meet was cancelled'; end if;
  if not public.is_meet_host(p_event) then raise exception 'Only the host or a co-host can set up a lucky draw'; end if;
  if not public.is_organizer(e.organizer_id) then
    raise exception 'Lucky draws are for verified organizers. Apply in Me > Apply to be an organizer.';
  end if;
  if char_length(trim(coalesce(p_title, ''))) < 2 then raise exception 'Give the draw a name'; end if;
  if p_draw_at is null or p_draw_at <= now() then raise exception 'Pick a draw time in the future'; end if;
  if v_cutoff > p_draw_at then raise exception 'The cut-off must be at or before the draw'; end if;
  select opens_at, closes_at into v_open, v_close from public.event_period(p_event);
  if p_draw_at < v_open or p_draw_at > v_close then raise exception 'The draw has to happen during the meet'; end if;
  if coalesce(p_claim_minutes, 15) not between 1 and 240 then raise exception 'Claim window is 1 to 240 minutes'; end if;
  if jsonb_typeof(coalesce(p_prizes, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_prizes, '[]'::jsonb)) = 0 then
    raise exception 'Add at least one prize';
  end if;
  if jsonb_array_length(p_prizes) > 20 then raise exception 'Up to 20 prizes'; end if;
  for v_prize in select * from jsonb_array_elements(p_prizes) loop
    if char_length(trim(coalesce(v_prize ->> 'name', ''))) = 0 then raise exception 'Every prize needs a name'; end if;
    if coalesce((v_prize ->> 'quantity')::int, 1) not between 1 and 50 then raise exception 'Quantity is 1 to 50'; end if;
    v_total := v_total + coalesce((v_prize ->> 'quantity')::int, 1);
  end loop;
  if v_total > 100 then raise exception 'Up to 100 winners per draw'; end if;

  if p_draw is null then
    if (select count(*) from public.lucky_draws where event_id = p_event and status <> 'cancelled') >= 5 then
      raise exception 'A meet can have up to 5 draws';
    end if;
    v_seed := extensions.gen_random_bytes(32);
    insert into public.lucky_draws (event_id, title, draw_at, cutoff_at, must_be_present, claim_minutes, seed_hash, created_by)
    values (p_event, left(trim(p_title), 80), p_draw_at, v_cutoff, coalesce(p_must_be_present, true), coalesce(p_claim_minutes, 15),
            encode(extensions.digest(v_seed, 'sha256'), 'hex'), me)
    returning * into d;
    insert into public.lucky_draw_secrets (draw_id, seed) values (d.id, v_seed);
    insert into public.lucky_draw_audit (draw_id, action, actor_id, seed_hash, detail)
    values (d.id, 'scheduled', me, d.seed_hash, jsonb_build_object('draw_at', p_draw_at, 'cutoff_at', v_cutoff, 'prizes', p_prizes));
  else
    select * into d from public.lucky_draws where id = p_draw for update;
    if d.id is null or d.event_id <> p_event then raise exception 'Draw not found'; end if;
    if d.status <> 'scheduled' then raise exception 'This draw has already run or was cancelled'; end if;
    update public.lucky_draws
       set title = left(trim(p_title), 80), draw_at = p_draw_at, cutoff_at = v_cutoff,
           must_be_present = coalesce(p_must_be_present, true), claim_minutes = coalesce(p_claim_minutes, 15),
           reminded_30_at = case when draw_at <> p_draw_at then null else reminded_30_at end,
           reminded_5_at = case when draw_at <> p_draw_at then null else reminded_5_at end,
           start_notified_at = case when draw_at <> p_draw_at then null else start_notified_at end
     where id = p_draw
    returning * into d;
    delete from public.lucky_draw_prizes where draw_id = d.id;
    insert into public.lucky_draw_audit (draw_id, action, actor_id, seed_hash, detail)
    values (d.id, 'edited', me, d.seed_hash, jsonb_build_object('draw_at', p_draw_at, 'cutoff_at', v_cutoff, 'prizes', p_prizes));
  end if;

  for v_prize in select * from jsonb_array_elements(p_prizes) loop
    insert into public.lucky_draw_prizes (draw_id, name, quantity, sort)
    values (d.id, left(trim(v_prize ->> 'name'), 80), coalesce((v_prize ->> 'quantity')::int, 1), v_i);
    v_i := v_i + 1;
  end loop;
  return d.id;
end;
$$;

create or replace function public.cancel_draw(p_draw uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.lucky_draws;
begin
  select * into d from public.lucky_draws where id = p_draw for update;
  if d.id is null then raise exception 'Draw not found'; end if;
  if not public.is_meet_host(d.event_id) then raise exception 'Only the host or a co-host can cancel the draw'; end if;
  if d.status <> 'scheduled' then raise exception 'Only a draw that has not run can be cancelled'; end if;
  update public.lucky_draws set status = 'cancelled' where id = p_draw;
  insert into public.lucky_draw_audit (draw_id, action, actor_id) values (p_draw, 'cancelled', auth.uid());
end;
$$;

-- =============================================================================
-- the draw
-- =============================================================================

-- Internal. p_actor null = the scheduler.
create or replace function public.lucky_draw_execute(p_draw uuid, p_actor uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  d public.lucky_draws;
  v_seed bytea;
  v_n int;
  v_hash text;
  v_slots uuid[];
  v_nslots int;
  v_rank int := 0;
  w record;
  v_winners uuid[] := '{}';
begin
  select * into d from public.lucky_draws where id = p_draw for update;
  if d.id is null then raise exception 'Draw not found'; end if;
  if d.status <> 'scheduled' then raise exception 'This draw has already run or was cancelled'; end if;

  -- Run early: nobody who checks in after this moment can be in it.
  if d.cutoff_at > now() then
    update public.lucky_draws set cutoff_at = now() where id = p_draw returning * into d;
  end if;

  -- 1. freeze the entrant list
  insert into public.lucky_draw_entrants (draw_id, user_id)
  select p_draw, x.user_id from public.lucky_draw_eligible(p_draw) x
  on conflict do nothing;
  select count(*)::int,
         encode(extensions.digest(coalesce(string_agg(en.user_id::text, ',' order by en.user_id), ''), 'sha256'), 'hex')
    into v_n, v_hash
    from public.lucky_draw_entrants en where en.draw_id = p_draw;

  -- 2. the seed committed at scheduling
  select s.seed into v_seed from public.lucky_draw_secrets s where s.draw_id = p_draw;
  if v_seed is null then
    v_seed := extensions.gen_random_bytes(32);
    insert into public.lucky_draw_secrets (draw_id, seed) values (p_draw, v_seed);
    update public.lucky_draws set seed_hash = encode(extensions.digest(v_seed, 'sha256'), 'hex') where id = p_draw returning * into d;
  end if;

  -- 3. one slot per prize unit, in prize order
  select coalesce(array_agg(p.id order by p.sort, p.id, g.n), '{}')
    into v_slots
    from public.lucky_draw_prizes p cross join lateral generate_series(1, p.quantity) as g(n)
   where p.draw_id = p_draw;
  v_nslots := coalesce(array_length(v_slots, 1), 0);

  -- 4. rank by sha256(seed || user id); prizes first, then 3 alternates
  for w in
    select en.user_id
      from public.lucky_draw_entrants en
     where en.draw_id = p_draw
     order by extensions.digest(v_seed || convert_to(en.user_id::text, 'UTF8'), 'sha256')
     limit v_nslots + 3
  loop
    v_rank := v_rank + 1;
    insert into public.lucky_draw_winners (draw_id, prize_id, user_id, rank, is_alternate, claim_code, expires_at)
    values (p_draw,
            case when v_rank <= v_nslots then v_slots[v_rank] end,
            w.user_id, v_rank, v_rank > v_nslots,
            public.lucky_draw_claim_code(),
            case when v_rank <= v_nslots and d.must_be_present then now() + make_interval(mins => d.claim_minutes) end);
    if v_rank <= v_nslots then v_winners := v_winners || w.user_id; end if;
  end loop;

  update public.lucky_draws
     set status = 'drawn', drawn_at = now(), drawn_by = p_actor,
         entrant_count = v_n, entrants_hash = v_hash, seed_reveal = encode(v_seed, 'hex')
   where id = p_draw
  returning * into d;

  insert into public.lucky_draw_audit (draw_id, action, actor_id, entrant_count, entrants_hash, seed_hash, detail)
  values (p_draw, 'drawn', p_actor, v_n, v_hash, d.seed_hash,
          jsonb_build_object('seed', d.seed_reveal, 'slots', v_nslots, 'ranked', v_rank, 'cutoff_at', d.cutoff_at));

  -- 5. tell people: each winner personally, everyone else checked in once
  insert into public.notifications (user_id, type, event_id, body)
  select wn.user_id, 'lucky_draw'::public.notification_type, d.event_id,
         'You won ' || p.name || ' in ' || d.title || '! ' || public.lucky_draw_claim_text(d.must_be_present, d.claim_minutes)
    from public.lucky_draw_winners wn join public.lucky_draw_prizes p on p.id = wn.prize_id
   where wn.draw_id = p_draw;
  perform public.lucky_draw_notify(
    array(select a.user_id from public.lucky_draw_audience(p_draw) a where not (a.user_id = any (v_winners))),
    d.event_id,
    'Results are out for ' || d.title || '. Tap to see the winners.');

  return jsonb_build_object('entrants', v_n, 'winners', least(v_rank, v_nslots), 'alternates', greatest(v_rank - v_nslots, 0),
                            'entrants_hash', v_hash, 'seed_hash', d.seed_hash);
end;
$$;

-- Host / co-host: run it now (before or at the scheduled time).
create or replace function public.run_lucky_draw(p_draw uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_event uuid;
begin
  select event_id into v_event from public.lucky_draws where id = p_draw;
  if v_event is null then raise exception 'Draw not found'; end if;
  if not public.is_meet_host(v_event) then raise exception 'Only the host or a co-host can run the draw'; end if;
  if not public.event_has_organizer_tools(v_event) then raise exception 'Lucky draws are for verified organizers'; end if;
  return public.lucky_draw_execute(p_draw, auth.uid());
end;
$$;

-- Give a prize whose winner expired / forfeited to the best-ranked alternate.
create or replace function public.lucky_draw_promote(p_draw uuid, p_prize uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  d public.lucky_draws;
  v_alt public.lucky_draw_winners;
  v_prize text;
begin
  select * into d from public.lucky_draws where id = p_draw;
  select name into v_prize from public.lucky_draw_prizes where id = p_prize;
  select * into v_alt from public.lucky_draw_winners
   where draw_id = p_draw and prize_id is null and status = 'pending'
   order by rank limit 1 for update;
  if v_alt.id is null then
    insert into public.lucky_draw_audit (draw_id, action, detail) values (p_draw, 'no_alternate', jsonb_build_object('prize', v_prize));
    return null;
  end if;
  update public.lucky_draw_winners
     set prize_id = p_prize, promoted_at = now(),
         expires_at = case when d.must_be_present then now() + make_interval(mins => d.claim_minutes) end
   where id = v_alt.id;
  insert into public.lucky_draw_audit (draw_id, action, detail)
  values (p_draw, 'promoted', jsonb_build_object('winner', v_alt.id, 'rank', v_alt.rank, 'prize', v_prize));
  perform public.lucky_draw_notify(array[v_alt.user_id], d.event_id,
    'You''re up! ' || v_prize || ' in ' || d.title || ' passed to you. ' || public.lucky_draw_claim_text(d.must_be_present, d.claim_minutes));
  return v_alt.id;
end;
$$;

-- Close claim windows that ran out and move those prizes on. Returns how many.
create or replace function public.lucky_draw_expire() returns int
language plpgsql security definer set search_path = public as $$
declare
  w record;
  n int := 0;
begin
  for w in
    update public.lucky_draw_winners x set status = 'expired'
     where x.status = 'pending' and x.prize_id is not null and x.expires_at is not null and x.expires_at < now()
    returning x.id, x.draw_id, x.prize_id, x.user_id, x.rank
  loop
    n := n + 1;
    insert into public.lucky_draw_audit (draw_id, action, detail)
    values (w.draw_id, 'expired', jsonb_build_object('winner', w.id, 'rank', w.rank));
    perform public.lucky_draw_notify(array[w.user_id], (select event_id from public.lucky_draws where id = w.draw_id),
      'Your claim window closed, so the prize passed to the next in line.');
    perform public.lucky_draw_promote(w.draw_id, w.prize_id);
  end loop;
  return n;
end;
$$;

-- Host / co-host: the winner is not here (or said no). Next alternate gets it.
create or replace function public.forfeit_draw_winner(p_winner uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  w public.lucky_draw_winners;
  v_event uuid;
begin
  select * into w from public.lucky_draw_winners where id = p_winner for update;
  if w.id is null then raise exception 'Winner not found'; end if;
  select event_id into v_event from public.lucky_draws where id = w.draw_id;
  if not public.is_meet_host(v_event) then raise exception 'Only the host or a co-host can do this'; end if;
  if w.status <> 'pending' or w.prize_id is null then raise exception 'Only an unclaimed prize can be passed on'; end if;
  update public.lucky_draw_winners set status = 'forfeited' where id = p_winner;
  insert into public.lucky_draw_audit (draw_id, action, actor_id, detail)
  values (w.draw_id, 'forfeited', auth.uid(), jsonb_build_object('winner', w.id, 'rank', w.rank));
  perform public.lucky_draw_promote(w.draw_id, w.prize_id);
end;
$$;

-- Host / co-host / crew scan the winner's claim QR (ttspot://drawclaim/<code>).
-- Returns {ok, message, prize, display_name, username, avatar_url, rank}.
create or replace function public.claim_prize(p_claim_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  w public.lucky_draw_winners;
  d public.lucky_draws;
  pr public.profiles;
  v_prize text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into w from public.lucky_draw_winners where claim_code = upper(trim(coalesce(p_claim_code, ''))) for update;
  if w.id is null then raise exception 'That is not a valid prize claim code'; end if;
  select * into d from public.lucky_draws where id = w.draw_id;
  if not public.is_event_crew(d.event_id) then raise exception 'Only the host or crew of this meet can hand over prizes'; end if;
  select * into pr from public.profiles where id = w.user_id;
  select name into v_prize from public.lucky_draw_prizes where id = w.prize_id;

  if w.prize_id is null then
    return jsonb_build_object('ok', false, 'message', 'On standby (#' || w.rank || '). No prize for them yet.',
                              'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url, 'rank', w.rank);
  end if;
  if w.status = 'claimed' then
    return jsonb_build_object('ok', false, 'message', 'Already handed over.', 'prize', v_prize,
                              'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url, 'rank', w.rank);
  end if;
  if w.status in ('expired', 'forfeited') or (w.expires_at is not null and w.expires_at < now()) then
    if w.status = 'pending' then perform public.lucky_draw_expire(); end if;
    return jsonb_build_object('ok', false, 'message', 'The claim window closed. The prize passed to the next in line.', 'prize', v_prize,
                              'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url, 'rank', w.rank);
  end if;

  update public.lucky_draw_winners set status = 'claimed', claimed_at = now(), claimed_by = auth.uid() where id = w.id;
  insert into public.lucky_draw_audit (draw_id, action, actor_id, detail)
  values (w.draw_id, 'claimed', auth.uid(), jsonb_build_object('winner', w.id, 'rank', w.rank, 'prize', v_prize));
  perform public.lucky_draw_notify(array[w.user_id], d.event_id, 'Prize handed over: ' || v_prize || '. Enjoy!');
  return jsonb_build_object('ok', true, 'message', 'Hand over the prize.', 'prize', v_prize,
                            'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url, 'rank', w.rank);
end;
$$;

-- =============================================================================
-- reads
-- =============================================================================

-- A member's view of every draw at a meet: am I in, did I win, my claim code.
create or replace function public.my_draw_status(p_event uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(s.j order by s.at), '[]'::jsonb)
  from (
    select d.draw_at as at, jsonb_build_object(
      'id', d.id,
      'title', d.title,
      'draw_at', d.draw_at,
      'cutoff_at', d.cutoff_at,
      'must_be_present', d.must_be_present,
      'claim_minutes', d.claim_minutes,
      'status', d.status,
      'entrant_count', d.entrant_count,
      'prizes', coalesce((select jsonb_agg(jsonb_build_object('name', p.name, 'quantity', p.quantity) order by p.sort)
                          from public.lucky_draw_prizes p where p.draw_id = d.id), '[]'::jsonb),
      'checked_in', exists (select 1 from public.checkins c where c.event_id = d.event_id and c.user_id = auth.uid()),
      'eligible', case when d.status = 'drawn'
                       then exists (select 1 from public.lucky_draw_entrants en where en.draw_id = d.id and en.user_id = auth.uid())
                       else exists (select 1 from public.lucky_draw_eligible(d.id) x where x.user_id = auth.uid()) end,
      'excluded', case when e.organizer_id = auth.uid() then 'host'
                       when exists (select 1 from public.event_crew k where k.event_id = d.event_id and k.user_id = auth.uid()) then 'crew' end,
      'win', (select jsonb_build_object('id', w.id, 'prize', p.name, 'rank', w.rank, 'claim_code', w.claim_code,
                                        'expires_at', w.expires_at, 'status', w.status, 'is_alternate', w.is_alternate,
                                        'has_prize', w.prize_id is not null, 'claimed_at', w.claimed_at)
                from public.lucky_draw_winners w left join public.lucky_draw_prizes p on p.id = w.prize_id
               where w.draw_id = d.id and w.user_id = auth.uid())
    ) as j
    from public.lucky_draws d join public.events e on e.id = d.event_id
    where d.event_id = p_event and d.status <> 'cancelled' and auth.uid() is not null
  ) s;
$$;

-- Public winners list (once drawn), by display name.
create or replace function public.draw_results(p_draw uuid)
returns table (rank int, prize text, display_name text, username text, avatar_url text, status text, is_alternate boolean)
language sql stable security definer set search_path = public as $$
  select w.rank, p.name, coalesce(pr.display_name, pr.username::text), pr.username::text, pr.avatar_url, w.status, w.is_alternate
  from public.lucky_draw_winners w
  join public.lucky_draws d on d.id = w.draw_id and d.status = 'drawn'
  join public.lucky_draw_prizes p on p.id = w.prize_id
  join public.profiles pr on pr.id = w.user_id
  where w.draw_id = p_draw and auth.uid() is not null
  order by p.sort, w.rank;
$$;

-- Everything the stage screen needs (crew only): live entrant count before
-- the draw, a sample of names to roll, and after it every winner and
-- alternate with claim state.
create or replace function public.draw_stage(p_draw uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  d public.lucky_draws;
  v jsonb;
begin
  select * into d from public.lucky_draws where id = p_draw;
  if d.id is null then raise exception 'Draw not found'; end if;
  if not public.is_event_crew(d.event_id) then raise exception 'Only the host or crew can open the stage screen'; end if;
  select jsonb_build_object(
    'id', d.id, 'event_id', d.event_id, 'title', d.title, 'status', d.status,
    'draw_at', d.draw_at, 'cutoff_at', d.cutoff_at, 'must_be_present', d.must_be_present, 'claim_minutes', d.claim_minutes,
    'drawn_at', d.drawn_at, 'seed_hash', d.seed_hash, 'seed_reveal', d.seed_reveal, 'entrants_hash', d.entrants_hash,
    'entrant_count', case when d.status = 'drawn' then d.entrant_count
                          else (select count(*) from public.lucky_draw_eligible(d.id)) end,
    'checked_in', (select count(*) from public.lucky_draw_audience(d.id)),
    'names', coalesce((select jsonb_agg(n) from (
                 select coalesce(pr.display_name, pr.username::text) n
                   from public.profiles pr
                  where pr.id in (select en.user_id from public.lucky_draw_entrants en where en.draw_id = d.id
                                  union select x.user_id from public.lucky_draw_eligible(d.id) x where d.status <> 'drawn')
                  order by random() limit 120) t), '[]'::jsonb),
    'prizes', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'quantity', p.quantity) order by p.sort)
                          from public.lucky_draw_prizes p where p.draw_id = d.id), '[]'::jsonb),
    'winners', coalesce((select jsonb_agg(jsonb_build_object(
                     'id', w.id, 'rank', w.rank, 'prize', p.name, 'prize_id', w.prize_id, 'prize_sort', p.sort,
                     'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url,
                     'status', w.status, 'is_alternate', w.is_alternate, 'expires_at', w.expires_at, 'claimed_at', w.claimed_at,
                     'promoted_at', w.promoted_at) order by w.rank)
                   from public.lucky_draw_winners w
                   join public.profiles pr on pr.id = w.user_id
                   left join public.lucky_draw_prizes p on p.id = w.prize_id
                  where w.draw_id = d.id), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

-- =============================================================================
-- scheduler
-- =============================================================================
create or replace function public.due_lucky_draws() returns int
language plpgsql security definer set search_path = public as $$
declare
  d record;
  n int := 0;
begin
  -- T-30 min (skipped when the draw is already inside 6 min)
  for d in
    update public.lucky_draws set reminded_30_at = now()
     where status = 'scheduled' and reminded_30_at is null
       and draw_at > now() + interval '6 minutes' and draw_at <= now() + interval '30 minutes'
    returning id, event_id, title, draw_at
  loop
    n := n + public.lucky_draw_notify(array(select a.user_id from public.lucky_draw_audience(d.id) a), d.event_id,
      d.title || ' at ' || public.lucky_draw_time(d.draw_at) || '. Stay checked in to be in the draw. Free entry.');
  end loop;

  -- T-5 min
  for d in
    update public.lucky_draws set reminded_5_at = now()
     where status = 'scheduled' and reminded_5_at is null
       and draw_at > now() and draw_at <= now() + interval '5 minutes'
    returning id, event_id, title
  loop
    n := n + public.lucky_draw_notify(array(select a.user_id from public.lucky_draw_audience(d.id) a), d.event_id,
      d.title || ' in 5 minutes. Head to the stage.');
  end loop;

  -- At draw_at: "starting now", then draw (if the host has not already).
  -- Only draws due in the last 2 hours, so an outage does not fire old ones.
  for d in
    update public.lucky_draws set start_notified_at = now()
     where status = 'scheduled' and start_notified_at is null
       and draw_at <= now() and draw_at > now() - interval '2 hours'
    returning id, event_id, title
  loop
    n := n + public.lucky_draw_notify(array(select a.user_id from public.lucky_draw_audience(d.id) a), d.event_id,
      d.title || ' is starting now. Winners are being picked.');
    begin
      perform public.lucky_draw_execute(d.id, null);
    exception when others then
      insert into public.lucky_draw_audit (draw_id, action, detail) values (d.id, 'auto_run_failed', jsonb_build_object('error', sqlerrm));
    end;
  end loop;

  n := n + public.lucky_draw_expire();
  return n;
end;
$$;

do $outer$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron could not be created: %', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'ttspot-lucky-draws') then
      perform cron.unschedule('ttspot-lucky-draws');
    end if;
    perform cron.schedule('ttspot-lucky-draws', '* * * * *', 'select public.due_lucky_draws()');
  else
    raise notice 'pg_cron not available: schedule public.due_lucky_draws() every minute some other way';
  end if;
end;
$outer$;

-- =============================================================================
-- grants
-- =============================================================================
revoke execute on function public.lucky_draw_fill_cutoff() from public, anon, authenticated;
revoke execute on function public.lucky_draw_eligible(uuid) from public, anon, authenticated;
revoke execute on function public.lucky_draw_audience(uuid) from public, anon, authenticated;
revoke execute on function public.lucky_draw_claim_code() from public, anon, authenticated;
revoke execute on function public.lucky_draw_notify(uuid[], uuid, text) from public, anon, authenticated;
revoke execute on function public.lucky_draw_execute(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.lucky_draw_promote(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.lucky_draw_expire() from public, anon, authenticated;
revoke execute on function public.due_lucky_draws() from public, anon, authenticated;
revoke execute on function public.save_lucky_draw(uuid, uuid, text, timestamptz, timestamptz, boolean, int, jsonb) from public, anon;
revoke execute on function public.cancel_draw(uuid) from public, anon;
revoke execute on function public.run_lucky_draw(uuid) from public, anon;
revoke execute on function public.forfeit_draw_winner(uuid) from public, anon;
revoke execute on function public.claim_prize(text) from public, anon;
revoke execute on function public.my_draw_status(uuid) from public, anon;
revoke execute on function public.draw_results(uuid) from public, anon;
revoke execute on function public.draw_stage(uuid) from public, anon;

grant execute on function public.save_lucky_draw(uuid, uuid, text, timestamptz, timestamptz, boolean, int, jsonb) to authenticated;
grant execute on function public.cancel_draw(uuid) to authenticated;
grant execute on function public.run_lucky_draw(uuid) to authenticated;
grant execute on function public.forfeit_draw_winner(uuid) to authenticated;
grant execute on function public.claim_prize(text) to authenticated;
grant execute on function public.my_draw_status(uuid) to authenticated;
grant execute on function public.draw_results(uuid) to authenticated;
grant execute on function public.draw_stage(uuid) to authenticated;
