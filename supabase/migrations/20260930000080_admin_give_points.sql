-- Admin "Give points": the TT Spot team hands a member points (or takes some
-- back) from the admin panel. Booked in the ledger as 'freepoints' (the rule
-- from 0079, "Free points") and the member gets a points notification, which
-- the push hook sends on like any other.

-- p_delta > 0 gives, < 0 takes back (never below 0). Capped at 100,000 either
-- way per call. Returns the member's new balance.
create or replace function public.admin_give_points(p_user uuid, p_delta int, p_note text default null)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_note text := nullif(left(btrim(coalesce(p_note, '')), 140), '');
  v_have int;
  v_amount text := to_char(abs(coalesce(p_delta, 0)), 'FM999,999,999') || case when abs(coalesce(p_delta, 0)) = 1 then ' point' else ' points' end;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_delta is null or p_delta = 0 then raise exception 'Enter an amount'; end if;
  if abs(p_delta) > 100000 then raise exception 'That''s too many. Up to 100,000 points at a time.'; end if;
  -- Locks the balance so two admins taking at once can't push it below 0.
  select points into v_have from public.profiles where id = p_user for update;
  if not found then raise exception 'Member not found'; end if;
  if v_have + p_delta < 0 then
    raise exception 'They only have % point%. You can take up to that.', to_char(v_have, 'FM999,999,999'), case when v_have = 1 then '' else 's' end;
  end if;

  perform public.award_points(p_user, p_delta, 'freepoints', null, null,
    coalesce(v_note, case when p_delta > 0 then 'Free points' else 'Taken back by TT Spot' end), 'freepoints:' || gen_random_uuid());

  perform public.notify(p_user, null, 'points', p_body =>
    case when p_delta > 0 then 'TT Spot gave you ' || v_amount else 'TT Spot took back ' || v_amount end
    || coalesce(': ' || v_note, '.'));

  return v_have + p_delta;
end;
$$;

-- The latest gifts and take-backs for the admin tool: who, how much, when, note.
create index if not exists point_ledger_freepoints_idx on public.point_ledger (created_at desc) where reason = 'freepoints';

