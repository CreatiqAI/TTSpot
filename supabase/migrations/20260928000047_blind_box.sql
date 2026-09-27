-- =============================================================================
-- Blind box cards (phase 1)
--   7 card types (4 common · 2 rare · 1 legendary) · a sealed box for every
--   new member (granted when onboarding finishes) · boxes for points ·
--   open_box() rolls server-side with admin-tunable odds · cards never expire,
--   trade between friends (≤ 9 cards a side) · card rewards: prizes that
--   consume cards, claimed as a QR the partner / admin scans at the counter.
-- All writes go through security-definer RPCs; RLS only grants reads.
-- =============================================================================

-- ------------------------------------------------------------ settings ---
insert into public.platform_settings (key, value, description) values
  ('card_odds',              '{"common": 70, "rare": 25, "legendary": 5}', 'Blind box drop odds in percent. Must add up to 100.'),
  ('box_points_cost',        '100', 'Points for one blind box bought in the Cards screen.'),
  ('trade_max_cards',        '9',   'Most cards each side may put into one trade.'),
  ('card_reward_claim_days', '30',  'Days a claimed card prize stays valid. Cards return to the member if it runs out.')
on conflict (key) do nothing;

insert into public.point_rules (reason, points, label, description, sort) values
  ('box', 0, 'Blind box', 'Spent on a blind box.', 200)
on conflict (reason) do nothing;

-- ---------------------------------------------------------- card types ---
create table public.card_types (
  id           text primary key,                       -- 'c1' … 'c7'
  set_id       text not null default 'set1',           -- seasons later
  number       int  not null,                          -- printed on the card
  name         text not null check (char_length(name) between 1 and 40),
  rarity       text not null check (rarity in ('common', 'rare', 'legendary')),
  description  text,
  art_url      text,                                   -- null = placeholder art in the app
  color        text not null default '#9AA0A8',        -- placeholder tint (hex)
  active       boolean not null default true,
  sort         int not null default 100
);
alter table public.card_types enable row level security;
create policy "card_types: read" on public.card_types for select to authenticated using (true);

insert into public.card_types (id, number, name, rarity, description, color, sort) values
  ('c1', 1, 'Hatch',        'common',    'Small, light, always at the meet.',            '#5B8DEF', 10),
  ('c2', 2, 'Sedan',        'common',    'Four doors, one big turbo.',                    '#4CC38A', 20),
  ('c3', 3, 'Kei',          'common',    'Tiny engine, huge heart.',                      '#F5A524', 30),
  ('c4', 4, 'Pickup',       'common',    'Lifted, loud and full of tyres.',               '#A78BFA', 40),
  ('c5', 5, 'Drift Missile','rare',      'Welded diff. Zero paint. All angle.',           '#2B7CFF', 50),
  ('c6', 6, 'Track Weapon', 'rare',      'Slicks on, mirrors off, lap timer running.',    '#0EA5E9', 60),
  ('c7', 7, 'JDM Legend',   'legendary', 'The poster car. Everyone turns around.',        '#E00008', 70);

-- --------------------------------------------------------------- boxes ---
create table public.card_boxes (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  source        text not null check (source in ('signup', 'points', 'spot', 'admin')),
  status        text not null default 'sealed' check (status in ('sealed', 'opened')),
  card_id       text references public.card_types (id),
  points_spent  int not null default 0,
  ref_id        text,                                  -- place / vendor id for map boxes later
  created_at    timestamptz not null default now(),
  opened_at     timestamptz
);
create index card_boxes_user_idx on public.card_boxes (user_id, status, created_at desc);
create unique index card_boxes_signup_once on public.card_boxes (user_id) where source = 'signup';
alter table public.card_boxes enable row level security;
create policy "card_boxes: read own" on public.card_boxes for select to authenticated using (user_id = auth.uid());

-- ----------------------------------------------------------- user cards ---
-- One row per copy. Trades move the row; a prize claim marks it redeemed.
create table public.user_cards (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  card_id      text not null references public.card_types (id),
  status       text not null default 'held' check (status in ('held', 'redeemed')),
  source       text not null default 'box' check (source in ('box', 'trade', 'admin')),
  box_id       uuid references public.card_boxes (id) on delete set null,
  claim_id     uuid,                                   -- card_reward_claims, fk added below
  acquired_at  timestamptz not null default now(),
  redeemed_at  timestamptz
);
create index user_cards_user_idx on public.user_cards (user_id, status);
create index user_cards_card_idx on public.user_cards (card_id);
alter table public.user_cards enable row level security;
create policy "user_cards: read own" on public.user_cards for select to authenticated using (user_id = auth.uid());

