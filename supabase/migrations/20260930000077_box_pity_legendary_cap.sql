-- =============================================================================
-- Blind box: a limited legendary run · pity · public odds
--   * Legendary is capped at platform_settings.legendary_stock_total (100)
--     copies, ever. card_stock is the mint: one counter row per capped rarity
--     that only goes up, so trades, prize spends and deleted accounts never
--     free stock. Every legendary copy, whatever inserts it (a box, an admin
--     in the table editor, a future grant RPC), takes the next serial from it
--     ("No. 37 of 100") or fails once the run is out. When the run is out the
--     roll gives legendary a weight of 0 and common / rare share its slice.
--   * Pity: at least one rare or better in every 10 boxes, per member. Read
--     from the member's own opened boxes (card_boxes.card_id is what each box
--     rolled and never moves), not from user_cards (a traded card changes
--     owner and source) and not from a counter column (can drift, needs
--     backfilling, and a missed write breaks the promise silently).
--   * box_odds(): what the shop shows, from the same weights the roll uses.
--   roll_card_for(user) replaces roll_card() inside open_box; open_box's
--   return shape is unchanged.
-- =============================================================================

-- ------------------------------------------------------------ settings ---
-- card_odds stays as the owner set it (89.5 / 10 / 0.5).
insert into public.platform_settings (key, value, description) values
  ('legendary_stock_total', '100', 'Legendary cards that will ever exist, from boxes, admin grants or anything else. Once they are all out, boxes stop dropping legendary and common / rare share its odds.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------- mint ---
create table public.card_stock (
  rarity  text primary key check (rarity in ('common', 'rare', 'legendary')),
  issued  int  not null default 0 check (issued >= 0)       -- copies ever made; never goes down
);
alter table public.card_stock enable row level security;    -- no policies: read through box_odds()

alter table public.user_cards add column serial int check (serial is null or serial > 0);
create unique index user_cards_serial_once on public.user_cards (serial) where serial is not null;

-- Legendaries already out, numbered in the order they were pulled.
with l as (
  select uc.id, row_number() over (order by coalesce(b.opened_at, uc.acquired_at), uc.id) as n
  from public.user_cards uc
  join public.card_types ct on ct.id = uc.card_id
  left join public.card_boxes b on b.id = uc.box_id
  where ct.rarity = 'legendary'
)
update public.user_cards u set serial = l.n from l where u.id = l.id;

insert into public.card_stock (rarity, issued)
select 'legendary', count(*)::int from public.user_cards uc join public.card_types ct on ct.id = uc.card_id where ct.rarity = 'legendary'
on conflict (rarity) do update set issued = greatest(public.card_stock.issued, excluded.issued);

-- Copies left in the legendary run (never below 0).
create or replace function public.legendary_left() returns int
language sql stable security definer set search_path = public as $$
  select greatest(greatest(public.setting_num('legendary_stock_total', 100)::int, 0)
                  - coalesce((select issued from public.card_stock where rarity = 'legendary'), 0), 0);
$$;

-- Each legendary copy takes the next serial or fails when the run is out.
-- The UPDATE row-locks the counter until the transaction ends, so two copies
-- can never share a number or slip past the total. A serial passed in is
-- ignored: the mint always numbers it.
create or replace function public.mint_legendary_serial() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_total int := greatest(public.setting_num('legendary_stock_total', 100)::int, 0);
  v_serial int;
begin
  if tg_op = 'UPDATE' and (new.card_id is not distinct from old.card_id or old.serial is not null) then return new; end if;
  if not exists (select 1 from public.card_types where id = new.card_id and rarity = 'legendary') then
    if tg_op = 'INSERT' then new.serial := null; end if;
    return new;
  end if;
  update public.card_stock set issued = issued + 1
   where rarity = 'legendary' and issued < v_total
  returning issued into v_serial;
  if v_serial is null then raise exception 'All % legendary cards are out. There are none left to give.', v_total; end if;
  new.serial := v_serial;
  return new;
end;
$$;
revoke execute on function public.mint_legendary_serial() from public, anon, authenticated;
create trigger user_cards_mint_legendary before insert or update of card_id on public.user_cards
  for each row execute function public.mint_legendary_serial();

-- ---------------------------------------------------------------- pity ---
-- Boxes in a row without a rare or better that guarantee one on the next.
create or replace function public.box_pity_every() returns int
language sql immutable as $$ select 10 $$;

-- Boxes a member opened since their last rare or better (all of them if they
-- never had one).
create or replace function public.box_pity_streak(p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int
  from public.card_boxes b
  where b.user_id = p_user and b.status = 'opened'
    and b.opened_at > coalesce((
      select max(b2.opened_at)
      from public.card_boxes b2 join public.card_types ct on ct.id = b2.card_id
      where b2.user_id = p_user and b2.status = 'opened' and ct.rarity <> 'common'
    ), '-infinity'::timestamptz);
$$;
revoke execute on function public.box_pity_streak(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------- weights ---
-- The weights a box rolls with right now: card_odds, minus any rarity with
-- no live card, minus legendary once the run is out ([p_sold_out] forces
-- that), and on a pity box minus common so rare and legendary split it by
-- their own odds. roll_card_for() and box_odds() both read this, so the odds
-- on screen are the odds in the roll.
create or replace function public.box_weights(p_pity boolean default false, p_sold_out boolean default null)
returns table (w_common numeric, w_rare numeric, w_legendary numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  v jsonb := coalesce((select value from public.platform_settings where key = 'card_odds'), '{"common":70,"rare":25,"legendary":5}'::jsonb);
begin
  w_common    := greatest(coalesce((v ->> 'common')::numeric, 70), 0);
  w_rare      := greatest(coalesce((v ->> 'rare')::numeric, 25), 0);
  w_legendary := greatest(coalesce((v ->> 'legendary')::numeric, 5), 0);
  if not exists (select 1 from public.card_types where active and rarity = 'common') then w_common := 0; end if;
  if not exists (select 1 from public.card_types where active and rarity = 'rare') then w_rare := 0; end if;
  if not exists (select 1 from public.card_types where active and rarity = 'legendary') then w_legendary := 0; end if;
  if coalesce(p_sold_out, public.legendary_left() <= 0) then w_legendary := 0; end if;
  if p_pity and w_rare + w_legendary > 0 then w_common := 0; end if;   -- nothing better live: a plain box
  return next;
end;
$$;
revoke execute on function public.box_weights(boolean, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------- roll ---
-- One roll for a member, pity and the legendary cap applied (null member =
-- no pity). Race safety:
--   * the member's rolls queue on an advisory lock, so two boxes opened at
--     once both see the other's result before counting pity;
--   * landing legendary locks the mint row until the transaction ends and
--     re-reads the stock under the lock. A second box landing legendary at
--     the same moment waits, then sees the new count; if that was the last
--     copy it re-rolls without legendary. The insert in open_box then takes
--     the serial from the row this transaction already holds.
create or replace function public.roll_card_for(p_user uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_pity boolean := false;
  w record;
  r numeric;
  v_rarity text;
  v_issued int;
  v_id text;
begin
  if p_user is not null then
    perform pg_advisory_xact_lock(hashtextextended('box_roll:' || p_user::text, 0));
    v_pity := public.box_pity_streak(p_user) >= public.box_pity_every() - 1;
  end if;
  select * into w from public.box_weights(v_pity);
  if w.w_common + w.w_rare + w.w_legendary <= 0 then raise exception 'No cards are live right now'; end if;
  r := random() * (w.w_common + w.w_rare + w.w_legendary);
  v_rarity := case when r < w.w_legendary then 'legendary' when r < w.w_legendary + w.w_rare then 'rare' else 'common' end;
  if v_rarity = 'legendary' then
    select issued into v_issued from public.card_stock where rarity = 'legendary' for update;
    if v_issued is null or v_issued >= greatest(public.setting_num('legendary_stock_total', 100)::int, 0) then
      -- the last copy went while this box rolled
      select * into w from public.box_weights(v_pity, true);
      if w.w_common + w.w_rare <= 0 then raise exception 'No cards are live right now'; end if;
      r := random() * (w.w_common + w.w_rare);
      v_rarity := case when r < w.w_rare then 'rare' else 'common' end;
    end if;
  end if;
  select id into v_id from public.card_types where active and rarity = v_rarity order by random() limit 1;
  if v_id is null then raise exception 'No cards are live right now'; end if;
  return v_id;
end;
$$;
revoke execute on function public.roll_card_for(uuid) from public, anon, authenticated;

-- Kept for anything that still calls it: the cap applies, pity doesn't.
create or replace function public.roll_card() returns text
language plpgsql security definer set search_path = public as $$
begin
  return public.roll_card_for(null);
end;
$$;
revoke execute on function public.roll_card() from public, anon, authenticated;

-- Open one of my sealed boxes. Same as before, rolled for me (pity + cap).
create or replace function public.open_box(p_box uuid) returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  b public.card_boxes%rowtype;
  ct public.card_types%rowtype;
  v_roll text;
  v_card uuid;
  v_count int;
begin
  if me is null then raise exception 'Sign in first'; end if;
  select * into b from public.card_boxes where id = p_box and user_id = me for update;
  if b.id is null then raise exception 'That box is not yours'; end if;
  if b.status <> 'sealed' then raise exception 'This box was already opened'; end if;
  v_roll := public.roll_card_for(me);
  select * into ct from public.card_types where id = v_roll;
  if ct.id is null then raise exception 'No cards are live right now'; end if;
  insert into public.user_cards (user_id, card_id, source, box_id) values (me, ct.id, 'box', b.id) returning id into v_card;
  update public.card_boxes set status = 'opened', card_id = ct.id, opened_at = now() where id = b.id;
  select count(*) into v_count from public.user_cards where user_id = me and card_id = ct.id and status = 'held';
  return json_build_object(
    'user_card_id', v_card, 'card_id', ct.id, 'number', ct.number, 'name', ct.name, 'rarity', ct.rarity,
    'description', ct.description, 'art_url', ct.art_url, 'color', ct.color, 'held', v_count
  );
end;
$$;

-- ---------------------------------------------------------------- odds ---
-- What a box can drop right now, in percent: per rarity and per card (cards
-- of one rarity share its slice equally), the same on a pity box, the
-- legendary run, and the caller's pity count (null when signed out).
create or replace function public.box_odds() returns json
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_total int := greatest(public.setting_num('legendary_stock_total', 100)::int, 0);
  v_issued int := coalesce((select issued from public.card_stock where rarity = 'legendary'), 0);
  v_every int := public.box_pity_every();
  v_streak int := case when me is null then null else public.box_pity_streak(me) end;
  w record;
  p record;
  ws numeric;
  ps numeric;
  pc numeric; pr numeric; pl numeric;     -- percent, plain box
  qc numeric; qr numeric; ql numeric;     -- percent, pity box
  v_cards json;
begin
  select * into w from public.box_weights(false);
  select * into p from public.box_weights(true);
  ws := w.w_common + w.w_rare + w.w_legendary;
  ps := p.w_common + p.w_rare + p.w_legendary;
  pc := case when ws > 0 then 100 * w.w_common / ws else 0 end;
  pr := case when ws > 0 then 100 * w.w_rare / ws else 0 end;
  pl := case when ws > 0 then 100 * w.w_legendary / ws else 0 end;
  qc := case when ps > 0 then 100 * p.w_common / ps else 0 end;
  qr := case when ps > 0 then 100 * p.w_rare / ps else 0 end;
  ql := case when ps > 0 then 100 * p.w_legendary / ps else 0 end;

  select coalesce(json_agg(json_build_object(
           'card_id', ct.id, 'number', ct.number, 'name', ct.name, 'rarity', ct.rarity,
           'percent', round(case ct.rarity when 'common' then pc when 'rare' then pr else pl end / n.cnt, 4),
           'pity_percent', round(case ct.rarity when 'common' then qc when 'rare' then qr else ql end / n.cnt, 4)
         ) order by ct.sort, ct.number), '[]'::json)
    into v_cards
  from public.card_types ct
  join (select rarity, count(*) as cnt from public.card_types where active group by rarity) n on n.rarity = ct.rarity
  where ct.active;

  return json_build_object(
    'odds', json_build_object('common', round(pc, 4), 'rare', round(pr, 4), 'legendary', round(pl, 4)),
    'pity_odds', json_build_object('common', round(qc, 4), 'rare', round(qr, 4), 'legendary', round(ql, 4)),
    'cards', v_cards,
    'legendary_total', v_total,
    'legendary_issued', v_issued,
    'legendary_left', greatest(v_total - v_issued, 0),
    'pity_every', v_every,
    'pity_streak', v_streak,
    'pity_left', case when v_streak is null then null else greatest(v_every - v_streak, 1) end
  );
end;
$$;
grant execute on function public.box_odds() to anon, authenticated;

-- ---------------------------------------------------------------- mine ---
-- my_cards gains the serial ("No. 1 of 100") for legendary copies.
drop function if exists public.my_cards();
create function public.my_cards()
returns table (id uuid, card_id text, status text, source text, acquired_at timestamptz, redeemed_at timestamptz, serial int)
language sql stable security definer set search_path = public as $$
  select id, card_id, status, source, acquired_at, redeemed_at, serial
  from public.user_cards where user_id = auth.uid()
  order by status, acquired_at desc;
$$;
grant execute on function public.my_cards() to authenticated;
