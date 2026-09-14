-- =============================================================================
-- Moment albums: a member groups their moments (live or kept) into named
-- albums shown as circles on their profile, like highlights. A moment inside
-- an album never disappears from the album, even after its 24 hours.
-- =============================================================================
create table public.moment_albums (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 30),
  cover_url   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index moment_albums_owner_idx on public.moment_albums (owner_id, created_at desc);

create table public.moment_album_items (
  album_id    uuid not null references public.moment_albums (id) on delete cascade,
  story_id    uuid not null references public.stories (id) on delete cascade,
  sort        int not null default 0,
  primary key (album_id, story_id)
);
create index moment_album_items_story_idx on public.moment_album_items (story_id);

alter table public.moment_albums enable row level security;
alter table public.moment_album_items enable row level security;

create policy "albums: read" on public.moment_albums for select to authenticated using (true);
create policy "albums: insert own" on public.moment_albums for insert to authenticated with check (owner_id = auth.uid());
create policy "albums: update own" on public.moment_albums for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "albums: delete own" on public.moment_albums for delete to authenticated using (owner_id = auth.uid());

create policy "album items: read" on public.moment_album_items for select to authenticated using (true);
create policy "album items: write own" on public.moment_album_items for insert to authenticated
  with check (exists (select 1 from public.moment_albums a where a.id = album_id and a.owner_id = auth.uid())
          and exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid()));
create policy "album items: delete own" on public.moment_album_items for delete to authenticated
  using (exists (select 1 from public.moment_albums a where a.id = album_id and a.owner_id = auth.uid()));

-- Moments in an album stay readable after they expire.
create or replace function public.is_in_album(p_story uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.moment_album_items where story_id = p_story);
$$;

drop policy "stories: read" on public.stories;
create policy "stories: read" on public.stories for select to authenticated
  using (expires_at > now() or event_id is not null or place_id is not null or author_id = auth.uid() or public.is_in_album(id));

-- Albums with how many moments they hold (for the profile row).
create or replace view public.moment_albums_with_counts
with (security_invoker = true) as
  select a.*, (select count(*) from public.moment_album_items i where i.album_id = a.id)::int as item_count
  from public.moment_albums a;