-- -------------------------------------------------------------- trades ---
create table public.card_trades (
  id          uuid primary key default gen_random_uuid(),
  from_user   uuid not null references public.profiles (id) on delete cascade,
  to_user     uuid not null references public.profiles (id) on delete cascade,
  status      text not null default 'proposed' check (status in ('proposed', 'accepted', 'declined', 'cancelled')),
  message     text check (message is null or char_length(message) <= 200),
  created_at  timestamptz not null default now(),
  decided_at  timestamptz,
  constraint trade_not_self check (from_user <> to_user)
);
create index card_trades_from_idx on public.card_trades (from_user, created_at desc);
create index card_trades_to_idx on public.card_trades (to_user, status, created_at desc);
alter table public.card_trades enable row level security;
create policy "card_trades: read mine" on public.card_trades for select to authenticated
  using (from_user = auth.uid() or to_user = auth.uid());

create table public.card_trade_items (
  trade_id      uuid not null references public.card_trades (id) on delete cascade,
  user_card_id  uuid not null references public.user_cards (id) on delete cascade,
  side          text not null check (side in ('offer', 'request')),   -- offer = from_user gives, request = to_user gives
  primary key (trade_id, user_card_id)
);
create index card_trade_items_card_idx on public.card_trade_items (user_card_id);
alter table public.card_trade_items enable row level security;
create policy "card_trade_items: read mine" on public.card_trade_items for select to authenticated
  using (exists (select 1 from public.card_trades t where t.id = trade_id and (t.from_user = auth.uid() or t.to_user = auth.uid())));

-- -------------------------------------------------------- card rewards ---
-- A prize that costs cards. vendor_id null = the platform hands it out.
create table public.card_rewards (
  id              uuid primary key default gen_random_uuid(),
  vendor_id       uuid references public.vendors (id) on delete cascade,
  title           text not null check (char_length(title) between 2 and 80),
  description     text,
  terms           text,
  image_url       text,
  need_common     int not null default 0 check (need_common between 0 and 20),
  need_rare       int not null default 0 check (need_rare between 0 and 20),
  need_legendary  int not null default 0 check (need_legendary between 0 and 20),
  need_full_set   boolean not null default false,       -- one of every active card
  stock           int check (stock is null or stock >= 0),  -- null = unlimited
  claims_count    int not null default 0,
  per_user_limit  int not null default 1 check (per_user_limit between 1 and 100),
  starts_at       timestamptz not null default now(),
  ends_at         timestamptz,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  constraint reward_costs_something check (need_full_set or need_common + need_rare + need_legendary > 0)
);
create index card_rewards_live_idx on public.card_rewards (active, starts_at, ends_at);
alter table public.card_rewards enable row level security;
create policy "card_rewards: read" on public.card_rewards for select to authenticated using (true);

