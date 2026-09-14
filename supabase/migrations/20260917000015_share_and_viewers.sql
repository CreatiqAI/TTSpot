-- =============================================================================
-- Sharing to chat + moment viewers.
-- * A message can carry a post or a moment (rendered as a preview card).
-- * The author of a moment can see who viewed it.
-- =============================================================================
alter table public.messages
  add column post_id  uuid references public.posts (id) on delete set null,
  add column story_id uuid references public.stories (id) on delete set null;

drop policy "story_views: read own" on public.story_views;
create policy "story_views: read own or my moment" on public.story_views for select to authenticated
  using (viewer_id = auth.uid() or exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid()));

-- Who viewed my moment, newest first (the author only).
create or replace function public.story_viewers(p_story uuid)
returns table (id uuid, username text, display_name text, bio text, avatar_url text, home_state text, created_at timestamptz, viewed_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.username::text, p.display_name, p.bio, p.avatar_url, p.home_state, p.created_at, v.viewed_at
  from public.story_views v join public.profiles p on p.id = v.viewer_id
  where v.story_id = p_story
    and exists (select 1 from public.stories s where s.id = p_story and s.author_id = auth.uid())
    and v.viewer_id <> auth.uid()
  order by v.viewed_at desc;
$$;
