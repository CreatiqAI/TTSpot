-- =============================================================================
-- Expo mode, track B: exhibitors and partner booths (docs/expo-mode-plan.md
-- items 7 and 8). Tables live in 0118; this file adds the RPCs.
--
--   expo_booth_codes(jsonb)          booth codes from ["A019","A024"] or "A019, A024"
--   import_event_exhibitors(...)     host: paste-a-list import (merge by name)
--   link_event_booth_pins(event)     host: booth pins -> exhibitor by booth code
--   event_exhibitors_list(event)     everyone: exhibitors + partner logo/name + pin count
-- =============================================================================

-- Booth codes from a JSON array or a string. Splits on , ; / | & and spaces,
-- trims, upper-cases, drops blanks and repeats (first order kept). Max 40.
create or replace function public.expo_booth_codes(p jsonb)
returns text[] language sql immutable set search_path = public as $$
  with parts as (
    select e as s, o
    from jsonb_array_elements_text(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) with ordinality as a(e, o)
    union all
    select p #>> '{}', 1 where jsonb_typeof(p) in ('string', 'number')
  ), codes as (
    select upper(btrim(c)) as code, min(parts.o * 1000 + t.n) as pos
    from parts, regexp_split_to_table(parts.s, '[,;/|&[:space:]]+') with ordinality as t(c, n)
    where btrim(c) <> ''
    group by 1
  )
  select coalesce((select array_agg(left(code, 20) order by pos) from (select * from codes order by pos limit 40) c), '{}'::text[]);
$$;

-- Host: import exhibitors. Each row: {name (or company), booths (array or
-- "A019, A024"), category, country, phone, email, website, about}.
-- Same name (case-insensitive) = same exhibitor: booths are merged and blank
-- fields filled, both inside the paste and against what is already there.
-- p_replace deletes the event's exhibitors first. Then links booth pins.
-- Returns how many exhibitors were added or updated.
create or replace function public.import_event_exhibitors(p_event uuid, p_rows jsonb, p_replace boolean default false)
returns int language plpgsql security definer set search_path = public as $$
declare
  r        jsonb;
  v_name   text;
  v_booths text[];
  v_id     uuid;
  v_ids    uuid[] := '{}';
begin
  if auth.uid() is null or not public.is_meet_host(p_event) then
    raise exception 'Only the host can import exhibitors' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Rows must be a list';
  end if;
  if jsonb_array_length(p_rows) > 2000 then
    raise exception 'Too many rows (2,000 max)';
  end if;

  if p_replace then
    delete from public.event_exhibitors where event_id = p_event;
  end if;

  for r in select e from jsonb_array_elements(p_rows) as a(e) where jsonb_typeof(e) = 'object' loop
    v_name := left(regexp_replace(btrim(coalesce(nullif(btrim(r->>'name'), ''), r->>'company', '')), '\s+', ' ', 'g'), 120);
    continue when v_name = '';
    v_booths := public.expo_booth_codes(coalesce(r->'booths', r->'booth', '[]'::jsonb));

    select x.id into v_id from public.event_exhibitors x
     where x.event_id = p_event and lower(x.name) = lower(v_name)
     order by x.created_at limit 1;

    if v_id is null then
      insert into public.event_exhibitors (event_id, name, booths, category, country, phone, email, website, about)
      values (
        p_event, v_name, v_booths,
        left(nullif(btrim(r->>'category'), ''), 60),
        left(nullif(btrim(r->>'country'), ''), 40),
        left(nullif(btrim(r->>'phone'), ''), 60),
        left(nullif(btrim(r->>'email'), ''), 120),
        left(nullif(btrim(r->>'website'), ''), 200),
        left(nullif(btrim(r->>'about'), ''), 1000)
      )
      returning id into v_id;
    else
      update public.event_exhibitors x set
        booths   = (select coalesce(array_agg(b order by o), '{}') from (
                      select b, min(o) as o from unnest(x.booths || v_booths) with ordinality as u(b, o) group by b
                    ) d),
        category = coalesce(x.category, left(nullif(btrim(r->>'category'), ''), 60)),
        country  = coalesce(x.country,  left(nullif(btrim(r->>'country'), ''), 40)),
        phone    = coalesce(x.phone,    left(nullif(btrim(r->>'phone'), ''), 60)),
        email    = coalesce(x.email,    left(nullif(btrim(r->>'email'), ''), 120)),
        website  = coalesce(x.website,  left(nullif(btrim(r->>'website'), ''), 200)),
        about    = coalesce(x.about,    left(nullif(btrim(r->>'about'), ''), 1000))
      where x.id = v_id;
    end if;
    if not v_id = any (v_ids) then v_ids := v_ids || v_id; end if;
    v_id := null;
  end loop;

  perform public.link_event_booth_pins(p_event);
  return coalesce(array_length(v_ids, 1), 0);
