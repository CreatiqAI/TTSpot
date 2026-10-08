-- Dry-run test for 20261009000130_wallet_pin.sql. Run with the migration, in
-- one transaction that rolls back: q.py --tx <migration> <this file>.
create temp table _o (n serial, line text);
do $$
declare
  a uuid; b uuid; ca uuid; cb uuid; vch uuid; vd uuid; tr uuid; sid uuid := gen_random_uuid();
  r json;
begin
  -- two friends who both hold a card
  select x.u1, x.u2 into a, b from (
    select f1.user_id u1, f2.user_id u2
    from (select distinct user_id from user_cards where status = 'held') f1
    cross join (select distinct user_id from user_cards where status = 'held') f2
    where f1.user_id <> f2.user_id and public.is_friend(f1.user_id, f2.user_id)
    limit 1) x;
  select id into ca from user_cards where user_id = a and status = 'held' limit 1;
  select id into cb from user_cards where user_id = b and status = 'held' limit 1;
  insert into _o (line) values ('a=' || a || ' b=' || b);
  -- clear any trades that touch these cards so propose/accept is clean
  update card_trades set status = 'cancelled' where status = 'proposed' and id in (select trade_id from card_trade_items where user_card_id in (ca, cb));
  update profiles set points = 1000 where id in (a, b);
  update profile_private set pin_hash = null where user_id in (a, b);
  -- a points voucher from someone else's vendor
  insert into vendors (owner_id, name) select id, 'Wallet PIN test shop' from profiles where id not in (a, b) limit 1 returning id into vd;
  insert into vouchers (vendor_id, title, points_cost, per_user_limit, starts_at)
  values (vd, 'Wallet PIN test', 10, 99, now() - interval '1 day') returning id into vch;

  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'session_id', sid)::text, true);

  -- status with no pin
  insert into _o (line) values ('status0 ' || public.wallet_pin_status()::text);

  -- no PIN: value actions say PIN_SETUP_REQUIRED
  begin perform public.buy_box(); insert into _o (line) values ('FAIL buy_box no pin');
  exception when others then insert into _o (line) values ('ok buy_box no pin: ' || sqlerrm); end;
  begin perform public.propose_trade(b, array[ca], array[cb]); insert into _o (line) values ('FAIL trade no pin');
  exception when others then insert into _o (line) values ('ok trade no pin: ' || sqlerrm); end;
  begin perform public.claim_voucher(vch); insert into _o (line) values ('FAIL voucher no pin');
  exception when others then insert into _o (line) values ('ok voucher no pin: ' || sqlerrm); end;

  -- trivial / bad PINs rejected
  begin perform public.set_wallet_pin('123456'); insert into _o (line) values ('FAIL 123456');
  exception when others then insert into _o (line) values ('ok 123456: ' || sqlerrm); end;
  begin perform public.set_wallet_pin('000000'); insert into _o (line) values ('FAIL 000000');
  exception when others then insert into _o (line) values ('ok 000000: ' || sqlerrm); end;
  begin perform public.set_wallet_pin('654321'); insert into _o (line) values ('FAIL 654321');
  exception when others then insert into _o (line) values ('ok 654321: ' || sqlerrm); end;
  begin perform public.set_wallet_pin('121212'); insert into _o (line) values ('FAIL 121212');
  exception when others then insert into _o (line) values ('ok 121212: ' || sqlerrm); end;
  begin perform public.set_wallet_pin('12345'); insert into _o (line) values ('FAIL 5 digits');
  exception when others then insert into _o (line) values ('ok 5 digits: ' || sqlerrm); end;
  begin perform public.set_wallet_pin('12a456'); insert into _o (line) values ('FAIL letters');
  exception when others then insert into _o (line) values ('ok letters: ' || sqlerrm); end;

  -- set a good one (unlocks for 5 min)
  insert into _o (line) values ('set ' || public.set_wallet_pin('482915')::text);
  insert into _o (line) values ('hash looks bcrypt: ' || (select left(pin_hash, 4) from profile_private where user_id = a));
  insert into _o (line) values ('status1 ' || public.wallet_pin_status()::text);

  -- changing needs the old one
  insert into _o (line) values ('change no old ' || public.set_wallet_pin('739164')::text);
  insert into _o (line) values ('change wrong old ' || public.set_wallet_pin('739164', '111112')::text);
  insert into _o (line) values ('change right old ' || public.set_wallet_pin('739164', '482915')::text);

  -- unlocked: actions work
  update profile_private set pin_unlocked_until = now() + interval '5 minutes' where user_id = a;
  tr := public.propose_trade(b, array[ca], array[cb]);
  insert into _o (line) values ('ok trade unlocked: ' || tr);
  r := public.claim_voucher(vch);
  insert into _o (line) values ('ok voucher unlocked: ' || r::text);

  -- locked: PIN_REQUIRED
  update profile_private set pin_unlocked_until = now() - interval '1 second' where user_id = a;
  begin perform public.claim_voucher(vch); insert into _o (line) values ('FAIL voucher locked');
  exception when others then insert into _o (line) values ('ok voucher locked: ' || sqlerrm); end;
  begin perform public.buy_box(); insert into _o (line) values ('FAIL box locked');
  exception when others then insert into _o (line) values ('ok box locked: ' || sqlerrm); end;
  begin perform public.claim_card_reward(gen_random_uuid()); insert into _o (line) values ('FAIL card prize locked');
  exception when others then insert into _o (line) values ('ok card prize locked: ' || sqlerrm); end;

  -- wrong PIN x5 locks
  for i in 1..5 loop
    insert into _o (line) values ('wrong ' || i || ' ' || public.verify_wallet_pin('000001')::text);
  end loop;
  insert into _o (line) values ('right while locked ' || public.verify_wallet_pin('739164')::text);
  insert into _o (line) values ('status locked ' || public.wallet_pin_status()::text);

  -- lock expires, right PIN unlocks
  update profile_private set pin_locked_until = now() - interval '1 second' where user_id = a;
  insert into _o (line) values ('verify ' || public.verify_wallet_pin('739164')::text);
  r := public.claim_voucher(vch);
  insert into _o (line) values ('ok voucher after verify: ' || (r->>'points_spent'));
  insert into _o (line) values ('failed counter after ok: ' || (select pin_failed from profile_private where user_id = a));

  -- b: accept with no PIN -> setup required; decline is never guarded
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  begin perform public.decide_trade(tr, true); insert into _o (line) values ('FAIL accept no pin');
  exception when others then insert into _o (line) values ('ok accept no pin: ' || sqlerrm); end;
  insert into _o (line) values ('set b ' || public.set_wallet_pin('583920')::text);
  perform public.decide_trade(tr, true);
  insert into _o (line) values ('ok accept unlocked: ' || (select status from card_trades where id = tr) || ' card a->' || ((select user_id from user_cards where id = ca) = b));

  -- reset: stale sign-in is refused, fresh one works
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'session_id', sid)::text, true);
  update auth.users set last_sign_in_at = now() - interval '10 minutes' where id = a;
  begin perform public.reset_wallet_pin('927461'); insert into _o (line) values ('FAIL reset stale');
  exception when others then insert into _o (line) values ('ok reset stale: ' || sqlerrm); end;
  update auth.users set last_sign_in_at = now() where id = a;
  -- fresh sign-in but an old session (stolen token): refused
  insert into auth.sessions (id, user_id, created_at, updated_at) values (sid, a, now() - interval '1 hour', now());
  begin perform public.reset_wallet_pin('927461'); insert into _o (line) values ('FAIL reset old session');
  exception when others then insert into _o (line) values ('ok reset old session: ' || sqlerrm); end;
  update auth.sessions set created_at = now() where id = sid;
  insert into _o (line) values ('reset fresh ' || public.reset_wallet_pin('927461')::text);
  insert into _o (line) values ('verify new ' || (public.verify_wallet_pin('927461')->>'ok'));

  -- client privileges: pin_hash unreadable
  insert into _o (line) values ('auth can read pin_hash: ' || has_column_privilege('authenticated', 'public.profile_private', 'pin_hash', 'select'));
  insert into _o (line) values ('auth can read phone: ' || has_column_privilege('authenticated', 'public.profile_private', 'phone', 'select'));
  insert into _o (line) values ('auth can update pin_unlocked_until: ' || has_column_privilege('authenticated', 'public.profile_private', 'pin_unlocked_until', 'update'));
  insert into _o (line) values ('anon exec verify: ' || has_function_privilege('anon', 'public.verify_wallet_pin(text)', 'execute'));
end $$;
select json_agg(line order by n) from _o;
