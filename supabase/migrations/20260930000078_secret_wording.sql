-- The top card tier is called "Secret" everywhere people read it. The rarity
-- value stays 'legendary' in data; only the words change here: the error an
-- admin sees when the numbered run is used up, and the settings description.

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
  if v_serial is null then raise exception 'All % Secret cards are out. There are none left to give.', v_total; end if;
  new.serial := v_serial;
  return new;
end;
$$;
revoke execute on function public.mint_legendary_serial() from public, anon, authenticated;

update public.platform_settings
   set description = 'Secret cards that will ever exist, from boxes, admin grants or anything else. Once they are all out, boxes stop dropping the Secret and common / rare share its odds.'
 where key = 'legendary_stock_total';