create or replace function public.admin_freepoints_recent(p_limit int default 30)
returns table (id bigint, user_id uuid, username text, display_name text, avatar_url text, delta int, note text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.id, l.user_id, p.username::text, p.display_name, p.avatar_url, l.delta, l.note, l.created_at
  from public.point_ledger l
  join public.profiles p on p.id = l.user_id
  where public.is_admin() and l.reason = 'freepoints'
  order by l.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

revoke execute on function public.admin_give_points(uuid, int, text) from public, anon;
revoke execute on function public.admin_freepoints_recent(int) from public, anon;
grant execute on function public.admin_give_points(uuid, int, text) to authenticated;
grant execute on function public.admin_freepoints_recent(int) to authenticated;

-- ---------------------------------------------------------------------------
-- Avatars: a member without a photo gets a TiTi picked from their user id, so
-- every list that shows a member needs the id to show the same TiTi as their
-- profile. These returned name + avatar but no id; now they add user_id.
-- Bodies are otherwise the live ones, unchanged.

-- Admin · prize claims (returns a table, so drop + create).
drop function if exists public.admin_card_reward_claims(int);
create function public.admin_card_reward_claims(p_limit int default 100)
returns table (id uuid, code text, title text, vendor_name text, username text, display_name text, avatar_url text, status text,
               cards_used int, claimed_at timestamptz, expires_at timestamptz, redeemed_at timestamptz, user_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select c.id, c.code, r.title, coalesce(v.name, 'TT Spot'), p.username::text, p.display_name, p.avatar_url,
           case when c.status = 'active' and c.expires_at < now() then 'expired' else c.status end,
           c.cards_used, c.claimed_at, c.expires_at, c.redeemed_at, c.user_id
    from public.card_reward_claims c
    join public.card_rewards r on r.id = c.reward_id
    left join public.vendors v on v.id = r.vendor_id
    join public.profiles p on p.id = c.user_id
    order by (c.status = 'active') desc, c.claimed_at desc
    limit p_limit;
end;
$$;
revoke execute on function public.admin_card_reward_claims(int) from public, anon;
grant execute on function public.admin_card_reward_claims(int) to authenticated;

-- Partner · redemptions list (table, drop + create).
drop function if exists public.my_vendor_redemptions(int);
create function public.my_vendor_redemptions(p_limit int default 100)
returns table (id uuid, title text, username text, avatar_url text, bill_amount numeric, commission_rate numeric, commission_amount numeric,
               receipt_url text, note text, created_at timestamptz, user_id uuid)
language sql stable security definer set search_path = public as $$
  select r.id, v.title, pr.username::text, pr.avatar_url, r.bill_amount, r.commission_rate, r.commission_amount, r.receipt_url, r.note, r.created_at, r.user_id
  from public.voucher_redemptions r
  join public.vouchers v on v.id = r.voucher_id
  join public.profiles pr on pr.id = r.user_id
  where r.vendor_id = public.my_vendor_id()
  order by r.created_at desc
  limit p_limit;
$$;
revoke execute on function public.my_vendor_redemptions(int) from public, anon;
grant execute on function public.my_vendor_redemptions(int) to authenticated;

-- Lucky draw results (table, drop + create).
drop function if exists public.draw_results(uuid);
create function public.draw_results(p_draw uuid)
returns table (rank int, prize text, display_name text, username text, avatar_url text, status text, is_alternate boolean, user_id uuid)
language sql stable security definer set search_path = public as $$
  select w.rank, p.name, coalesce(pr.display_name, pr.username::text), pr.username::text, pr.avatar_url, w.status, w.is_alternate, w.user_id
  from public.lucky_draw_winners w
  join public.lucky_draws d on d.id = w.draw_id and d.status = 'drawn'
  join public.lucky_draw_prizes p on p.id = w.prize_id
  join public.profiles pr on pr.id = w.user_id
  where w.draw_id = p_draw and auth.uid() is not null
  order by p.sort, w.rank;
$$;
revoke execute on function public.draw_results(uuid) from public, anon;
grant execute on function public.draw_results(uuid) to authenticated;

-- Partner / admin · prize QR lookup.
create or replace function public.lookup_card_reward_claim(p_claim uuid, p_code text)
returns json
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
    'username', p.username, 'display_name', p.display_name, 'avatar_url', p.avatar_url, 'user_id', c.user_id
  );
end;
$$;

-- Partner · voucher QR lookup.
create or replace function public.lookup_voucher_claim(p_claim uuid, p_code text)
returns json
language plpgsql stable security definer set search_path = public as $$
declare
  c public.voucher_claims%rowtype;
  v public.vouchers%rowtype;
  v_vendor uuid := public.my_vendor_id();
  v_username text;
  v_display text;
  v_avatar text;
begin
  if v_vendor is null then raise exception 'Only partners can scan vouchers'; end if;
  select * into c from public.voucher_claims where id = p_claim;
  if c.id is null or c.code <> p_code then raise exception 'Invalid voucher QR'; end if;
  select * into v from public.vouchers where id = c.voucher_id;
  if v.vendor_id <> v_vendor then raise exception 'This voucher belongs to another shop'; end if;
  select username, display_name, avatar_url into v_username, v_display, v_avatar from public.profiles where id = c.user_id;
  return json_build_object(
    'claim_id', c.id, 'status', case when c.status = 'active' and c.expires_at < now() then 'expired' else c.status end,
    'expires_at', c.expires_at, 'redeemed_at', c.redeemed_at,
    'voucher_id', v.id, 'title', v.title, 'discount_kind', v.discount_kind, 'discount_value', v.discount_value,
    'min_spend', v.min_spend, 'terms', v.terms,
    'username', v_username, 'display_name', v_display, 'avatar_url', v_avatar, 'user_id', c.user_id,
    'commission_rate', coalesce((select commission_rate from public.vendors where id = v_vendor), public.setting_num('commission_rate', 0.01))
  );
end;
$$;

-- Lucky draw · stage screen (winners carry user_id).
create or replace function public.draw_stage(p_draw uuid)
returns jsonb
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
                     'user_id', w.user_id,
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

-- Lucky draw · crew hands over a prize (the result carries user_id).
create or replace function public.claim_prize(p_claim_code text)
returns jsonb
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
                              'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url, 'user_id', w.user_id, 'rank', w.rank);
  end if;
  if w.status = 'claimed' then
    return jsonb_build_object('ok', false, 'message', 'Already handed over.', 'prize', v_prize,
                              'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url, 'user_id', w.user_id, 'rank', w.rank);
  end if;
  if w.status in ('expired', 'forfeited') or (w.expires_at is not null and w.expires_at < now()) then
    if w.status = 'pending' then perform public.lucky_draw_expire(); end if;
    return jsonb_build_object('ok', false, 'message', 'The claim window closed. The prize passed to the next in line.', 'prize', v_prize,
                              'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url, 'user_id', w.user_id, 'rank', w.rank);
  end if;

  update public.lucky_draw_winners set status = 'claimed', claimed_at = now(), claimed_by = auth.uid() where id = w.id;
  insert into public.lucky_draw_audit (draw_id, action, actor_id, detail)
  values (w.draw_id, 'claimed', auth.uid(), jsonb_build_object('winner', w.id, 'rank', w.rank, 'prize', v_prize));
  perform public.lucky_draw_notify(array[w.user_id], d.event_id, 'Prize handed over: ' || v_prize || '. Enjoy!');
  return jsonb_build_object('ok', true, 'message', 'Hand over the prize.', 'prize', v_prize,
                            'display_name', coalesce(pr.display_name, pr.username::text), 'username', pr.username::text, 'avatar_url', pr.avatar_url, 'user_id', w.user_id, 'rank', w.rank);
end;
$$;
