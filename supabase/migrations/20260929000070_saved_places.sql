-- =============================================================================
-- Saved spots + nearest spots.
--
--   place_saves(user_id, place_id, created_at)
--     A member's bookmarked places. Members read, add and remove their own rows only.
--   toggle_place_save(p_place uuid) returns boolean
--     Saves the place for me, or unsaves it if already saved. true = now saved.
--   my_saved_places() returns setof places_with_counts
--     My saved places, newest save first, wherever they are.
--   nearest_spots(p_lat float8, p_lng float8, p_limit int default 5) returns setof places_with_counts
--     The spots (is_spot) closest to a point, nearest first (public.metres_between).
-- =============================================================================

create table if not exists public.place_saves (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  place_id   uuid not null references public.places (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, place_id)
);
create index if not exists place_saves_user_idx on public.place_saves (user_id, created_at desc);

alter table public.place_saves enable row level security;

drop policy if exists "place_saves: read own" on public.place_saves;
drop policy if exists "place_saves: insert own" on public.place_saves;
drop policy if exists "place_saves: delete own" on public.place_saves;
create policy "place_saves: read own" on public.place_saves for select to authenticated using (user_id = auth.uid());
create policy "place_saves: insert own" on public.place_saves for insert to authenticated with check (user_id = auth.uid());
create policy "place_saves: delete own" on public.place_saves for delete to authenticated using (user_id = auth.uid());

-- ------------------------------------------------------------------ toggle ---

create or replace function public.toggle_place_save(p_place uuid) returns boolean
language plpgsql security invoker set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Sign in to save spots';
  end if;
  delete from public.place_saves where user_id = v_me and place_id = p_place;
  if found then
    return false;
  end if;
  insert into public.place_saves (user_id, place_id) values (v_me, p_place)
  on conflict do nothing;
  return true;
end;
$$;

-- ------------------------------------------------------------ my saved ---

create or replace function public.my_saved_places() returns setof public.places_with_counts
language sql stable security invoker set search_path = public as $$
  select v.*
  from public.place_saves s
  join public.places_with_counts v on v.id = s.place_id
  where s.user_id = auth.uid()
  order by s.created_at desc
  limit 200;
$$;

-- ----------------------------------------------------------- nearest spots ---

create or replace function public.nearest_spots(p_lat float8, p_lng float8, p_limit int default 5) returns setof public.places_with_counts
language sql stable security invoker set search_path = public as $$
  select v.*
  from public.places_with_counts v
  where v.is_spot
  order by public.metres_between(p_lat, p_lng, v.lat, v.lng)
  limit greatest(1, least(coalesce(p_limit, 5), 50));
$$;

revoke all on function public.toggle_place_save(uuid) from public, anon;
revoke all on function public.my_saved_places() from public, anon;
revoke all on function public.nearest_spots(float8, float8, int) from public, anon;
grant execute on function public.toggle_place_save(uuid) to authenticated;
grant execute on function public.my_saved_places() to authenticated;
grant execute on function public.nearest_spots(float8, float8, int) to authenticated;
