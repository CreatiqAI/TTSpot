-- =============================================================================
-- Expo mode, part one: the shared schema (docs/expo-mode-plan.md).
-- Tables and columns only, plus row-level security. The RPCs live in
-- 0119 (door & pass), 0120 (exhibitors), 0121 (stamps, freebies, leads),
-- 0122 (schedule & draw roll call) and 0123 (show-car vote & dashboard).
-- =============================================================================

-- ---------------------------------------------------------------- door ---

-- Check-in area per event (metres from the event pin). Null = the global
-- `checkin_radius_m` setting (300 m). Expos span whole halls.
alter table public.events add column if not exists checkin_radius_m int;
alter table public.events drop constraint if exists events_checkin_radius_m_check;
alter table public.events add constraint events_checkin_radius_m_check
  check (checkin_radius_m is null or checkin_radius_m between 50 and 100000);

-- Entry number (#0001 in check-in order) = the lucky draw number, and the
-- pass code booth staff scan for leads. share_contact: the member lets booths
-- that scan their pass see phone + email.
alter table public.checkins add column if not exists entry_no int;
alter table public.checkins add column if not exists pass_code text;
alter table public.checkins add column if not exists share_contact boolean not null default false;
create unique index if not exists checkins_entry_no_uidx on public.checkins (event_id, entry_no) where entry_no is not null;
create unique index if not exists checkins_pass_code_uidx on public.checkins (pass_code) where pass_code is not null;

create table if not exists public.event_entry_counters (
  event_id  uuid primary key references public.events (id) on delete cascade,
  last_no   int not null default 0
);
alter table public.event_entry_counters enable row level security;  -- no policies: triggers only

create or replace function public.checkins_assign_entry() returns trigger
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  if new.entry_no is null then
    insert into public.event_entry_counters as c (event_id, last_no) values (new.event_id, 1)
    on conflict (event_id) do update set last_no = c.last_no + 1
    returning last_no into v;
    new.entry_no := v;
  end if;
  if new.pass_code is null then
    new.pass_code := substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 16);
  end if;
  return new;
end;
$$;
drop trigger if exists checkins_assign_entry on public.checkins;
create trigger checkins_assign_entry before insert on public.checkins
  for each row execute function public.checkins_assign_entry();

-- Backfill existing check-ins in check-in order.
with numbered as (
  select event_id, user_id, row_number() over (partition by event_id order by checked_in_at, user_id) as n
  from public.checkins where entry_no is null
)
update public.checkins c set entry_no = n.n
from numbered n where c.event_id = n.event_id and c.user_id = n.user_id;
update public.checkins set pass_code = substr(md5(gen_random_uuid()::text || user_id::text), 1, 16) where pass_code is null;
insert into public.event_entry_counters (event_id, last_no)
select event_id, max(entry_no) from public.checkins group by event_id
on conflict (event_id) do update set last_no = greatest(public.event_entry_counters.last_no, excluded.last_no);

-- -------------------------------------------------------- registration ---

-- questions: [{"id":"q1","label":"You are a","type":"one|many|text","options":["Trade buyer","Car owner"],"required":true}]
create table if not exists public.event_forms (
  event_id      uuid primary key references public.events (id) on delete cascade,
  questions     jsonb not null default '[]'::jsonb
                check (jsonb_typeof(questions) = 'array' and jsonb_array_length(questions) <= 8),
  consent_text  text check (consent_text is null or char_length(consent_text) <= 500),
  ask_contact   boolean not null default true,   -- ask members to share phone + email with the organiser
  required      boolean not null default false,  -- the pass keeps asking until it's done
  updated_at    timestamptz not null default now()
);
alter table public.event_forms enable row level security;
drop policy if exists "event_forms: read" on public.event_forms;
create policy "event_forms: read" on public.event_forms for select to authenticated using (true);
drop policy if exists "event_forms: host write" on public.event_forms;
create policy "event_forms: host write" on public.event_forms for all to authenticated
  using (public.is_meet_host(event_id)) with check (public.is_meet_host(event_id));

