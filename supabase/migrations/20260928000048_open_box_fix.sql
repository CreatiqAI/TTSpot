-- open_box: roll once into a variable. `where id = roll_card()` re-rolled per
-- row (volatile function in WHERE), so the lookup could miss every row and
-- the insert failed on a null card_id.
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
  v_roll := public.roll_card();
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
