-- One car per member is the default: it fronts the profile, draws on the
-- map, and is the car they "go with" to a meet unless they switch.
-- portrait_url is the AI portrait (Kie), filled in by a later phase.
alter table public.cars add column if not exists is_default boolean not null default false;
alter table public.cars add column if not exists portrait_url text;
create unique index if not exists cars_one_default_per_owner on public.cars (owner_id) where is_default;

-- Everyone's oldest car becomes the default.
update public.cars c set is_default = true
 where c.id = (select o.id from public.cars o where o.owner_id = c.owner_id order by o.created_at asc limit 1)
   and not exists (select 1 from public.cars d where d.owner_id = c.owner_id and d.is_default);

create or replace function public.set_default_car(p_car uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Sign in first'; end if;
  if not exists (select 1 from public.cars where id = p_car and owner_id = me) then raise exception 'That car is not in your garage'; end if;
  update public.cars set is_default = false where owner_id = me and is_default;
  update public.cars set is_default = true where id = p_car;
end;
$$;

-- A new car becomes the default when it is the only one; deleting the default
-- hands it to the next oldest.
create or replace function public.on_car_default_upkeep() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.cars where owner_id = new.owner_id and is_default and id <> new.id) then
      update public.cars set is_default = true where id = new.id;
    end if;
    return new;
  end if;
  if tg_op = 'DELETE' and old.is_default then
    update public.cars set is_default = true
     where id = (select id from public.cars where owner_id = old.owner_id and id <> old.id order by created_at asc limit 1);
  end if;
  return old;
end;
$$;
drop trigger if exists cars_default_upkeep_insert on public.cars;
create trigger cars_default_upkeep_insert after insert on public.cars for each row execute function public.on_car_default_upkeep();
drop trigger if exists cars_default_upkeep_delete on public.cars;
create trigger cars_default_upkeep_delete after delete on public.cars for each row execute function public.on_car_default_upkeep();