create table if not exists public.event_registrations (
  event_id    uuid not null references public.events (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  answers     jsonb not null default '{}'::jsonb check (jsonb_typeof(answers) = 'object'),
  contact_ok  boolean not null default false,  -- phone + email go to the organiser
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (event_id, user_id)
);
alter table public.event_registrations enable row level security;
drop policy if exists "event_registrations: own" on public.event_registrations;
create policy "event_registrations: own" on public.event_registrations for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "event_registrations: host read" on public.event_registrations;
create policy "event_registrations: host read" on public.event_registrations for select to authenticated
  using (public.is_meet_host(event_id));

-- ---------------------------------------------------------- exhibitors ---

create table if not exists public.event_exhibitors (
  id                 uuid primary key default gen_random_uuid(),
  event_id           uuid not null references public.events (id) on delete cascade,
  name               text not null check (char_length(name) between 1 and 120),
  booths             text[] not null default '{}',          -- booth codes, e.g. {A019,A024}
  category           text check (category is null or char_length(category) <= 60),
  country            text check (country is null or char_length(country) <= 40),
  about              text check (about is null or char_length(about) <= 1000),
  phone              text check (phone is null or char_length(phone) <= 60),
  email              text check (email is null or char_length(email) <= 120),
  website            text check (website is null or char_length(website) <= 200),
  address            text check (address is null or char_length(address) <= 300),
  logo_url           text,
  partner_vendor_id  uuid references public.vendors (id) on delete set null,
  stamp_stop         boolean not null default false,
  freebie            text check (freebie is null or char_length(freebie) <= 80),
  freebie_limit      int check (freebie_limit is null or freebie_limit between 1 and 100000),
  sort               int not null default 0,
  created_at         timestamptz not null default now()
);
create index if not exists event_exhibitors_event_idx on public.event_exhibitors (event_id, sort, name);
create index if not exists event_exhibitors_partner_idx on public.event_exhibitors (partner_vendor_id) where partner_vendor_id is not null;
alter table public.event_exhibitors enable row level security;
drop policy if exists "event_exhibitors: read" on public.event_exhibitors;
create policy "event_exhibitors: read" on public.event_exhibitors for select to authenticated using (true);
drop policy if exists "event_exhibitors: host write" on public.event_exhibitors;
create policy "event_exhibitors: host write" on public.event_exhibitors for all to authenticated
  using (public.is_meet_host(event_id)) with check (public.is_meet_host(event_id));

-- The code printed on a booth's stamp QR (ttspot://booth/<exhibitor>/<code>).
-- Separate so members can't read it and stamp from home.
create table if not exists public.event_exhibitor_secrets (
  exhibitor_id  uuid primary key references public.event_exhibitors (id) on delete cascade,
  stamp_code    text not null default substr(md5(gen_random_uuid()::text), 1, 12)
);
alter table public.event_exhibitor_secrets enable row level security;  -- RPCs only

create or replace function public.event_exhibitor_secret_init() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.event_exhibitor_secrets (exhibitor_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists event_exhibitors_secret on public.event_exhibitors;
create trigger event_exhibitors_secret after insert on public.event_exhibitors
  for each row execute function public.event_exhibitor_secret_init();

-- Booth pins link to an exhibitor; w/h = the booth's size on the plan
-- (fractions of the image) so it can be highlighted as a box.
alter table public.event_floor_pins add column if not exists exhibitor_id uuid references public.event_exhibitors (id) on delete set null;
alter table public.event_floor_pins add column if not exists w real;
alter table public.event_floor_pins add column if not exists h real;
alter table public.event_floor_pins drop constraint if exists event_floor_pins_wh_check;
alter table public.event_floor_pins add constraint event_floor_pins_wh_check
  check ((w is null or (w > 0 and w <= 1)) and (h is null or (h > 0 and h <= 1)));
create index if not exists event_floor_pins_exhibitor_idx on public.event_floor_pins (exhibitor_id) where exhibitor_id is not null;

create table if not exists public.event_exhibitor_staff (
  exhibitor_id  uuid not null references public.event_exhibitors (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  added_by      uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  primary key (exhibitor_id, user_id)
);
create index if not exists event_exhibitor_staff_user_idx on public.event_exhibitor_staff (user_id);
alter table public.event_exhibitor_staff enable row level security;

-- Booth staff: added by the host, or the owner of the linked partner shop.
create or replace function public.is_exhibitor_staff(p_exhibitor uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select p_user is not null and (
    exists (select 1 from public.event_exhibitor_staff s where s.exhibitor_id = p_exhibitor and s.user_id = p_user)
    or exists (select 1 from public.event_exhibitors x join public.vendors v on v.id = x.partner_vendor_id
               where x.id = p_exhibitor and v.owner_id = p_user)
  );
$$;

drop policy if exists "event_exhibitor_staff: read" on public.event_exhibitor_staff;
create policy "event_exhibitor_staff: read" on public.event_exhibitor_staff for select to authenticated
  using (user_id = auth.uid() or public.is_meet_host((select x.event_id from public.event_exhibitors x where x.id = exhibitor_id)));
drop policy if exists "event_exhibitor_staff: host write" on public.event_exhibitor_staff;
create policy "event_exhibitor_staff: host write" on public.event_exhibitor_staff for all to authenticated
  using (public.is_meet_host((select x.event_id from public.event_exhibitors x where x.id = exhibitor_id)))
  with check (public.is_meet_host((select x.event_id from public.event_exhibitors x where x.id = exhibitor_id)));

-- --------------------------------------------------- stamps & freebies ---

create table if not exists public.event_booth_visits (
  exhibitor_id         uuid not null references public.event_exhibitors (id) on delete cascade,
  user_id              uuid not null references public.profiles (id) on delete cascade,
  event_id             uuid not null references public.events (id) on delete cascade,
  stamped_at           timestamptz not null default now(),
  freebie_redeemed_at  timestamptz,
  primary key (exhibitor_id, user_id)
);
create index if not exists event_booth_visits_event_user_idx on public.event_booth_visits (event_id, user_id);
alter table public.event_booth_visits enable row level security;
drop policy if exists "event_booth_visits: read" on public.event_booth_visits;
create policy "event_booth_visits: read" on public.event_booth_visits for select to authenticated
  using (user_id = auth.uid() or public.is_meet_host(event_id) or public.is_exhibitor_staff(exhibitor_id));

create table if not exists public.event_expo_settings (
  event_id      uuid primary key references public.events (id) on delete cascade,
  stamp_goal    int check (stamp_goal is null or stamp_goal between 1 and 50),
  stamp_reward  text check (stamp_reward is null or char_length(stamp_reward) <= 120),
  updated_at    timestamptz not null default now()
);
alter table public.event_expo_settings enable row level security;
drop policy if exists "event_expo_settings: read" on public.event_expo_settings;
create policy "event_expo_settings: read" on public.event_expo_settings for select to authenticated using (true);
drop policy if exists "event_expo_settings: host write" on public.event_expo_settings;
create policy "event_expo_settings: host write" on public.event_expo_settings for all to authenticated
  using (public.is_meet_host(event_id)) with check (public.is_meet_host(event_id));

-- Stamp rally done: reward collected at the counter (crew swipe it).
create table if not exists public.event_rally_claims (
  event_id      uuid not null references public.events (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  completed_at  timestamptz not null default now(),
  redeemed_at   timestamptz,
  primary key (event_id, user_id)
);
alter table public.event_rally_claims enable row level security;
drop policy if exists "event_rally_claims: read" on public.event_rally_claims;
create policy "event_rally_claims: read" on public.event_rally_claims for select to authenticated
  using (user_id = auth.uid() or public.is_meet_host(event_id));

-- --------------------------------------------------------------- leads ---

create table if not exists public.event_leads (
  id            uuid primary key default gen_random_uuid(),
  exhibitor_id  uuid not null references public.event_exhibitors (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  scanned_by    uuid references public.profiles (id) on delete set null,
  note          text check (note is null or char_length(note) <= 300),
  created_at    timestamptz not null default now(),
  unique (exhibitor_id, user_id)
);
create index if not exists event_leads_user_idx on public.event_leads (user_id);
alter table public.event_leads enable row level security;
drop policy if exists "event_leads: read" on public.event_leads;
create policy "event_leads: read" on public.event_leads for select to authenticated
  using (user_id = auth.uid() or public.is_exhibitor_staff(exhibitor_id));
-- The member can take their contact back.
drop policy if exists "event_leads: own delete" on public.event_leads;
create policy "event_leads: own delete" on public.event_leads for delete to authenticated
  using (user_id = auth.uid() or public.is_exhibitor_staff(exhibitor_id));
drop policy if exists "event_leads: staff note" on public.event_leads;
create policy "event_leads: staff note" on public.event_leads for update to authenticated
  using (public.is_exhibitor_staff(exhibitor_id)) with check (public.is_exhibitor_staff(exhibitor_id));

-- ------------------------------------------------------------ schedule ---

create table if not exists public.event_agenda (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events (id) on delete cascade,
  title        text not null check (char_length(title) between 1 and 80),
  about        text check (about is null or char_length(about) <= 500),
  starts_at    timestamptz not null,
  ends_at      timestamptz,
  pin_id       uuid references public.event_floor_pins (id) on delete set null,
  place_label  text check (place_label is null or char_length(place_label) <= 60),
  reminded_at  timestamptz,
  created_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists event_agenda_event_idx on public.event_agenda (event_id, starts_at);
create index if not exists event_agenda_due_idx on public.event_agenda (starts_at) where reminded_at is null;
alter table public.event_agenda enable row level security;
drop policy if exists "event_agenda: read" on public.event_agenda;
create policy "event_agenda: read" on public.event_agenda for select to authenticated using (true);
drop policy if exists "event_agenda: host write" on public.event_agenda;
create policy "event_agenda: host write" on public.event_agenda for all to authenticated
  using (public.is_meet_host(event_id)) with check (public.is_meet_host(event_id));

create table if not exists public.event_agenda_reminders (
  item_id     uuid not null references public.event_agenda (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (item_id, user_id)
);
alter table public.event_agenda_reminders enable row level security;
drop policy if exists "event_agenda_reminders: own" on public.event_agenda_reminders;
create policy "event_agenda_reminders: own" on public.event_agenda_reminders for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- -------------------------------------------------- draw roll call ---

-- presence_minutes: ask everyone eligible to confirm they're here this many
-- minutes before the draw; only confirmed members enter. Null = off.
alter table public.lucky_draws add column if not exists presence_minutes int;
alter table public.lucky_draws drop constraint if exists lucky_draws_presence_minutes_check;
alter table public.lucky_draws add constraint lucky_draws_presence_minutes_check
  check (presence_minutes is null or presence_minutes between 5 and 120);
alter table public.lucky_draws add column if not exists presence_asked_at timestamptz;

create table if not exists public.lucky_draw_presence (
  draw_id       uuid not null references public.lucky_draws (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  confirmed_at  timestamptz not null default now(),
  distance_m    int,
  primary key (draw_id, user_id)
);
alter table public.lucky_draw_presence enable row level security;
drop policy if exists "lucky_draw_presence: read" on public.lucky_draw_presence;
create policy "lucky_draw_presence: read" on public.lucky_draw_presence for select to authenticated
  using (user_id = auth.uid() or public.is_event_crew((select d.event_id from public.lucky_draws d where d.id = draw_id)));

-- ---------------------------------------------------- show-car vote ---

create table if not exists public.event_contests (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references public.events (id) on delete cascade,
  title           text not null check (char_length(title) between 2 and 80),
  about           text check (about is null or char_length(about) <= 500),
  opens_at        timestamptz,
  closes_at       timestamptz,
  members_enter   boolean not null default true,   -- members can enter their own car (host approves)
  status          text not null default 'open' check (status in ('open', 'closed', 'cancelled')),
  created_by      uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists event_contests_event_idx on public.event_contests (event_id, created_at);
alter table public.event_contests enable row level security;
drop policy if exists "event_contests: read" on public.event_contests;
create policy "event_contests: read" on public.event_contests for select to authenticated using (true);
drop policy if exists "event_contests: host write" on public.event_contests;
create policy "event_contests: host write" on public.event_contests for all to authenticated
  using (public.is_meet_host(event_id)) with check (public.is_meet_host(event_id));

create table if not exists public.event_contest_entries (
  id          uuid primary key default gen_random_uuid(),
  contest_id  uuid not null references public.event_contests (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  car_id      uuid references public.cars (id) on delete set null,
  number      int,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at  timestamptz not null default now(),
  unique (contest_id, user_id),
  unique (contest_id, number)
);
alter table public.event_contest_entries enable row level security;
drop policy if exists "event_contest_entries: read" on public.event_contest_entries;
create policy "event_contest_entries: read" on public.event_contest_entries for select to authenticated
  using (status = 'approved' or user_id = auth.uid()
         or public.is_meet_host((select c.event_id from public.event_contests c where c.id = contest_id)));

create table if not exists public.event_contest_votes (
  contest_id  uuid not null references public.event_contests (id) on delete cascade,
  voter_id    uuid not null references public.profiles (id) on delete cascade,
  entry_id    uuid not null references public.event_contest_entries (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (contest_id, voter_id)
);
create index if not exists event_contest_votes_entry_idx on public.event_contest_votes (entry_id);
alter table public.event_contest_votes enable row level security;
drop policy if exists "event_contest_votes: own read" on public.event_contest_votes;
create policy "event_contest_votes: own read" on public.event_contest_votes for select to authenticated
  using (voter_id = auth.uid());

-- ------------------------------------------------------------- points ---

insert into public.point_rules (reason, points, label, description, sort, active, limit_note)
values ('booth_stamp', 2, 'Booth stamp', 'Scan a booth''s stamp QR at an event.', 75, true, 'Once per booth')
on conflict (reason) do nothing;
