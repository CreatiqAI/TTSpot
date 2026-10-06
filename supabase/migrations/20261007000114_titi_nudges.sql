-- =============================================================================
-- 0114 titi_nudges: proactive TiTi (batch 0.3.58).
--
-- TiTi writes a member at most ONE short message a day (Malaysia time), never
-- 22:00-08:00, only when something useful fits (rain today, a meet today, road
-- tax / insurance due, an unopened box, Friday's points reset, or now and then
-- a fun line). The Edge Function `titi-nudge` (cron every 30 min) picks the
-- members, writes the line with the TiTi model, saves it as a TiTi chat
-- message (titi_messages, the member's latest chat) and adds a notification
-- (type titi_nudge) whose push says "TiTi" and opens /titi.
--
--   titi_nudges          one row per message sent: trigger, text, language,
--                        tokens, cost. unique (user_id, day) = the 1-a-day rule.
--   weather_locations    MET Malaysia forecast towns (Tn) and districts (Ds)
--                        with coordinates (OpenStreetMap Nominatim, 2026-10-07)
--                        to find a member's nearest forecast.
--   titi_nudge_context() everything the function needs about a batch of
--                        members, in one call (service role only).
--   titi_set_lang()      the titi function stores the language the member
--                        chats in (profiles.settings.titi_lang: en | zh | ms).
--
-- Switches:
--   platform_settings.titi_nudges_enabled      false until the lead turns it on
--   platform_settings.titi_nudges_daily_budget max nudges a day, all members
--   profiles.settings.titi_tips                the member's "TiTi tips" switch
--                                              (missing = on)
--
-- Vault (set once, out of band; never in a migration):
--   select vault.create_secret('<random>', 'titi_nudge_secret');
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/titi-nudge', 'titi_nudge_url');
-- The same random value is the function secret TITI_NUDGE_SECRET.
-- Safe to re-run.
-- =============================================================================

alter type public.notification_type add value if not exists 'titi_nudge';

-- ------------------------------------------------------------ the log ---

create table if not exists public.titi_nudges (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  day             date not null default (now() at time zone 'Asia/Kuala_Lumpur')::date,
  trigger         text not null check (trigger in ('weather', 'meet', 'doc', 'box', 'points', 'fun')),
  ref             text,
  text            text not null check (char_length(text) between 1 and 200),
  lang            text not null default 'en',
  model           text,
  input_tokens    int not null default 0,
  cached_tokens   int not null default 0,
  output_tokens   int not null default 0,
  cost_usd        numeric(10, 6) not null default 0,
  fallback        boolean not null default false,
  session_id      uuid references public.titi_sessions (id) on delete set null,
  message_id      uuid,
  notification_id uuid,
  sent_at         timestamptz not null default now(),
  unique (user_id, day)
);
create index if not exists titi_nudges_user_idx on public.titi_nudges (user_id, sent_at desc);
create index if not exists titi_nudges_day_idx on public.titi_nudges (day);

alter table public.titi_nudges enable row level security;
revoke all on public.titi_nudges from anon, authenticated;
grant all on public.titi_nudges to service_role;

-- ------------------------------------------------------------ switches ---

insert into public.platform_settings (key, value, description) values
  ('titi_nudges_enabled', 'false'::jsonb, 'Proactive TiTi messages (titi-nudge cron). Off = nothing is sent.'),
  ('titi_nudges_daily_budget', '300'::jsonb, 'Most proactive TiTi messages per Malaysian day, all members together.')
on conflict (key) do nothing;

-- ------------------------------------------------------------- weather ---

create table if not exists public.weather_locations (
  id    text primary key,          -- MET Malaysia location_id (Tn001, Ds058…)
  name  text not null,
  kind  text not null check (kind in ('town', 'district')),
  state text,
  lat   double precision not null,
  lng   double precision not null
);
alter table public.weather_locations enable row level security;
revoke all on public.weather_locations from anon, authenticated;
grant all on public.weather_locations to service_role;

-- ---------------------------------------------------------- language ---

create or replace function public.titi_set_lang(p_user uuid, p_lang text) returns void
language sql security definer set search_path = public as $$
  update public.profiles
     set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('titi_lang', p_lang)
   where id = p_user and p_lang in ('en', 'zh', 'ms')
     and coalesce(settings ->> 'titi_lang', '') is distinct from p_lang;
$$;
revoke execute on function public.titi_set_lang(uuid, text) from public, anon, authenticated;
grant execute on function public.titi_set_lang(uuid, text) to service_role;

-- ------------------------------------------------------- candidates ---

-- Members who may get a nudge now: TiTi tips on, a push token, not
-- suspended, no nudge yet today, fewer than 8 pushes in the last 24 hours.
-- Oldest last-nudge first so everyone gets a turn.
create or replace function public.titi_nudge_candidates(p_limit int default 40) returns setof uuid
language sql stable security definer set search_path = public as $$
  select p.id
    from public.profiles p
   where p.suspended_at is null
     and p.username is not null
     and not public.setting_off(p.settings, 'titi_tips')
     and exists (select 1 from public.push_tokens t where t.user_id = p.id)
     and not exists (select 1 from public.titi_nudges n
                      where n.user_id = p.id and n.day = (now() at time zone 'Asia/Kuala_Lumpur')::date)
     and (select count(*) from public.notifications x
           where x.user_id = p.id and not x.silent and x.created_at > now() - interval '24 hours') < 8
   order by (select max(n.sent_at) from public.titi_nudges n where n.user_id = p.id) asc nulls first, p.id
   limit greatest(1, least(p_limit, 200));
$$;
revoke execute on function public.titi_nudge_candidates(int) from public, anon, authenticated;
grant execute on function public.titi_nudge_candidates(int) to service_role;

-- Everything the function needs to pick a trigger and write the line, per
-- member, in one call. Times are Malaysia time where they are dates.
create or replace function public.titi_nudge_context(p_users uuid[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_midnight timestamptz := (v_today::timestamp at time zone 'Asia/Kuala_Lumpur');
  v_week text := public.points_week_key(now());
begin
  return coalesce((
    select jsonb_object_agg(p.id, jsonb_build_object(
      'name', coalesce(nullif(btrim(p.display_name), ''), p.username::text),
      'home_state', p.home_state,
      'titi_tips', not public.setting_off(p.settings, 'titi_tips'),
      'titi_lang', p.settings ->> 'titi_lang',
      'has_token', exists (select 1 from public.push_tokens t where t.user_id = p.id),
      'pushes_24h', (select count(*) from public.notifications x
                      where x.user_id = p.id and not x.silent and x.created_at > now() - interval '24 hours'),
      'nudged_today', exists (select 1 from public.titi_nudges n where n.user_id = p.id and n.day = v_today),
      'car', (select jsonb_build_object('make', c.make, 'model', c.model, 'color', c.color, 'year', c.year)
                from public.cars c where c.owner_id = p.id
               order by c.is_default desc nulls last, c.created_at limit 1),
      'location', (select jsonb_build_object('lat', l.lat, 'lng', l.lng)
                     from public.user_locations l
                    where l.user_id = p.id and l.updated_at > now() - interval '30 days'),
      'recent', (select coalesce(jsonb_agg(left(m.content, 160) order by m.created_at), '[]'::jsonb)
                   from (select content, created_at from public.titi_messages
                          where user_id = p.id and role = 'user' and btrim(content) <> ''
                          order by created_at desc limit 8) m),
      'meets_today', (select coalesce(jsonb_agg(jsonb_build_object(
                          'id', e.id, 'title', e.title, 'venue', e.venue_name, 'starts_at', e.starts_at,
                          'going', exists (select 1 from public.event_attendees a where a.event_id = e.id and a.user_id = p.id),
                          'reminded_today', exists (select 1 from public.notifications n
                                                     where n.user_id = p.id and n.event_id = e.id
                                                       and n.type::text in ('event_reminder', 'meet_start')
                                                       and n.created_at >= v_midnight))
                          order by e.starts_at), '[]'::jsonb)
                        from public.events e
                       where e.status = 'active'
                         and e.starts_at > now()
                         and (e.starts_at at time zone 'Asia/Kuala_Lumpur')::date = v_today
                         and (exists (select 1 from public.event_attendees a where a.event_id = e.id and a.user_id = p.id)
                           or exists (select 1 from public.event_bookmarks b where b.event_id = e.id and b.user_id = p.id))),
      'docs', (select coalesce(jsonb_agg(jsonb_build_object('car_id', c.id, 'model', c.model, 'kind', x.kind, 'due', x.due, 'days', x.due - v_today)
                        order by x.due), '[]'::jsonb)
                 from public.car_documents d
                 join public.cars c on c.id = d.car_id
                cross join lateral (values ('road_tax', d.road_tax_expiry), ('insurance', d.insurance_expiry)) as x(kind, due)
                where c.owner_id = p.id and x.due between v_today and v_today + 7),
      'doc_pinged_today', exists (select 1 from public.notifications n
                                   where n.user_id = p.id and n.type::text = 'car_doc' and n.created_at >= v_midnight),
      'boxes', (select coalesce(jsonb_agg(b.id order by b.created_at), '[]'::jsonb)
                  from public.card_boxes b where b.user_id = p.id and b.status = 'sealed'),
      'week_key', v_week,
      'post_done', exists (select 1 from public.point_ledger l where l.idem_key = 'weekly_post:' || p.id || ':' || v_week),
      'nudges', (select coalesce(jsonb_agg(jsonb_build_object('trigger', n.trigger, 'ref', n.ref, 'sent_at', n.sent_at, 'text', n.text)
                         order by n.sent_at desc), '[]'::jsonb)
                   from public.titi_nudges n where n.user_id = p.id and n.sent_at > now() - interval '30 days')
    ))
    from public.profiles p
    where p.id = any (p_users)
  ), '{}'::jsonb);
end;
$$;
revoke execute on function public.titi_nudge_context(uuid[]) from public, anon, authenticated;
grant execute on function public.titi_nudge_context(uuid[]) to service_role;

-- How many nudges went out today (the daily budget).
create or replace function public.titi_nudges_today() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.titi_nudges where day = (now() at time zone 'Asia/Kuala_Lumpur')::date;
$$;
revoke execute on function public.titi_nudges_today() from public, anon, authenticated;
grant execute on function public.titi_nudges_today() to service_role;

-- ---------------------------------------------------------------- cron ---

-- Posts {} to the function. Never raises. The function itself checks the
-- switch, the hours and the budget, so a run when it's off costs nothing.
create or replace function public.titi_nudge_post() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
  v_url text;
begin
  if coalesce((select value #>> '{}' from public.platform_settings where key = 'titi_nudges_enabled'), 'false') not in ('true', '1', 'on') then
    return;
  end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'titi_nudge_secret';
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'titi_nudge_url';
  if v_secret is null or v_url is null then
    raise warning 'titi_nudge_post: titi_nudge_secret / titi_nudge_url not set';
    return;
  end if;
  perform net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-titi-secret', v_secret),
    timeout_milliseconds := 120000
  );
exception when others then
  raise warning 'titi_nudge_post: %', sqlerrm;
end;
$$;
revoke execute on function public.titi_nudge_post() from public, anon, authenticated;

-- Every 30 minutes from 08:00 to 21:30 Malaysia time (00:00-13:30 UTC).
do $outer$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'ttspot-titi-nudges';
    perform cron.schedule('ttspot-titi-nudges', '0,30 0-13 * * *', 'select public.titi_nudge_post()');
  else
    raise notice 'pg_cron not available: run titi_nudge_post() every 30 minutes some other way';
  end if;
end;
$outer$;

-- MET Malaysia forecast towns and districts. Coordinates and states from
-- OpenStreetMap Nominatim (© OpenStreetMap contributors, ODbL), looked up once
-- on 2026-10-07; Bandar Baru Seri Manjung set by hand.
insert into public.weather_locations (id, name, kind, state, lat, lng) values
  ('Ds001', 'Langkawi', 'district', 'Kedah', 6.37, 99.7929),
  ('Ds002', 'Perlis', 'district', 'Perlis', 6.4308, 100.2701),
  ('Ds003', 'Kubang Pasu', 'district', 'Kedah', 6.3356, 100.3723),
  ('Ds004', 'Kota Setar', 'district', 'Kedah', 6.1592, 100.3621),
  ('Ds005', 'Pokok Sena', 'district', 'Pulau Pinang', 5.4843, 100.4574),
  ('Ds006', 'Padang Terap', 'district', 'Kedah', 6.2567, 100.6646),
  ('Ds007', 'Yan', 'district', 'Kedah', 5.8483, 100.4152),
  ('Ds008', 'Pendang', 'district', 'Kedah', 6.0291, 100.4801),
  ('Ds009', 'Kuala Muda', 'district', 'Kedah', 5.7073, 100.4953),
  ('Ds010', 'Sik', 'district', 'Kedah', 5.9239, 100.8231),
  ('Ds011', 'Barat Daya', 'district', 'Pulau Pinang', 5.3357, 100.2389),
  ('Ds012', 'Timur Laut', 'district', 'Pulau Pinang', 5.4103, 100.287),
  ('Ds013', 'Seberang Perai Utara', 'district', 'Pulau Pinang', 5.4993, 100.4468),
  ('Ds014', 'Seberang Perai Tengah', 'district', 'Pulau Pinang', 5.3611, 100.4574),
  ('Ds015', 'Baling', 'district', 'Kedah', 5.5507, 100.7976),
  ('Ds016', 'Kulim', 'district', 'Kedah', 5.3707, 100.6172),
  ('Ds017', 'Seberang Perai Selatan', 'district', 'Pulau Pinang', 5.217, 100.4805),
  ('Ds018', 'Bandar Baharu', 'district', 'Kedah', 5.1673, 100.5849),
  ('Ds019', 'Kerian', 'district', 'Perak', 5.0346, 100.4985),
  ('Ds020', 'Larut, Matang Dan Selama', 'district', 'Perak', 4.8514, 100.7435),
  ('Ds021', 'Hulu Perak', 'district', 'Perak', 5.448, 101.2971),
  ('Ds022', 'Tumpat', 'district', 'Kelantan', 6.119, 102.1977),
  ('Ds023', 'Pasir Mas', 'district', 'Kelantan', 6.0336, 102.1407),
  ('Ds024', 'Kota Bharu', 'district', 'Kelantan', 6.1066, 102.2594),
  ('Ds025', 'Jeli', 'district', 'Kelantan', 5.6983, 101.8419),
  ('Ds026', 'Kuala Kangsar', 'district', 'Perak', 4.8169, 101.0748),
  ('Ds027', 'Tanah Merah', 'district', 'Kedah', 6.2413, 100.4165),
  ('Ds028', 'Bachok', 'district', 'Kelantan', 6.1188, 102.3572),
  ('Ds029', 'Manjung', 'district', 'Perak', 4.3348, 100.6343),
  ('Ds030', 'Machang', 'district', 'Kelantan', 5.7629, 102.215),
  ('Ds031', 'Pasir Puteh', 'district', 'Kelantan', 5.764, 102.4313),
  ('Ds032', 'Kinta', 'district', 'Perak', 4.5949, 101.0751),
  ('Ds033', 'Perak Tengah', 'district', 'Perak', 4.3484, 100.8828),
  ('Ds034', 'Kuala Krai', 'district', 'Kelantan', 5.5414, 102.2033),
  ('Ds035', 'Kampar', 'district', 'Perak', 4.3068, 101.1436),
  ('Ds036', 'Bagan Datuk', 'district', 'Perak', 3.9287, 100.7769),
  ('Ds037', 'Besut', 'district', 'Terengganu', 5.7943, 102.5644),
  ('Ds038', 'Tanah Tinggi Cameron', 'district', 'Pahang', 4.4686, 101.3808),
  ('Ds039', 'Gua Musang', 'district', 'Kelantan', 4.8612, 101.9565),
  ('Ds040', 'Hilir Perak', 'district', 'Perak', 4.0072, 101.0205),
  ('Ds041', 'Batang Padang', 'district', 'Perak', 4.1954, 101.2598),
  ('Ds042', 'Setiu', 'district', 'Terengganu', 5.5318, 102.7364),
  ('Ds043', 'Sabak Bernam', 'district', 'Selangor', 3.6871, 101.0581),
  ('Ds044', 'Lipis', 'district', 'Pahang', 4.1677, 102.0358),
  ('Ds045', 'Muallim', 'district', 'Perak', 3.7215, 101.4776),
  ('Ds046', 'Kuala Nerus', 'district', 'Terengganu', 5.3428, 103.0905),
  ('Ds047', 'Hulu Terengganu', 'district', 'Terengganu', 5.0734, 103.0091),
  ('Ds048', 'Kuala Terengganu', 'district', 'Terengganu', 5.3288, 103.1425),
  ('Ds049', 'Kuala Selangor', 'district', 'Selangor', 3.3621, 101.3456),
  ('Ds050', 'Raub', 'district', 'Pahang', 3.7147, 101.7347),
  ('Ds051', 'Hulu Selangor', 'district', 'Selangor', 3.5367, 101.5949),
  ('Ds052', 'Marang', 'district', 'Terengganu', 5.2087, 103.2042),
  ('Ds053', 'Jerantut', 'district', 'Pahang', 3.9208, 102.385),
  ('Ds054', 'Klang', 'district', 'Selangor', 3.0833, 101.4167),
  ('Ds055', 'Gombak', 'district', 'Selangor', 3.2494, 101.6745),
  ('Ds056', 'Dungun', 'district', 'Terengganu', 4.7741, 103.4233),
  ('Ds057', 'Petaling', 'district', 'Selangor', 3.0833, 101.5833),
  ('Ds058', 'Kuala Lumpur', 'district', 'Kuala Lumpur', 3.1183, 101.6686),
  ('Ds059', 'Bentong', 'district', 'Pahang', 3.528, 101.9077),
  ('Ds060', 'Kuala Langat', 'district', 'Selangor', 2.8366, 101.4962),
  ('Ds061', 'Temerloh', 'district', 'Pahang', 3.6124, 102.2567),
  ('Ds062', 'Putrajaya', 'district', 'Putrajaya', 2.9461, 101.7245),
  ('Ds063', 'Hulu Langat', 'district', 'Selangor', 2.9553, 101.7579),
  ('Ds064', 'Sepang', 'district', 'Selangor', 2.8078, 101.741),
  ('Ds065', 'Kemaman', 'district', 'Terengganu', 4.2346, 103.4236),
  ('Ds066', 'Maran', 'district', 'Pahang', 3.5832, 102.7795),
  ('Ds067', 'Jelebu', 'district', 'Negeri Sembilan', 3.0366, 102.1179),
  ('Ds068', 'Seremban', 'district', 'Negeri Sembilan', 2.7443, 101.9264),
  ('Ds069', 'Kuantan', 'district', 'Pahang', 3.8561, 103.0395),
  ('Ds070', 'Port Dickson', 'district', 'Negeri Sembilan', 2.5152, 101.8996),
  ('Ds071', 'Bera', 'district', 'Pahang', 3.2679, 102.453),
  ('Ds072', 'Kuala Pilah', 'district', 'Negeri Sembilan', 2.7431, 102.2155),
  ('Ds073', 'Rembau', 'district', 'Negeri Sembilan', 2.6198, 102.0582),
  ('Ds074', 'Jempol', 'district', 'Negeri Sembilan', 2.8503, 102.5082),
  ('Ds075', 'Alor Gajah', 'district', 'Melaka', 2.3835, 102.2108),
  ('Ds076', 'Pekan', 'district', 'Pahang', 3.4908, 103.3991),
  ('Ds077', 'Tampin', 'district', 'Melaka', 2.4635, 102.2262),
  ('Ds078', 'Melaka Tengah', 'district', 'Melaka', 2.2301, 102.2453),
  ('Ds079', 'Jasin', 'district', 'Melaka', 2.3058, 102.4223),
  ('Ds080', 'Rompin', 'district', 'Pahang', 2.7991, 103.4722),
  ('Ds081', 'Tangkak', 'district', 'Johor', 2.2686, 102.5377),
  ('Ds082', 'Segamat', 'district', 'Johor', 2.4922, 102.8449),
  ('Ds083', 'Muar', 'district', 'Johor', 2.0439, 102.5636),
  ('Ds084', 'Batu Pahat', 'district', 'Johor', 2.0133, 103.0571),
  ('Ds085', 'Kluang', 'district', 'Johor', 2.0323, 103.3191),
  ('Ds086', 'Mersing', 'district', 'Johor', 2.3167, 103.7167),
  ('Ds087', 'Pontian', 'district', 'Johor', 1.4928, 103.3864),
  ('Ds088', 'Kulai', 'district', 'Johor', 1.6667, 103.6),
  ('Ds089', 'Kota Tinggi', 'district', 'Johor', 1.8167, 103.9667),
  ('Ds090', 'Johor Bahru', 'district', 'Johor', 1.5397, 103.6616),
  ('Ds092', 'Selama', 'district', 'Perak', 5.2181, 100.6917),
  ('Ds501', 'Tebedu', 'district', 'Sarawak', 1.0166, 110.3549),
  ('Ds502', 'Bau', 'district', 'Sarawak', 1.4218, 110.1542),
  ('Ds503', 'Lundu', 'district', 'Sarawak', 1.748, 109.7772),
  ('Ds504', 'Kuching', 'district', 'Sarawak', 1.5868, 110.3715),
  ('Ds505', 'Serian', 'district', 'Sarawak', 1.1727, 110.5674),
  ('Ds506', 'Samarahan', 'district', 'Sarawak', 1.4605, 110.491),
  ('Ds507', 'Asajaya', 'district', 'Sarawak', 1.5422, 110.6127),
  ('Ds508', 'Simunjan', 'district', 'Sarawak', 1.3632, 110.7923),
  ('Ds509', 'Sri Aman', 'district', 'Sarawak', 1.2309, 111.4554),
  ('Ds510', 'Pusa', 'district', 'Sarawak', 1.6179, 111.2937),
  ('Ds511', 'Betong', 'district', 'Sarawak', 1.5659, 111.4305),
  ('Ds512', 'Saratok', 'district', 'Sarawak', 1.7413, 111.3388),
  ('Ds513', 'Kabong', 'district', 'Perak', 4.4874, 100.7836),
  ('Ds514', 'Lubok Antu', 'district', 'Sarawak', 1.0401, 111.8329),
  ('Ds515', 'Pakan', 'district', 'Sarawak', 1.783, 111.6626),
  ('Ds516', 'Sarikei', 'district', 'Sarawak', 2.1369, 111.5042),
  ('Ds517', 'Tanjung Manis', 'district', 'Sarawak', 2.2287, 111.2139),
  ('Ds518', 'Julau', 'district', 'Sarawak', 2.1686, 111.6347),
  ('Ds519', 'Meradong', 'district', 'Sarawak', 2.1673, 111.6322),
  ('Ds520', 'Daro', 'district', 'Sarawak', 2.516, 111.4262),
  ('Ds521', 'Sibu', 'district', 'Sarawak', 2.3139, 111.8341),
  ('Ds522', 'Kanowit', 'district', 'Sarawak', 2.1031, 112.152),
  ('Ds523', 'Song', 'district', 'Sarawak', 2.0058, 112.5524),
  ('Ds524', 'Matu', 'district', 'Sarawak', 2.7413, 111.5112),
  ('Ds525', 'Dalat', 'district', 'Terengganu', 4.3912, 103.0732),
  ('Ds526', 'Selangau', 'district', 'Sarawak', 2.5233, 112.3256),
  ('Ds527', 'Mukah', 'district', 'Sarawak', 2.9002, 112.092),
  ('Ds528', 'Kapit', 'district', 'Sarawak', 2.0154, 112.9404),
  ('Ds529', 'Bukit Mabong', 'district', 'Sarawak', 1.7647, 113.841),
  ('Ds530', 'Tatau', 'district', 'Sarawak', 2.8779, 112.8568),
  ('Ds531', 'Bintulu', 'district', 'Sarawak', 3.1767, 113.0413),
  ('Ds532', 'Sebauh', 'district', 'Sarawak', 2.8779, 112.8568),
  ('Ds533', 'Belaga', 'district', 'Sarawak', 2.706, 113.7829),
  ('Ds534', 'Subis', 'district', 'Sarawak', 4.0556, 113.8442),
  ('Ds535', 'Beluru', 'district', 'Kelantan', 6.1777, 102.2328),
  ('Ds536', 'Telang Usan', 'district', 'Sarawak', 3.3172, 114.8258),
  ('Ds537', 'Miri', 'district', 'Sarawak', 4.3677, 114.0081),
  ('Ds538', 'Marudi', 'district', 'Sarawak', 4.1776, 114.3243),
  ('Ds539', 'Limbang', 'district', 'Sarawak', 4.7585, 115.0077),
  ('Ds540', 'Lawas', 'district', 'Sarawak', 4.8539, 115.4005),
  ('Ds541', 'Sipitang', 'district', 'Sabah', 5.0804, 115.55),
  ('Ds543', 'Tenom', 'district', 'Sabah', 5.1279, 115.9401),
  ('Ds544', 'Kuala Penyu', 'district', 'Sabah', 5.5721, 115.6009),
  ('Ds545', 'Beaufort', 'district', 'Sabah', 5.3559, 115.7339),
  ('Ds546', 'Nabawan', 'district', 'Sabah', 5.0442, 116.4326),
  ('Ds547', 'Keningau', 'district', 'Sabah', 5.3628, 116.1747),
  ('Ds548', 'Papar', 'district', 'Sabah', 5.7461, 116.045),
  ('Ds549', 'Putatan', 'district', 'Sabah', 5.8959, 116.0457),
  ('Ds550', 'Penampang', 'district', 'Sabah', 5.8626, 116.1138),
  ('Ds551', 'Tambunan', 'district', 'Sabah', 5.6677, 116.3624),
  ('Ds552', 'Tawau', 'district', 'Sabah', 4.2473, 117.8809),
  ('Ds553', 'Tongod', 'district', 'Sabah', 5.0658, 116.9941),
  ('Ds554', 'Kota Kinabalu', 'district', 'Sabah', 5.95, 116.144),
  ('Ds555', 'Tuaran', 'district', 'Sabah', 6.1729, 116.2309),
  ('Ds556', 'Ranau', 'district', 'Sabah', 5.9523, 116.6616),
  ('Ds557', 'Kunak', 'district', 'Sabah', 4.6839, 118.25),
  ('Ds558', 'Kota Belud', 'district', 'Sabah', 6.3568, 116.4296),
  ('Ds559', 'Semporna', 'district', 'Sabah', 4.4758, 118.6081),
  ('Ds560', 'Telupid', 'district', 'Sabah', 5.7903, 117.1698),
  ('Ds561', 'Kota Marudu', 'district', 'Sabah', 6.4956, 116.772),
  ('Ds562', 'Lahad Datu', 'district', 'Sabah', 5.0276, 118.3268),
  ('Ds563', 'Kinabatangan', 'district', 'Sabah', 5.7162, 118.3472),
  ('Ds564', 'Beluran', 'district', 'Sabah', 5.8959, 117.5574),
  ('Ds565', 'Sandakan', 'district', 'Sabah', 5.889, 117.9941),
  ('Ds566', 'Pitas', 'district', 'Sabah', 6.4968, 116.7694),
  ('Ds567', 'Kudat', 'district', 'Sabah', 5.9331, 116.0712),
  ('Ds568', 'Membakut', 'district', 'Sabah', 5.504, 115.8052),
  ('Ds570', 'Labuk & Sugut', 'district', 'Sabah', 5.8959, 117.5574),
  ('Ds571', 'Kalabakan', 'district', 'Sabah', 4.4809, 117.4071),
  ('Ds572', 'Sook', 'district', 'Sabah', 5.1451, 116.3047),
  ('Ds573', 'Sebuyau', 'district', 'Sarawak', 1.5192, 110.9359),
  ('Ds574', 'Gedong', 'district', 'Selangor', 2.9216, 101.2472),
  ('Ds575', 'Pantu', 'district', 'Sarawak', 1.1394, 111.1179),
  ('Ds576', 'Lingga', 'district', 'Sarawak', 1.3519, 111.1717),
  ('Ds577', 'Siburan', 'district', 'Sarawak', 1.3615, 110.4043),
  ('Ds578', 'Labuan', 'district', 'Labuan', 5.2768, 115.2471),
  ('Ds579', 'Bario', 'district', 'Sarawak', 3.7479, 115.4604),
  ('Tn001', 'Perlis', 'town', 'Perlis', 6.4868, 100.2578),
  ('Tn002', 'Jitra', 'town', 'Kedah', 6.2668, 100.4197),
  ('Tn003', 'Alor Star', 'town', 'Kedah', 6.1232, 100.3684),
  ('Tn004', 'Pokok Sena', 'town', 'Kedah', 6.1731, 100.5204),
  ('Tn005', 'Kuala Nerang', 'town', 'Kedah', 6.2552, 100.6071),
  ('Tn006', 'Pendang', 'town', 'Kedah', 5.9721, 100.5502),
  ('Tn007', 'Yan', 'town', 'Kedah', 5.8483, 100.4152),
  ('Tn008', 'Sungai Petani', 'town', 'Kedah', 5.6435, 100.487),
  ('Tn009', 'Balik Pulau', 'town', 'Pulau Pinang', 5.3507, 100.2349),
  ('Tn010', 'Ayer Itam', 'town', 'Pulau Pinang', 5.4019, 100.2778),
  ('Tn011', 'Sik', 'town', 'Kedah', 5.9239, 100.8231),
  ('Tn012', 'Kepala Batas', 'town', 'Pulau Pinang', 5.5168, 100.4255),
  ('Tn013', 'Georgetown', 'town', 'Pulau Pinang', 5.4026, 100.3036),
  ('Tn014', 'Butterworth', 'town', 'Pulau Pinang', 5.4082, 100.3697),
  ('Tn015', 'Bayan Lepas', 'town', 'Pulau Pinang', 5.2948, 100.2596),
  ('Tn016', 'Perai', 'town', 'Pulau Pinang', 5.3871, 100.3822),
  ('Tn017', 'Bukit Tengah', 'town', 'Pulau Pinang', 5.366, 100.421),
  ('Tn018', 'Bukit Mertajam', 'town', 'Pulau Pinang', 5.3643, 100.461),
  ('Tn019', 'Batu Kawan', 'town', 'Pulau Pinang', 5.2626, 100.4305),
  ('Tn020', 'Kulim', 'town', 'Kedah', 5.3707, 100.6172),
  ('Tn021', 'Baling', 'town', 'Kedah', 5.5507, 100.7976),
  ('Tn022', 'Nibong Tebal', 'town', 'Pulau Pinang', 5.1701, 100.4785),
  ('Tn023', 'Serdang', 'town', 'Selangor', 3.0341, 101.7056),
  ('Tn024', 'Parit Buntar', 'town', 'Perak', 5.092, 100.4863),
  ('Tn025', 'Selama', 'town', 'Perak', 5.2181, 100.6917),
  ('Tn026', 'Bagan Serai', 'town', 'Perak', 5.0122, 100.5336),
  ('Tn027', 'Gerik', 'town', 'Perak', 5.4307, 101.1296),
  ('Tn028', 'Lenggong', 'town', 'Perak', 5.1095, 100.9679),
  ('Tn029', 'Taiping', 'town', 'Perak', 4.8547, 100.7439),
  ('Tn030', 'Rantau Panjang', 'town', 'Kelantan', 6.0181, 101.9728),
  ('Tn031', 'Tumpat', 'town', 'Kelantan', 6.1764, 102.1663),
  ('Tn032', 'Pasir Mas', 'town', 'Kelantan', 6.0081, 102.0925),
  ('Tn033', 'Kota Bharu', 'town', 'Kelantan', 6.1248, 102.2378),
  ('Tn034', 'Jeli', 'town', 'Kelantan', 5.59, 101.8172),
  ('Tn035', 'Kuala Kangsar', 'town', 'Perak', 4.7721, 100.9409),
  ('Tn036', 'Sungai Siput', 'town', 'Perak', 4.8197, 101.0722),
  ('Tn037', 'Bachok', 'town', 'Kelantan', 5.9951, 102.3867),
  ('Tn038', 'Tanah Merah', 'town', 'Kelantan', 5.7663, 102.0341),
  ('Tn039', 'Machang', 'town', 'Kelantan', 5.7677, 102.2381),
  ('Tn040', 'Sitiawan', 'town', 'Perak', 4.2162, 100.6952),
  ('Tn041', 'Ipoh', 'town', 'Perak', 4.5987, 101.09),
  ('Tn042', 'Pasir Puteh', 'town', 'Kelantan', 5.8346, 102.383),
  ('Tn043', 'Batu Gajah', 'town', 'Perak', 4.4795, 101.038),
  ('Tn044', 'Seri Iskandar', 'town', 'Perak', 4.3613, 100.9509),
  ('Tn045', 'Kuala Krai', 'town', 'Kelantan', 5.5312, 102.1994),
  ('Tn046', 'Gopeng', 'town', 'Perak', 4.4768, 101.1681),
  ('Tn047', 'Besut', 'town', 'Terengganu', 5.5833, 102.5),
  ('Tn048', 'Jerteh', 'town', 'Terengganu', 5.7381, 102.4972),
  ('Tn049', 'Bagan Datuk', 'town', 'Perak', 3.9167, 100.9167),
  ('Tn050', 'Kampar', 'town', 'Perak', 4.3, 101.15),
  ('Tn051', 'Teluk Intan', 'town', 'Perak', 4.0232, 101.0262),
  ('Tn052', 'Tapah', 'town', 'Perak', 4.1991, 101.2599),
  ('Tn053', 'Gua Musang', 'town', 'Kelantan', 5.0198, 102.0383),
  ('Tn054', 'Sabak Bernam', 'town', 'Selangor', 3.6871, 101.0581),
  ('Tn055', 'Bandar Permaisuri', 'town', 'Terengganu', 5.5207, 102.747),
  ('Tn056', 'Setiu', 'town', 'Terengganu', 5.5501, 102.7355),
  ('Tn057', 'Slim River', 'town', 'Perak', 3.8311, 101.4026),
  ('Tn058', 'Kuala Nerus', 'town', 'Terengganu', 5.3957, 103.0615),
  ('Tn059', 'Kuala Terengganu', 'town', 'Terengganu', 5.3296, 103.1383),
  ('Tn060', 'Kuala Lipis', 'town', 'Pahang', 4.187, 102.0544),
  ('Tn061', 'Kuala Selangor', 'town', 'Selangor', 3.3621, 101.3456),
  ('Tn062', 'Raub', 'town', 'Pahang', 3.8844, 101.792),
  ('Tn063', 'Kuala Kubu Bharu', 'town', 'Selangor', 3.5633, 101.6607),
  ('Tn064', 'Rawang', 'town', 'Selangor', 3.3198, 101.5773),
  ('Tn065', 'Selayang', 'town', 'Selangor', 3.2537, 101.6539),
  ('Tn066', 'Pelabuhan Klang', 'town', 'Selangor', 3.0028, 101.3967),
  ('Tn067', 'Kepong', 'town', 'Kuala Lumpur', 3.214, 101.6348),
  ('Tn068', 'Jerantut', 'town', 'Pahang', 4.2834, 102.5575),
  ('Tn069', 'Batu Caves', 'town', 'Selangor', 3.2369, 101.6833),
  ('Tn070', 'Shah Alam', 'town', 'Selangor', 3.0739, 101.5185),
  ('Tn071', 'Sentul', 'town', 'Kuala Lumpur', 3.1769, 101.6904),
  ('Tn072', 'Bentong', 'town', 'Pahang', 3.3625, 102.0173),
  ('Tn073', 'Jalan Duta', 'town', 'Kuala Lumpur', 3.1485, 101.6765),
  ('Tn074', 'Damansara', 'town', 'Selangor', 3.1537, 101.5935),
  ('Tn075', 'Setapak', 'town', 'Kuala Lumpur', 3.1976, 101.714),
  ('Tn076', 'Petaling Jaya', 'town', 'Selangor', 3.0989, 101.6454),
  ('Tn077', 'Subang Jaya', 'town', 'Selangor', 3.0515, 101.5823),
  ('Tn078', 'Bangsar', 'town', 'Kuala Lumpur', 3.1308, 101.6694),
  ('Tn079', 'Kuala Lumpur', 'town', 'Kuala Lumpur', 3.1517, 101.6942),
  ('Tn080', 'Bukit Bintang', 'town', 'Kuala Lumpur', 3.1471, 101.7086),
  ('Tn081', 'Ampang', 'town', 'Selangor', 3.122, 101.7635),
  ('Tn082', 'Dungun', 'town', 'Terengganu', 4.7644, 103.4184),
  ('Tn083', 'Sungai Besi', 'town', 'Kuala Lumpur', 3.0652, 101.7109),
  ('Tn084', 'Banting', 'town', 'Selangor', 2.8028, 101.4957),
  ('Tn085', 'Seri Kembangan', 'town', 'Selangor', 3.0341, 101.7056),
  ('Tn086', 'Cheras', 'town', 'Kuala Lumpur', 3.0992, 101.7374),
  ('Tn087', 'Cyberjaya', 'town', 'Selangor', 2.9339, 101.6456),
  ('Tn088', 'Putrajaya', 'town', 'Putrajaya', 2.9384, 101.6922),
  ('Tn089', 'Paka', 'town', 'Terengganu', 4.6369, 103.436),
  ('Tn090', 'Kajang', 'town', 'Selangor', 2.9948, 101.7897),
  ('Tn091', 'Mentakab', 'town', 'Pahang', 3.4865, 102.3515),
  ('Tn092', 'Bangi', 'town', 'Selangor', 2.9541, 101.781),
  ('Tn093', 'Semenyih', 'town', 'Selangor', 2.9474, 101.846),
  ('Tn094', 'Kertih', 'town', 'Terengganu', 4.5083, 103.4418),
  ('Tn095', 'Temerloh', 'town', 'Pahang', 3.6124, 102.2567),
  ('Tn096', 'Nilai', 'town', 'Negeri Sembilan', 2.8021, 101.7982),
  ('Tn097', 'Sepang', 'town', 'Selangor', 2.8009, 101.7094),
  ('Tn098', 'Kemaman', 'town', 'Terengganu', 4.2346, 103.4236),
  ('Tn099', 'Kuala Klawang', 'town', 'Negeri Sembilan', 2.9379, 102.0709),
  ('Tn100', 'Jelebu', 'town', 'Negeri Sembilan', 3.0366, 102.1179),
  ('Tn101', 'Triang', 'town', 'Pahang', 3.2467, 102.4162),
  ('Tn102', 'Bera', 'town', 'Pahang', 3.2367, 102.5418),
  ('Tn103', 'Maran', 'town', 'Pahang', 3.6014, 102.641),
  ('Tn104', 'Seremban', 'town', 'Negeri Sembilan', 2.7231, 101.9401),
  ('Tn105', 'Port Dickson', 'town', 'Negeri Sembilan', 2.5262, 101.8106),
  ('Tn106', 'Kuala Pilah', 'town', 'Negeri Sembilan', 2.7431, 102.2155),
  ('Tn107', 'Rembau', 'town', 'Negeri Sembilan', 2.5579, 102.1082),
  ('Tn108', 'Kuantan', 'town', 'Pahang', 3.7974, 103.3219),
  ('Tn109', 'Jempol', 'town', 'Negeri Sembilan', 2.8503, 102.5082),
  ('Tn110', 'Tampin', 'town', 'Negeri Sembilan', 2.5542, 102.446),
  ('Tn111', 'Masjid Tanah', 'town', 'Melaka', 2.3522, 102.109),
  ('Tn112', 'Alor Gajah', 'town', 'Melaka', 2.3835, 102.2108),
  ('Tn113', 'Tangga Batu', 'town', 'Melaka', 2.2495, 102.1555),
  ('Tn114', 'Pekan', 'town', 'Pahang', 3.3782, 103.2096),
  ('Tn115', 'Durian Tunggal', 'town', 'Melaka', 2.3118, 102.2821),
  ('Tn116', 'Muadzam Shah', 'town', 'Pahang', 3.0645, 103.0813),
  ('Tn117', 'Gemas', 'town', 'Negeri Sembilan', 2.5813, 102.6117),
  ('Tn118', 'Ayer Keroh', 'town', 'Melaka', 2.256, 102.2915),
  ('Tn119', 'Bandaraya Melaka', 'town', 'Melaka', 2.1943, 102.2487),
  ('Tn120', 'Jasin', 'town', 'Melaka', 2.3058, 102.4223),
  ('Tn121', 'Tangkak', 'town', 'Johor', 2.25, 102.5833),
  ('Tn122', 'Merlimau', 'town', 'Melaka', 2.1464, 102.4258),
  ('Tn123', 'Segamat', 'town', 'Johor', 2.4922, 102.8449),
  ('Tn124', 'Muar', 'town', 'Johor', 2.05, 102.5667),
  ('Tn125', 'Pagoh', 'town', 'Johor', 2.1495, 102.7715),
  ('Tn126', 'Labis', 'town', 'Johor', 2.3869, 103.02),
  ('Tn127', 'Kuala Rompin', 'town', 'Pahang', 2.8058, 103.4885),
  ('Tn128', 'Yong Peng', 'town', 'Johor', 2.0132, 103.0571),
  ('Tn129', 'Batu Pahat', 'town', 'Johor', 1.9333, 103),
  ('Tn130', 'Ayer Hitam', 'town', 'Johor', 1.9182, 103.1795),
  ('Tn131', 'Kluang', 'town', 'Johor', 2.0323, 103.3191),
  ('Tn132', 'Mersing', 'town', 'Johor', 2.4299, 103.8355),
  ('Tn133', 'Simpang Renggam', 'town', 'Johor', 1.8267, 103.3087),
  ('Tn134', 'Pontian', 'town', 'Johor', 1.5, 103.5),
  ('Tn135', 'Kulai', 'town', 'Johor', 1.6667, 103.6),
  ('Tn136', 'Senai', 'town', 'Johor', 1.6012, 103.6447),
  ('Tn137', 'Kota Tinggi', 'town', 'Johor', 1.7337, 103.9007),
  ('Tn138', 'Iskandar Puteri', 'town', 'Johor', 1.4523, 103.6145),
  ('Tn139', 'Johor Bahru', 'town', 'Johor', 1.4582, 103.7649),
  ('Tn140', 'Pasir Gudang', 'town', 'Johor', 1.4953, 103.9207),
  ('Tn141', 'Lojing', 'town', 'Kelantan', 4.6316, 101.4604),
  ('Tn142', 'Penawar', 'town', 'Johor', 1.5538, 104.2308),
  ('Tn143', 'Kuah', 'town', 'Kedah', 6.3225, 99.8475),
  ('Tn144', 'Kubang Kerian', 'town', 'Kelantan', 6.094, 102.2845),
  ('Tn145', 'Tanah Rata - Brinchang', 'town', 'Pahang', 4.4872, 101.3737),
  ('Tn146', 'Tanjong Malim', 'town', 'Perak', 3.69, 101.5235),
  ('Tn147', 'Meru', 'town', 'Selangor', 3.1387, 101.4411),
  ('Tn148', 'Kelana Jaya', 'town', 'Selangor', 3.1039, 101.5967),
  ('Tn149', 'Bandar Baru Salak Tinggi', 'town', 'Selangor', 2.8123, 101.7373),
  ('Tn150', 'Jertih', 'town', 'Terengganu', 5.7381, 102.4972),
  ('Tn151', 'Pekan Nenas', 'town', 'Johor', 1.5068, 103.5127),
  ('Tn152', 'Bandar Tun Abdul Razak, Jengka', 'town', 'Pahang', 3.7505, 102.564),
  ('Tn153', 'Ulu Tiram', 'town', 'Johor', 1.5994, 103.8209),
  ('Tn154', 'Tanjong Karang', 'town', 'Selangor', 3.4249, 101.1765),
  ('Tn155', 'Gombak (Taman Perwira )', 'town', 'Selangor', 3.3, 101.7),
  ('Tn156', 'Bandar Baru Seri Manjung', 'town', 'Perak', 4.2081, 100.6631),
  ('Tn157', 'Kuala Kedah', 'town', 'Kedah', 6.1072, 100.2935),
  ('Tn158', 'Sri Gombak', 'town', 'Selangor', 3.2444, 101.7044),
  ('Tn159', 'Skudai', 'town', 'Johor', 1.537, 103.6621),
  ('Tn160', 'Bayan Baru', 'town', 'Pulau Pinang', 5.3249, 100.2852),
  ('Tn161', 'Gurun', 'town', 'Kedah', 5.8202, 100.4772),
  ('Tn162', 'Serendah', 'town', 'Selangor', 3.3651, 101.6033),
  ('Tn163', 'Sungai Udang', 'town', 'Melaka', 2.2841, 102.1339),
  ('Tn164', 'Serdang', 'town', 'Selangor', 3.0341, 101.7056),
  ('Tn165', 'Batu Berendam', 'town', 'Melaka', 2.2507, 102.2542),
  ('Tn166', 'Telok Panglima Garang', 'town', 'Selangor', 2.895, 101.4685),
  ('Tn167', 'Sungai Dua - Sungai Nibong', 'town', 'Pulau Pinang', 5.3441, 100.3046),
  ('Tn168', 'Bahau', 'town', 'Negeri Sembilan', 2.81, 102.4004),
  ('Tn169', 'Sabak', 'town', 'Kelantan', 6.1731, 102.3197),
  ('Tn170', 'Gelugor', 'town', 'Pulau Pinang', 5.3684, 100.31),
  ('Tn171', 'Puchong', 'town', 'Selangor', 3.0342, 101.617),
  ('Tn172', 'Tanjung Bungah', 'town', 'Pulau Pinang', 5.4648, 100.2845),
  ('Tn173', 'Tanjung Tokong', 'town', 'Pulau Pinang', 5.451, 100.3056),
  ('Tn174', 'Bandar Utama', 'town', 'Selangor', 3.1432, 101.6114),
  ('Tn175', 'Sungai Ara', 'town', 'Pulau Pinang', 5.3207, 100.2682),
  ('Tn176', 'Juru', 'town', 'Pulau Pinang', 5.3431, 100.4363),
  ('Tn177', 'Jawi', 'town', 'Pulau Pinang', 5.1988, 100.4919),
  ('Tn178', 'Sungai Besar', 'town', 'Selangor', 3.6777, 100.988),
  ('Tn179', 'Kangar', 'town', 'Perlis', 6.4389, 100.1945),
  ('Tn180', 'Ulu Kelang', 'town', 'Selangor', 3.2202, 101.777),
  ('Tn181', 'Klang', 'town', 'Selangor', 3.0448, 101.4447),
  ('Tn182', 'Marang', 'town', 'Terengganu', 5.1667, 103.1667),
  ('Tn183', 'Kuala Berang', 'town', 'Terengganu', 5.0743, 103.0172),
  ('Tn184', 'Kampong Raja', 'town', 'Perak', 4.5589, 100.6718),
  ('Tn185', 'Bandar Al-Muktafi Billah Shah', 'town', 'Terengganu', 4.6158, 103.2076),
  ('Tn186', 'Cukai', 'town', 'Terengganu', 4.2193, 103.4225),
  ('Tn187', 'Kuching', 'town', 'Sarawak', 1.5598, 110.3454),
  ('Tn188', 'Sri Aman', 'town', 'Sarawak', 1.2088, 111.408),
  ('Tn189', 'Sarikei', 'town', 'Sarawak', 2.0508, 111.4176),
  ('Tn190', 'Sibu', 'town', 'Sarawak', 2.2906, 111.8256),
  ('Tn191', 'Mukah', 'town', 'Sarawak', 2.8119, 112.2912),
  ('Tn192', 'Kapit', 'town', 'Sarawak', 2.0139, 112.9357),
  ('Tn193', 'Bintulu', 'town', 'Sarawak', 3.1874, 113.0473),
  ('Tn194', 'Miri', 'town', 'Sarawak', 4.394, 113.988),
  ('Tn195', 'Limbang', 'town', 'Sarawak', 4.352, 115.0602),
  ('Tn196', 'Kota Kinabalu', 'town', 'Sabah', 5.978, 116.0729),
  ('Tn197', 'Keningau', 'town', 'Sabah', 5.2179, 116.2463),
  ('Tn198', 'Tuaran', 'town', 'Sabah', 6.0659, 116.3198),
  ('Tn199', 'Tawau', 'town', 'Sabah', 4.2435, 117.8853),
  ('Tn200', 'Sandakan', 'town', 'Sabah', 5.8391, 118.1159),
  ('Tn201', 'Lahad Datu', 'town', 'Sabah', 5.1155, 118.4306)
on conflict (id) do update set name = excluded.name, kind = excluded.kind, state = excluded.state, lat = excluded.lat, lng = excluded.lng;
