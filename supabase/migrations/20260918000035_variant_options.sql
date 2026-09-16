-- Variant options can carry their own price and photo:
-- [{"name": "Compound", "options": [{"label": "Street", "price": 420, "photo_url": "https://…"}, "Track"]}]
-- Plain strings are still accepted for older rows.
create or replace function public.save_product(
  p_id uuid, p_name text, p_description text, p_price numeric, p_photo_urls text[], p_variants jsonb, p_active boolean
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_vendor uuid := public.my_vendor_id();
  v_id uuid;
  v_count int;
  g jsonb;
  o jsonb;
begin
  if v_vendor is null then raise exception 'You are not an active partner'; end if;
  if p_variants is not null then
    if jsonb_typeof(p_variants) <> 'array' or jsonb_array_length(p_variants) > 3 then raise exception 'Up to 3 variant groups'; end if;
    for g in select * from jsonb_array_elements(p_variants) loop
      if coalesce(char_length(g->>'name'), 0) between 1 and 30 is not true then raise exception 'Give every variant group a short name'; end if;
      if jsonb_typeof(g->'options') <> 'array' or jsonb_array_length(g->'options') between 1 and 8 is not true then raise exception 'Each group needs 1–8 options'; end if;
      for o in select * from jsonb_array_elements(g->'options') loop
        if jsonb_typeof(o) = 'string' then
          if char_length(o #>> '{}') between 1 and 30 is not true then raise exception 'Option names are 1–30 characters'; end if;
        elsif jsonb_typeof(o) = 'object' then
          if coalesce(char_length(o->>'label'), 0) between 1 and 30 is not true then raise exception 'Option names are 1–30 characters'; end if;
          if o ? 'price' and jsonb_typeof(o->'price') not in ('null', 'number') then raise exception 'Option price must be a number'; end if;
          if jsonb_typeof(o->'price') = 'number' and (o->>'price')::numeric < 0 then raise exception 'Option price must be 0 or more'; end if;
        else
          raise exception 'Bad variant option';
        end if;
      end loop;
    end loop;
  end if;
  if p_id is null then
    select count(*) into v_count from public.vendor_products where vendor_id = v_vendor;
    if v_count >= 5 then raise exception 'Up to 5 products per shop for now'; end if;
    insert into public.vendor_products (vendor_id, name, description, price, photo_urls, variants, sort_order, active)
    values (v_vendor, trim(p_name), nullif(trim(p_description), ''), p_price, coalesce(p_photo_urls, '{}'), coalesce(p_variants, '[]'::jsonb), v_count, coalesce(p_active, true))
    returning id into v_id;
    return v_id;
  end if;
  update public.vendor_products
     set name = trim(p_name), description = nullif(trim(p_description), ''), price = p_price,
         photo_urls = coalesce(p_photo_urls, photo_urls), variants = coalesce(p_variants, variants), active = coalesce(p_active, active)
   where id = p_id and vendor_id = v_vendor;
  if not found then raise exception 'Product not found'; end if;
  return p_id;
end;
$$;