end;
$$;

-- Host: point every booth pin on the event's levels at the exhibitor whose
-- booth codes hold the pin's label (case-insensitive, trimmed). A partner
-- wins a shared booth, then the first added. Labelled pins that match nothing
-- are unlinked; pins without a label keep a link set by hand.
-- Returns how many booth pins are linked afterwards.
create or replace function public.link_event_booth_pins(p_event uuid)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if auth.uid() is null or not public.is_meet_host(p_event) then
    raise exception 'Only the host can link booths' using errcode = '42501';
  end if;

  with pins as (
    select p.id, upper(btrim(p.label)) as code, p.exhibitor_id
    from public.event_floor_pins p
    join public.event_floor_levels l on l.id = p.level_id
    where l.event_id = p_event and p.kind = 'booth' and btrim(p.label) <> ''
  ), m as (
    select pins.id, pins.exhibitor_id as old_ex,
      (select x.id from public.event_exhibitors x
        where x.event_id = p_event
          and exists (select 1 from unnest(x.booths) b where upper(btrim(b)) = pins.code)
        order by (x.partner_vendor_id is null), x.sort, x.created_at, x.id
        limit 1) as ex
    from pins
  )
  update public.event_floor_pins p set exhibitor_id = m.ex
  from m where p.id = m.id and m.old_ex is distinct from m.ex;

  select count(*) into v_n
  from public.event_floor_pins p
  join public.event_floor_levels l on l.id = p.level_id
  where l.event_id = p_event and p.kind = 'booth' and p.exhibitor_id is not null;
  return v_n;
end;
$$;

-- Everyone: the event's exhibitors, partners first, with the linked partner's
-- logo and name (active partners only) and how many booth pins point at them.
create or replace function public.event_exhibitors_list(p_event uuid)
returns table (
  id uuid, event_id uuid, name text, booths text[], category text, country text, about text,
  phone text, email text, website text, address text, logo_url text, partner_vendor_id uuid,
  stamp_stop boolean, freebie text, freebie_limit int, sort int, created_at timestamptz,
  partner_logo text, partner_name text, pin_count int
)
language sql stable security definer set search_path = public as $$
  select x.id, x.event_id, x.name, x.booths, x.category, x.country, x.about,
         x.phone, x.email, x.website, x.address, x.logo_url,
         case when v.id is null then null else x.partner_vendor_id end,
         x.stamp_stop, x.freebie, x.freebie_limit, x.sort, x.created_at,
         v.logo_url, v.name,
         (select count(*)::int from public.event_floor_pins p
            join public.event_floor_levels l on l.id = p.level_id
           where l.event_id = x.event_id and p.exhibitor_id = x.id)
  from public.event_exhibitors x
  left join public.vendors v on v.id = x.partner_vendor_id and v.active
  where x.event_id = p_event and auth.uid() is not null
  order by (v.id is null), x.sort, lower(x.name);
$$;

revoke execute on function public.expo_booth_codes(jsonb) from public, anon;
revoke execute on function public.import_event_exhibitors(uuid, jsonb, boolean) from public, anon;
revoke execute on function public.link_event_booth_pins(uuid) from public, anon;
revoke execute on function public.event_exhibitors_list(uuid) from public, anon;
grant execute on function public.expo_booth_codes(jsonb) to authenticated;
grant execute on function public.import_event_exhibitors(uuid, jsonb, boolean) to authenticated;
grant execute on function public.link_event_booth_pins(uuid) to authenticated;
grant execute on function public.event_exhibitors_list(uuid) to authenticated;