create table public.card_reward_claims (
  id           uuid primary key default gen_random_uuid(),
  reward_id    uuid not null references public.card_rewards (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  code         text not null default encode(extensions.gen_random_bytes(12), 'hex'),
  status       text not null default 'active' check (status in ('active', 'redeemed', 'expired', 'cancelled')),
  cards_used   int not null default 0,
  claimed_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  redeemed_at  timestamptz,
  redeemed_by  uuid references public.profiles (id) on delete set null,
  note         text
);
create index card_reward_claims_user_idx on public.card_reward_claims (user_id, claimed_at desc);
create index card_reward_claims_reward_idx on public.card_reward_claims (reward_id, status);
alter table public.card_reward_claims enable row level security;
create policy "card_reward_claims: read own" on public.card_reward_claims for select to authenticated using (user_id = auth.uid());

alter table public.user_cards add constraint user_cards_claim_fk
  foreign key (claim_id) references public.card_reward_claims (id) on delete set null;

-- =============================================================================
-- boxes: grant, buy, open
-- =============================================================================

-- Weighted rarity roll from platform_settings.card_odds, then a random active card of that rarity.
create or replace function public.roll_card() returns text
language plpgsql security definer set search_path = public as $$
declare
  v jsonb := coalesce((select value from public.platform_settings where key = 'card_odds'), '{"common":70,"rare":25,"legendary":5}'::jsonb);
  wc numeric := greatest(coalesce((v ->> 'common')::numeric, 70), 0);
  wr numeric := greatest(coalesce((v ->> 'rare')::numeric, 25), 0);
  wl numeric := greatest(coalesce((v ->> 'legendary')::numeric, 5), 0);
  r numeric := random() * (wc + wr + wl);
  v_rarity text;
  v_id text;
begin
  v_rarity := case when r < wl then 'legendary' when r < wl + wr then 'rare' else 'common' end;
  select id into v_id from public.card_types where active and rarity = v_rarity order by random() limit 1;
  if v_id is null then select id into v_id from public.card_types where active order by random() limit 1; end if;
  if v_id is null then raise exception 'No cards are live right now'; end if;
  return v_id;
end;
$$;
revoke execute on function public.roll_card() from public, anon, authenticated;

create or replace function public.grant_box(p_user uuid, p_source text, p_ref text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_user is null then return null; end if;
  insert into public.card_boxes (user_id, source, ref_id) values (p_user, p_source, p_ref)
  on conflict (user_id) where source = 'signup' do nothing
  returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function public.grant_box(uuid, text, text) from public, anon, authenticated;

-- One sealed box the moment onboarding finishes (username goes from null to set).
create or replace function public.on_profile_onboarded_box() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.username is null and new.username is not null then
    perform public.grant_box(new.id, 'signup');
  end if;
  return new;
end; $$;
create trigger profiles_after_onboard_box after update of username on public.profiles
  for each row execute function public.on_profile_onboarded_box();

-- Members who joined before this shipped get theirs now.
insert into public.card_boxes (user_id, source)
select id, 'signup' from public.profiles where username is not null
on conflict (user_id) where source = 'signup' do nothing;

-- Buy a sealed box with points. Returns the box id.
create or replace function public.buy_box() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_cost int := public.setting_num('box_points_cost', 100)::int;
  v_balance int;
  v_id uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if v_cost <= 0 then raise exception 'Boxes are not for sale right now'; end if;
  select points into v_balance from public.profiles where id = me for update;
  if coalesce(v_balance, 0) < v_cost then
    raise exception 'You need % points for a box (you have %)', v_cost, coalesce(v_balance, 0);
  end if;
  insert into public.card_boxes (user_id, source, points_spent) values (me, 'points', v_cost) returning id into v_id;
  perform public.award_points(me, -v_cost, 'box', 'card_box', v_id::text, 'Blind box', 'box:' || v_id);
  return v_id;
end;
$$;

-- Open one of my sealed boxes. The roll happens here, never on the phone.
create or replace function public.open_box(p_box uuid) returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  b public.card_boxes%rowtype;
  ct public.card_types%rowtype;
  v_card uuid;
  v_count int;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into b from public.card_boxes where id = p_box and user_id = me for update;
  if b.id is null then raise exception 'That box is not yours'; end if;
  if b.status <> 'sealed' then raise exception 'This box was already opened'; end if;
  select * into ct from public.card_types where id = public.roll_card();
  insert into public.user_cards (user_id, card_id, source, box_id) values (me, ct.id, 'box', b.id) returning id into v_card;
  update public.card_boxes set status = 'opened', card_id = ct.id, opened_at = now() where id = b.id;
  select count(*) into v_count from public.user_cards where user_id = me and card_id = ct.id and status = 'held';
  return json_build_object(
    'user_card_id', v_card, 'card_id', ct.id, 'number', ct.number, 'name', ct.name, 'rarity', ct.rarity,
    'description', ct.description, 'art_url', ct.art_url, 'color', ct.color, 'held', v_count
  );
end;
$$;

create or replace function public.my_boxes()
returns table (id uuid, source text, status text, card_id text, points_spent int, created_at timestamptz, opened_at timestamptz)
language sql stable security definer set search_path = public as $$
  select id, source, status, card_id, points_spent, created_at, opened_at
  from public.card_boxes where user_id = auth.uid()
  order by (status = 'sealed') desc, created_at desc
  limit 200;
$$;

create or replace function public.my_cards()
returns table (id uuid, card_id text, status text, source text, acquired_at timestamptz, redeemed_at timestamptz)
language sql stable security definer set search_path = public as $$
  select id, card_id, status, source, acquired_at, redeemed_at
  from public.user_cards where user_id = auth.uid()
  order by status, acquired_at desc;
$$;

-- A friend's held cards, so I can ask for some in a trade.
create or replace function public.friend_cards(p_user uuid)
returns table (id uuid, card_id text, acquired_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not public.is_friend(auth.uid(), p_user) then raise exception 'You can only trade with friends'; end if;
  return query select uc.id, uc.card_id, uc.acquired_at from public.user_cards uc
    where uc.user_id = p_user and uc.status = 'held' order by uc.acquired_at desc;
end;
$$;

-- =============================================================================
-- trades
-- =============================================================================
create or replace function public.propose_trade(p_to uuid, p_offer uuid[], p_request uuid[], p_message text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_max int := public.setting_num('trade_max_cards', 9)::int;
  v_offer uuid[] := (select coalesce(array_agg(distinct x), '{}') from unnest(coalesce(p_offer, '{}')) x);
  v_request uuid[] := (select coalesce(array_agg(distinct x), '{}') from unnest(coalesce(p_request, '{}')) x);
  v_ok int;
  v_id uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if p_to is null or p_to = me then raise exception 'Pick a friend to trade with'; end if;
  if not public.is_friend(me, p_to) then raise exception 'You can only trade with friends'; end if;
  if exists (select 1 from public.blocks b where (b.blocker_id = me and b.blocked_id = p_to) or (b.blocker_id = p_to and b.blocked_id = me)) then
    raise exception 'You cannot trade with this user';
  end if;
  if cardinality(v_offer) + cardinality(v_request) = 0 then raise exception 'Add at least one card to the trade'; end if;
  if cardinality(v_offer) > v_max or cardinality(v_request) > v_max then raise exception 'Up to % cards a side', v_max; end if;
  select count(*) into v_ok from public.user_cards where id = any(v_offer) and user_id = me and status = 'held';
  if v_ok <> cardinality(v_offer) then raise exception 'One of the cards you offered is no longer yours'; end if;
  select count(*) into v_ok from public.user_cards where id = any(v_request) and user_id = p_to and status = 'held';
  if v_ok <> cardinality(v_request) then raise exception 'One of the cards you asked for is no longer theirs'; end if;
  insert into public.card_trades (from_user, to_user, message) values (me, p_to, nullif(trim(coalesce(p_message, '')), '')) returning id into v_id;
  insert into public.card_trade_items (trade_id, user_card_id, side) select v_id, x, 'offer' from unnest(v_offer) x;
  insert into public.card_trade_items (trade_id, user_card_id, side) select v_id, x, 'request' from unnest(v_request) x;
  perform public.notify(p_to, me, 'cards', p_body => 'trade:' || v_id);
  return v_id;
end;
$$;

-- The receiver accepts or declines. Accepting swaps ownership in one go and
-- re-checks that every card is still where it was when the offer was made.
create or replace function public.decide_trade(p_trade uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  t public.card_trades%rowtype;
  v_offer uuid[];
  v_request uuid[];
  v_ok int;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into t from public.card_trades where id = p_trade for update;
  if t.id is null or t.to_user <> me then raise exception 'Trade not found'; end if;
  if t.status <> 'proposed' then raise exception 'This trade was already %', t.status; end if;
  if not p_accept then
    update public.card_trades set status = 'declined', decided_at = now() where id = p_trade;
    perform public.notify(t.from_user, me, 'cards', p_body => 'declined:' || p_trade);
    return;
  end if;
  select coalesce(array_agg(user_card_id), '{}') into v_offer from public.card_trade_items where trade_id = p_trade and side = 'offer';
  select coalesce(array_agg(user_card_id), '{}') into v_request from public.card_trade_items where trade_id = p_trade and side = 'request';
  -- lock the cards, then verify nothing moved since the offer
  perform 1 from public.user_cards where id = any(v_offer || v_request) for update;
  select count(*) into v_ok from public.user_cards where id = any(v_offer) and user_id = t.from_user and status = 'held';
  if v_ok <> cardinality(v_offer) then
    update public.card_trades set status = 'cancelled', decided_at = now() where id = p_trade;
    raise exception 'Some of the cards offered have already moved. The trade was cancelled.';
  end if;
  select count(*) into v_ok from public.user_cards where id = any(v_request) and user_id = t.to_user and status = 'held';
  if v_ok <> cardinality(v_request) then
    update public.card_trades set status = 'cancelled', decided_at = now() where id = p_trade;
    raise exception 'Some of your cards have already moved. The trade was cancelled.';
  end if;
  update public.user_cards set user_id = t.to_user, source = 'trade', acquired_at = now() where id = any(v_offer);
  update public.user_cards set user_id = t.from_user, source = 'trade', acquired_at = now() where id = any(v_request);
  update public.card_trades set status = 'accepted', decided_at = now() where id = p_trade;
  -- any other open offer that touched these cards is now moot
  update public.card_trades set status = 'cancelled', decided_at = now()
   where status = 'proposed' and id <> p_trade
     and id in (select trade_id from public.card_trade_items where user_card_id = any(v_offer || v_request));
  perform public.notify(t.from_user, me, 'cards', p_body => 'accepted:' || p_trade);
end;
$$;

create or replace function public.cancel_trade(p_trade uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.card_trades set status = 'cancelled', decided_at = now()
   where id = p_trade and from_user = auth.uid() and status = 'proposed';
  if not found then raise exception 'This trade can no longer be cancelled'; end if;
end;
$$;

create or replace function public.my_trades(p_limit int default 100)
returns table (
  id uuid, from_user uuid, to_user uuid, status text, message text, created_at timestamptz, decided_at timestamptz,
  from_username text, from_display_name text, from_avatar_url text,
  to_username text, to_display_name text, to_avatar_url text,
  offer jsonb, request jsonb
)
language sql stable security definer set search_path = public as $$
  select t.id, t.from_user, t.to_user, t.status, t.message, t.created_at, t.decided_at,
         pf.username::text, pf.display_name, pf.avatar_url,
         pt.username::text, pt.display_name, pt.avatar_url,
         coalesce((select jsonb_agg(jsonb_build_object('user_card_id', i.user_card_id, 'card_id', uc.card_id) order by uc.card_id)
                   from public.card_trade_items i join public.user_cards uc on uc.id = i.user_card_id
                   where i.trade_id = t.id and i.side = 'offer'), '[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('user_card_id', i.user_card_id, 'card_id', uc.card_id) order by uc.card_id)
                   from public.card_trade_items i join public.user_cards uc on uc.id = i.user_card_id
                   where i.trade_id = t.id and i.side = 'request'), '[]'::jsonb)
  from public.card_trades t
  join public.profiles pf on pf.id = t.from_user
  join public.profiles pt on pt.id = t.to_user
  where t.from_user = auth.uid() or t.to_user = auth.uid()
  order by (t.status = 'proposed') desc, t.created_at desc
  limit p_limit;
$$;

-- =============================================================================
-- card rewards (prizes that cost cards)
-- =============================================================================

-- Claims that ran out: cards go back to the member.
create or replace function public.expire_card_reward_claims(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c record;
begin
  for c in select id, reward_id from public.card_reward_claims where user_id = p_user and status = 'active' and expires_at < now() loop
    update public.card_reward_claims set status = 'expired' where id = c.id;
    update public.user_cards set status = 'held', claim_id = null, redeemed_at = null where claim_id = c.id;
    update public.card_rewards set claims_count = greatest(claims_count - 1, 0) where id = c.reward_id;
  end loop;
end;
$$;
revoke execute on function public.expire_card_reward_claims(uuid) from public, anon, authenticated;

create or replace function public.card_reward_shop()
returns table (
  id uuid, vendor_id uuid, vendor_name text, vendor_logo text, title text, description text, terms text, image_url text,
  need_common int, need_rare int, need_legendary int, need_full_set boolean, stock int, claims_count int, per_user_limit int,
  starts_at timestamptz, ends_at timestamptz, active boolean, my_claims int, my_active_claim uuid
)
language sql stable security definer set search_path = public as $$
  select r.id, r.vendor_id, v.name, v.logo_url, r.title, r.description, r.terms, r.image_url,
         r.need_common, r.need_rare, r.need_legendary, r.need_full_set, r.stock, r.claims_count, r.per_user_limit,
         r.starts_at, r.ends_at, r.active,
         (select count(*)::int from public.card_reward_claims c where c.reward_id = r.id and c.user_id = auth.uid() and c.status <> 'cancelled' and c.status <> 'expired'),
         (select c.id from public.card_reward_claims c where c.reward_id = r.id and c.user_id = auth.uid() and c.status = 'active' and c.expires_at > now() order by c.claimed_at desc limit 1)
  from public.card_rewards r left join public.vendors v on v.id = r.vendor_id
  where r.active and r.starts_at <= now() and (r.ends_at is null or r.ends_at > now())
    and (r.stock is null or r.claims_count < r.stock)
  order by r.need_full_set desc, r.need_legendary desc, r.need_rare desc, r.need_common desc, r.created_at desc;
$$;

-- Spend cards on a prize. Duplicates go first, and the full set takes one of
-- each. Returns the claim so the app can show its QR.
create or replace function public.claim_card_reward(p_reward uuid) returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  r public.card_rewards%rowtype;
  v_mine int;
  v_used uuid[] := '{}';
  v_pick uuid[];
  v_need int;
  v_set_size int;
  v_rarity text;
  v_id uuid;
  v_exp timestamptz;
begin
  if me is null then raise exception 'Sign in first'; end if;
  perform public.expire_card_reward_claims(me);
  select * into r from public.card_rewards where id = p_reward for update;
  if r.id is null or not r.active then raise exception 'This prize is no longer available'; end if;
  if r.starts_at > now() then raise exception 'This prize is not live yet'; end if;
  if r.ends_at is not null and r.ends_at < now() then raise exception 'This prize has ended'; end if;
  if r.stock is not null and r.claims_count >= r.stock then raise exception 'All of these have been claimed'; end if;
  if r.vendor_id is not null and exists (select 1 from public.vendors vd where vd.id = r.vendor_id and vd.owner_id = me) then
    raise exception 'You cannot claim your own prize';
  end if;
  select count(*) into v_mine from public.card_reward_claims where reward_id = p_reward and user_id = me and status in ('active', 'redeemed');
  if v_mine >= r.per_user_limit then raise exception 'You already claimed this prize'; end if;
  -- lock my held cards so two claims can't spend the same card
  perform 1 from public.user_cards where user_id = me and status = 'held' for update;

  if r.need_full_set then
    select count(*) into v_set_size from public.card_types where active;
    select coalesce(array_agg(id), '{}') into v_pick from (
      select distinct on (uc.card_id) uc.id
      from public.user_cards uc join public.card_types ct on ct.id = uc.card_id
      where uc.user_id = me and uc.status = 'held' and ct.active
      order by uc.card_id, uc.acquired_at asc
    ) s;
    if cardinality(v_pick) < v_set_size then
      raise exception 'You need the full set for this (% of % cards)', cardinality(v_pick), v_set_size;
    end if;
    v_used := v_used || v_pick;
  end if;

  for v_rarity, v_need in select * from (values ('common', r.need_common), ('rare', r.need_rare), ('legendary', r.need_legendary)) t(rar, need) loop
    if v_need <= 0 then continue; end if;
    select coalesce(array_agg(id), '{}') into v_pick from (
      select uc.id
      from public.user_cards uc join public.card_types ct on ct.id = uc.card_id
      where uc.user_id = me and uc.status = 'held' and ct.rarity = v_rarity and not (uc.id = any(v_used))
      order by (select count(*) from public.user_cards u2 where u2.user_id = me and u2.status = 'held' and u2.card_id = uc.card_id) desc,
               uc.acquired_at asc
      limit v_need
    ) s;
    if cardinality(v_pick) < v_need then
      raise exception 'You need % more % card%', v_need - cardinality(v_pick), v_rarity, case when v_need - cardinality(v_pick) = 1 then '' else 's' end;
    end if;
    v_used := v_used || v_pick;
  end loop;

  v_exp := coalesce(r.ends_at, now() + make_interval(days => public.setting_num('card_reward_claim_days', 30)::int));
  insert into public.card_reward_claims (reward_id, user_id, cards_used, expires_at)
  values (p_reward, me, cardinality(v_used), v_exp) returning id into v_id;
  update public.user_cards set status = 'redeemed', claim_id = v_id, redeemed_at = now() where id = any(v_used);
  update public.card_rewards set claims_count = claims_count + 1 where id = p_reward;
  return json_build_object('id', v_id, 'expires_at', v_exp, 'cards_used', cardinality(v_used));
end;
$$;

create or replace function public.my_card_reward_claims(p_limit int default 100)
returns table (id uuid, reward_id uuid, title text, vendor_name text, image_url text, status text, cards_used int,
               claimed_at timestamptz, expires_at timestamptz, redeemed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  return query
    select c.id, c.reward_id, r.title, coalesce(v.name, 'TT Spot'), r.image_url,
           case when c.status = 'active' and c.expires_at < now() then 'expired' else c.status end,
           c.cards_used, c.claimed_at, c.expires_at, c.redeemed_at
    from public.card_reward_claims c
    join public.card_rewards r on r.id = c.reward_id
    left join public.vendors v on v.id = r.vendor_id
    where c.user_id = auth.uid()
    order by (c.status = 'active' and c.expires_at > now()) desc, c.claimed_at desc
    limit p_limit;
end;
$$;

-- What the member shows at the counter.
create or replace function public.card_reward_claim_payload(p_claim uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare c public.card_reward_claims%rowtype;
begin
  select * into c from public.card_reward_claims where id = p_claim and user_id = auth.uid();
  if c.id is null then raise exception 'Prize not found'; end if;
  if c.status <> 'active' then raise exception 'This prize was already %', c.status; end if;
  if c.expires_at < now() then raise exception 'This prize claim expired'; end if;
  return 'ttspot://cardreward/' || c.id || '/' || c.code;
end;
$$;

-- Partner (its own prizes) or admin (everything): what is this QR.
create or replace function public.lookup_card_reward_claim(p_claim uuid, p_code text) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  c public.card_reward_claims%rowtype;
  r public.card_rewards%rowtype;
  p public.profiles%rowtype;
  v_vendor uuid := public.my_vendor_id();
begin
  select * into c from public.card_reward_claims where id = p_claim;
  if c.id is null or c.code <> p_code then raise exception 'That QR is not a valid prize'; end if;
  select * into r from public.card_rewards where id = c.reward_id;
  if not public.is_admin() and (v_vendor is null or r.vendor_id is distinct from v_vendor) then
    raise exception 'This prize belongs to another partner';
  end if;
  select * into p from public.profiles where id = c.user_id;
  return json_build_object(
    'id', c.id, 'title', r.title, 'description', r.description, 'terms', r.terms, 'image_url', r.image_url,
    'status', case when c.status = 'active' and c.expires_at < now() then 'expired' else c.status end,
    'cards_used', c.cards_used, 'expires_at', c.expires_at, 'redeemed_at', c.redeemed_at,
    'username', p.username, 'display_name', p.display_name, 'avatar_url', p.avatar_url
  );
end;
$$;

create or replace function public.redeem_card_reward_claim(p_claim uuid, p_code text, p_note text default null) returns json
language plpgsql security definer set search_path = public as $$
declare
  c public.card_reward_claims%rowtype;
  r public.card_rewards%rowtype;
  v_vendor uuid := public.my_vendor_id();
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into c from public.card_reward_claims where id = p_claim for update;
  if c.id is null or c.code <> p_code then raise exception 'That QR is not a valid prize'; end if;
  select * into r from public.card_rewards where id = c.reward_id;
  if not public.is_admin() and (v_vendor is null or r.vendor_id is distinct from v_vendor) then
    raise exception 'This prize belongs to another partner';
  end if;
  if c.status <> 'active' then raise exception 'This prize was already %', c.status; end if;
  if c.expires_at < now() then raise exception 'This prize claim expired'; end if;
  update public.card_reward_claims set status = 'redeemed', redeemed_at = now(), redeemed_by = auth.uid(), note = nullif(trim(coalesce(p_note, '')), '')
   where id = p_claim;
  perform public.notify(c.user_id, null, 'cards', p_body => 'redeemed:' || r.title);
  return json_build_object('id', c.id, 'title', r.title);
end;
$$;

-- =============================================================================
-- admin
-- =============================================================================
create or replace function public.admin_save_card_type(
  p_id text, p_name text, p_rarity text, p_number int, p_description text default null, p_art_url text default null,
  p_color text default null, p_active boolean default true, p_set text default 'set1'
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  insert into public.card_types (id, set_id, number, name, rarity, description, art_url, color, active, sort)
  values (p_id, coalesce(p_set, 'set1'), p_number, trim(p_name), p_rarity, nullif(trim(coalesce(p_description, '')), ''), nullif(trim(coalesce(p_art_url, '')), ''),
          coalesce(nullif(trim(coalesce(p_color, '')), ''), '#9AA0A8'), coalesce(p_active, true), p_number * 10)
  on conflict (id) do update set
    set_id = excluded.set_id, number = excluded.number, name = excluded.name, rarity = excluded.rarity, description = excluded.description,
    art_url = excluded.art_url, color = excluded.color, active = excluded.active, sort = excluded.sort;
end;
$$;

create or replace function public.admin_save_card_reward(
  p_id uuid, p_title text, p_description text, p_terms text, p_image_url text, p_vendor uuid,
  p_common int, p_rare int, p_legendary int, p_full_set boolean, p_stock int, p_per_user int,
  p_starts timestamptz, p_ends timestamptz, p_active boolean
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_ends is not null and p_ends <= coalesce(p_starts, now()) then raise exception 'End must be after start'; end if;
  if p_id is null then
    insert into public.card_rewards (vendor_id, title, description, terms, image_url, need_common, need_rare, need_legendary, need_full_set,
                                     stock, per_user_limit, starts_at, ends_at, active)
    values (p_vendor, trim(p_title), nullif(trim(coalesce(p_description, '')), ''), nullif(trim(coalesce(p_terms, '')), ''), nullif(trim(coalesce(p_image_url, '')), ''),
            coalesce(p_common, 0), coalesce(p_rare, 0), coalesce(p_legendary, 0), coalesce(p_full_set, false),
            p_stock, coalesce(p_per_user, 1), coalesce(p_starts, now()), p_ends, coalesce(p_active, true))
    returning id into v_id;
    return v_id;
  end if;
  update public.card_rewards
     set vendor_id = p_vendor, title = trim(p_title), description = nullif(trim(coalesce(p_description, '')), ''), terms = nullif(trim(coalesce(p_terms, '')), ''),
         image_url = nullif(trim(coalesce(p_image_url, '')), ''), need_common = coalesce(p_common, 0), need_rare = coalesce(p_rare, 0),
         need_legendary = coalesce(p_legendary, 0), need_full_set = coalesce(p_full_set, false), stock = p_stock, per_user_limit = coalesce(p_per_user, 1),
         starts_at = coalesce(p_starts, starts_at), ends_at = p_ends, active = coalesce(p_active, active)
   where id = p_id;
  if not found then raise exception 'Prize not found'; end if;
  return p_id;
end;
$$;

create or replace function public.admin_card_rewards()
returns table (id uuid, vendor_id uuid, vendor_name text, title text, description text, terms text, image_url text,
               need_common int, need_rare int, need_legendary int, need_full_set boolean, stock int, claims_count int, per_user_limit int,
               starts_at timestamptz, ends_at timestamptz, active boolean, redeemed_count int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select r.id, r.vendor_id, v.name, r.title, r.description, r.terms, r.image_url,
           r.need_common, r.need_rare, r.need_legendary, r.need_full_set, r.stock, r.claims_count, r.per_user_limit,
           r.starts_at, r.ends_at, r.active,
           (select count(*)::int from public.card_reward_claims c where c.reward_id = r.id and c.status = 'redeemed')
    from public.card_rewards r left join public.vendors v on v.id = r.vendor_id
    order by r.active desc, r.created_at desc;
end;
$$;

-- Everyone's claims, newest first, so the admin can see what is waiting to be handed out.
create or replace function public.admin_card_reward_claims(p_limit int default 100)
returns table (id uuid, code text, title text, vendor_name text, username text, display_name text, avatar_url text, status text,
               cards_used int, claimed_at timestamptz, expires_at timestamptz, redeemed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select c.id, c.code, r.title, coalesce(v.name, 'TT Spot'), p.username::text, p.display_name, p.avatar_url,
           case when c.status = 'active' and c.expires_at < now() then 'expired' else c.status end,
           c.cards_used, c.claimed_at, c.expires_at, c.redeemed_at
    from public.card_reward_claims c
    join public.card_rewards r on r.id = c.reward_id
    left join public.vendors v on v.id = r.vendor_id
    join public.profiles p on p.id = c.user_id
    order by (c.status = 'active') desc, c.claimed_at desc
    limit p_limit;
end;
$$;

-- Hand a member sealed boxes by username (giveaways, make-goods).
create or replace function public.admin_grant_boxes(p_username text, p_count int default 1) returns int
language plpgsql security definer set search_path = public as $$
declare v_user uuid; i int;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select id into v_user from public.profiles where username = lower(trim(p_username));
  if v_user is null then raise exception 'No member called @%', p_username; end if;
  if p_count < 1 or p_count > 50 then raise exception 'Between 1 and 50 boxes'; end if;
  for i in 1..p_count loop
    insert into public.card_boxes (user_id, source) values (v_user, 'admin');
  end loop;
  return p_count;
end;
$$;

create or replace function public.admin_card_stats() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return json_build_object(
    'boxes_sealed', (select count(*) from public.card_boxes where status = 'sealed'),
    'boxes_opened', (select count(*) from public.card_boxes where status = 'opened'),
    'boxes_bought_30d', (select count(*) from public.card_boxes where source = 'points' and created_at > now() - interval '30 days'),
    'cards_held', (select count(*) from public.user_cards where status = 'held'),
    'collectors', (select count(distinct user_id) from public.user_cards),
    'trades_30d', (select count(*) from public.card_trades where status = 'accepted' and decided_at > now() - interval '30 days'),
    'trades_open', (select count(*) from public.card_trades where status = 'proposed'),
    'claims_30d', (select count(*) from public.card_reward_claims where claimed_at > now() - interval '30 days'),
    'claims_waiting', (select count(*) from public.card_reward_claims where status = 'active' and expires_at > now()),
    'by_rarity', (select coalesce(json_object_agg(ct.rarity, n), '{}'::json) from (
                    select ct.rarity, count(uc.id) n from public.card_types ct left join public.user_cards uc on uc.card_id = ct.id and uc.status = 'held'
                    group by ct.rarity) ct)
  );
end;
$$;
