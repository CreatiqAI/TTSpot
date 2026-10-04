-- =============================================================================
-- 0103 · Automatic photo check on new posts and moments, and +50 points for a
-- member's first post (the "Share your ride" nudge on Home and the profile).
--
-- Moderation (Apple 1.2: apps with user content must filter objectionable
-- material, not only offer report / block):
--   * posts.moderation and stories.moderation: 'pending' | 'ok' | 'flagged' |
--     'removed'. New rows start 'pending'; rows from before this migration are
--     'ok'. moderation_reason (short, for admins), moderation_categories
--     (the scores), moderated_at (when the state last changed).
--   * AFTER INSERT → moderation_enqueue() → pg_net → Edge Function
--     moderate-content, which asks OpenAI's free omni-moderation-latest about
--     the photos (grid thumbnails where they exist), the video still and the
--     text, and answers through moderation_apply(). Thresholds: decide.ts.
--   * Who sees what (RLS): 'ok' is for everyone; 'pending', 'flagged' and
--     'removed' only for the author and admins. The check answers in a few
--     seconds (measured live 2026-10-05: 1.8 to 3.4 s from insert to verdict,
--     ~2 s of it OpenAI), so a new post reaches others already checked
--     instead of being shown and pulled back. The author sees it at once.
--     Security-definer feeds return ids and the app fetches the rows under
--     RLS, so hidden ones drop out of every list.
--   * Fails OPEN: no answer within 3 minutes (function down, pg_net lost the
--     call) → 'ok' with reason 'Not checked: …' and a log line; the one-minute
--     sweep asks again after 45 s first. A missing Vault secret → 'ok' at once.
--     A broken checker must never make every new post vanish; reports and
--     block stay as the second line.
--   * Members can't set their own verdict: a BEFORE trigger forces 'pending'
--     on insert and keeps the moderation columns on update; an edited 'ok'
--     post goes back to 'pending' and is checked again.
--   * Admin · Queues → "Flagged posts and moments": Approve (→ 'ok') or
--     Remove (→ 'removed', still hidden, kept for the record).
--
-- The hook reads two Vault secrets, created once outside this repo:
--   select vault.create_secret('<random>', 'moderation_hook_secret');
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/moderate-content', 'moderation_hook_url');
-- and the function gets the same value as MODERATION_HOOK_SECRET.
--
-- First post: point_rules 'first_post' = 50, awarded once per member (ledger
-- key 'first_post:<user>') when their first personal post is 'ok', with the
-- usual 'points' notification. Flagged or removed posts earn nothing.
-- =============================================================================

create extension if not exists pg_net;

-- --------------------------------------------------------------- columns ---
-- Added with default 'ok' so every existing row is 'ok', then the default
-- becomes 'pending' for new rows.
alter table public.posts add column if not exists moderation text not null default 'ok';
alter table public.posts alter column moderation set default 'pending';
alter table public.posts add column if not exists moderation_reason text;
alter table public.posts add column if not exists moderation_categories jsonb;
alter table public.posts add column if not exists moderated_at timestamptz;
alter table public.posts drop constraint if exists posts_moderation_check;
alter table public.posts add constraint posts_moderation_check check (moderation in ('pending', 'ok', 'flagged', 'removed'));

alter table public.stories add column if not exists moderation text not null default 'ok';
alter table public.stories alter column moderation set default 'pending';
alter table public.stories add column if not exists moderation_reason text;
alter table public.stories add column if not exists moderation_categories jsonb;
alter table public.stories add column if not exists moderated_at timestamptz;
alter table public.stories drop constraint if exists stories_moderation_check;
alter table public.stories add constraint stories_moderation_check check (moderation in ('pending', 'ok', 'flagged', 'removed'));

-- The sweep and the admin queue only look at these.
create index if not exists posts_moderation_open_idx on public.posts (moderated_at) where moderation in ('pending', 'flagged');
create index if not exists stories_moderation_open_idx on public.stories (moderated_at) where moderation in ('pending', 'flagged');

-- ---------------------------------------------------------------- guards ---
-- Security invoker on purpose: current_user is the caller ('authenticated'
-- from the app), while security-definer RPCs and the Edge Function's service
-- role may set a verdict.
create or replace function public.posts_moderation_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if current_user in ('authenticated', 'anon') or new.moderation is null then
      new.moderation := 'pending';
      new.moderation_reason := null;
      new.moderation_categories := null;
    end if;
    new.moderated_at := now();
    return new;
  end if;
  if current_user in ('authenticated', 'anon') then
    new.moderation := old.moderation;
    new.moderation_reason := old.moderation_reason;
    new.moderation_categories := old.moderation_categories;
    new.moderated_at := old.moderated_at;
    -- An edited post is checked again; a flagged or removed one waits for the admin.
    if old.moderation = 'ok' and (
         new.photo_urls is distinct from old.photo_urls
         or new.video_poster_url is distinct from old.video_poster_url
         or new.title is distinct from old.title
         or new.caption is distinct from old.caption
         or new.poll_options is distinct from old.poll_options
       ) then
      new.moderation := 'pending';
      new.moderated_at := now();
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.stories_moderation_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if current_user in ('authenticated', 'anon') or new.moderation is null then
      new.moderation := 'pending';
      new.moderation_reason := null;
      new.moderation_categories := null;
    end if;
    new.moderated_at := now();
    return new;
  end if;
  if current_user in ('authenticated', 'anon') then
    new.moderation := old.moderation;
    new.moderation_reason := old.moderation_reason;
    new.moderation_categories := old.moderation_categories;
    new.moderated_at := old.moderated_at;
  end if;
  return new;
end;
$$;

drop trigger if exists posts_moderation_guard on public.posts;
create trigger posts_moderation_guard before insert or update on public.posts
  for each row execute function public.posts_moderation_guard();
drop trigger if exists stories_moderation_guard on public.stories;
create trigger stories_moderation_guard before insert or update on public.stories
  for each row execute function public.stories_moderation_guard();

-- ---------------------------------------------------------------- verdict ---
-- The one place a verdict lands (Edge Function, sweep, admins). With
-- p_only_pending (the checker) it never overrides a decision already made.
-- A hidden photo stops being a spot's cover, and nobody else keeps an
-- Activity row pointing at the post. Returns the verdict, or null when the
-- row is gone or already decided.
create or replace function public.moderation_apply(
  p_table text, p_id uuid, p_verdict text,
  p_reason text default null, p_categories jsonb default null, p_only_pending boolean default true
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_author uuid;
  v_place uuid;
  v_photos text[];
begin
  if p_verdict not in ('ok', 'flagged', 'removed') then raise exception 'Unknown verdict %', p_verdict; end if;
  if p_table = 'posts' then
    update public.posts
       set moderation = p_verdict, moderation_reason = p_reason,
           moderation_categories = coalesce(p_categories, moderation_categories), moderated_at = now()
     where id = p_id and (not p_only_pending or moderation = 'pending')
    returning author_id, place_id, photo_urls || array_remove(array[video_poster_url], null)
      into v_author, v_place, v_photos;
  elsif p_table = 'stories' then
    update public.stories
       set moderation = p_verdict, moderation_reason = p_reason,
           moderation_categories = coalesce(p_categories, moderation_categories), moderated_at = now()
     where id = p_id and (not p_only_pending or moderation = 'pending')
    returning author_id, place_id, array[photo_url]
      into v_author, v_place, v_photos;
  else
    raise exception 'Unknown table %', p_table;
  end if;
  if not found then return null; end if;
  if p_verdict <> 'ok' then
    if v_place is not null then
      update public.places set cover_url = null where id = v_place and cover_url = any (v_photos);
    end if;
    if p_table = 'posts' then
      delete from public.notifications where post_id = p_id and user_id <> v_author;
    end if;
  end if;
  return p_verdict;
end;
$$;

-- --------------------------------------------------------------- the hook ---
create or replace function public.moderation_enqueue(p_table text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
  v_url text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'moderation_hook_secret';
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'moderation_hook_url';
  if v_secret is null or v_url is null then
    -- Not set up: fail open now rather than hide everything for 3 minutes.
    perform public.moderation_apply(p_table, p_id, 'ok', 'Not checked: the photo check is not set up');
    return;
  end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('table', p_table, 'id', p_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-moderation-secret', v_secret),
    timeout_milliseconds := 30000
  );
exception when others then
  -- Never block a post; the sweep asks again and then fails open.
  raise warning 'moderation_enqueue % %: %', p_table, p_id, sqlerrm;
end;
$$;

create or replace function public.on_moderation_queue() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.moderation_enqueue(tg_table_name, new.id);
  return null;
end;
$$;

drop trigger if exists posts_moderation_queue on public.posts;
create trigger posts_moderation_queue after insert on public.posts
  for each row when (new.moderation = 'pending') execute function public.on_moderation_queue();
-- An edited post that went back to 'pending' (no column list: the guard
-- changes moderation, which isn't in the member's SET list).
drop trigger if exists posts_moderation_requeue on public.posts;
create trigger posts_moderation_requeue after update on public.posts
  for each row when (new.moderation = 'pending' and old.moderation is distinct from 'pending')
  execute function public.on_moderation_queue();
drop trigger if exists stories_moderation_queue on public.stories;
create trigger stories_moderation_queue after insert on public.stories
  for each row when (new.moderation = 'pending') execute function public.on_moderation_queue();

-- ----------------------------------------------------------------- sweep ---
-- Every minute: pending for 45 s → ask again (20 a table at most); pending
-- for 3 minutes → fail open ('ok', reason 'Not checked: …', a log line).
create or replace function public.moderation_sweep() returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select 'posts'::text as t, id from public.posts where moderation = 'pending' and moderated_at < now() - interval '3 minutes'
    union all
    select 'stories'::text, id from public.stories where moderation = 'pending' and moderated_at < now() - interval '3 minutes'
  loop
    perform public.moderation_apply(r.t, r.id, 'ok', 'Not checked: no answer from the photo check');
    raise log 'moderation_sweep: % % failed open after 3 minutes', r.t, r.id;
    n := n + 1;
  end loop;
  for r in
    (select 'posts'::text as t, id from public.posts where moderation = 'pending' and moderated_at < now() - interval '45 seconds' order by moderated_at limit 20)
    union all
    (select 'stories'::text, id from public.stories where moderation = 'pending' and moderated_at < now() - interval '45 seconds' order by moderated_at limit 20)
  loop
    perform public.moderation_enqueue(r.t, r.id);
  end loop;
  return n;
end;
$$;

select cron.schedule('ttspot-moderation-sweep', '* * * * *', $$select public.moderation_sweep()$$);

-- ------------------------------------------------------------------- RLS ---
drop policy if exists "posts: read" on public.posts;
create policy "posts: read" on public.posts for select to authenticated
  using (moderation = 'ok' or author_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "stories: read" on public.stories;
create policy "stories: read" on public.stories for select to authenticated
  using (
    ((expires_at > now()) or (event_id is not null) or (place_id is not null) or (author_id = (select auth.uid())) or public.is_in_album(id))
    and (moderation = 'ok' or author_id = (select auth.uid()) or (select public.is_admin()))
  );

-- ----------------------------------------------------------------- admins ---
create or replace function public.admin_moderation_queue(p_limit int default 100)
returns table (
  kind text, id uuid, author_id uuid, username text, display_name text, avatar_url text,
  photo_urls text[], is_video boolean, title text, caption text,
  reason text, categories jsonb, created_at timestamptz, moderated_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select q.* from (
      select 'post'::text, p.id, p.author_id, pr.username::text, pr.display_name, pr.avatar_url,
             case when cardinality(p.photo_urls) > 0 then p.photo_urls else array_remove(array[p.video_poster_url], null) end,
             p.video_url is not null, p.title, p.caption,
             p.moderation_reason, p.moderation_categories, p.created_at, p.moderated_at
        from public.posts p join public.profiles pr on pr.id = p.author_id
       where p.moderation = 'flagged'
      union all
      select 'moment'::text, s.id, s.author_id, pr.username::text, pr.display_name, pr.avatar_url,
             array[s.photo_url], s.video_url is not null, null::text, s.caption,
             s.moderation_reason, s.moderation_categories, s.created_at, s.moderated_at
        from public.stories s join public.profiles pr on pr.id = s.author_id
       where s.moderation = 'flagged'
    ) q
    order by q.moderated_at desc nulls last
    limit greatest(1, least(p_limit, 500));
end;
$$;

-- Approve (→ 'ok', shown again) or Remove (→ 'removed', stays hidden).
-- p_kind: 'post' | 'moment'. Returns the new state, or null when it's gone.
create or replace function public.admin_moderate(p_kind text, p_id uuid, p_approve boolean) returns text
language plpgsql security definer set search_path = public as $$
declare v_me text;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select username::text into v_me from public.profiles where id = auth.uid();
  return public.moderation_apply(
    case p_kind when 'post' then 'posts' when 'moment' then 'stories' else p_kind end,
    p_id,
    case when p_approve then 'ok' else 'removed' end,
    case when p_approve then 'Approved by @' else 'Removed by @' end || coalesce(v_me, 'admin'),
    null,
    false
  );
end;
$$;

-- Car of the Week only from posts everyone can see.
create or replace function public.pick_car_of_week() returns void
language plpgsql security definer set search_path = public as $$
declare
  ws date := (date_trunc('week', now()) - interval '7 days')::date;
  we date := date_trunc('week', now())::date;
  w record;
begin
  if exists (select 1 from public.weekly_winners where week_start = ws) then return; end if;
  select p.id as post_id, p.car_id, p.author_id as user_id,
         (select count(*) from public.post_likes l where l.post_id = p.id)::int as like_count
    into w
  from public.posts p
  where p.kind = 'post' and p.car_id is not null and p.moderation = 'ok'
    and p.created_at >= ws and p.created_at < we
  order by like_count desc, p.created_at asc
  limit 1;
  if w.post_id is null then return; end if;
  insert into public.weekly_winners (week_start, post_id, car_id, user_id, like_count)
  values (ws, w.post_id, w.car_id, w.user_id, w.like_count);
  perform public.award_badge(w.user_id, 'car_of_week');
  insert into public.notifications (user_id, type, post_id, body)
  values (w.user_id, 'car_of_week', w.post_id, 'Your build is Car of the Week!');
end;
$$;

-- ------------------------------------------------------------- first post ---
insert into public.point_rules (reason, points, label, description, sort)
values ('first_post', 50, 'Share your first post', 'Post your ride for the first time.', 45)
on conflict (reason) do update set label = excluded.label, description = excluded.description, sort = excluded.sort;

-- When a member's first personal post (not as a club or partner) is 'ok'.
-- An older visible post means this isn't their first (members who posted
-- before this rule get nothing new); the ledger key makes it once ever.
create or replace function public.on_post_first_points() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pts int := public.rule_points('first_post');
begin
  if v_pts <= 0 or new.as_club or new.as_vendor then return null; end if;
  if exists (
    select 1 from public.posts p
     where p.author_id = new.author_id and p.id <> new.id
       and not p.as_club and not p.as_vendor
       and p.moderation = 'ok' and p.created_at < new.created_at
  ) then
    return null;
  end if;
  if public.award_points(new.author_id, v_pts, 'first_post', 'post', new.id::text, null, 'first_post:' || new.author_id) then
    perform public.notify(new.author_id, null, 'points', p_post => new.id, p_body => '+' || v_pts || ' · your first post');
  end if;
  return null;
end;
$$;

drop trigger if exists posts_first_post_points on public.posts;
create trigger posts_first_post_points after insert or update of moderation on public.posts
  for each row when (new.moderation = 'ok') execute function public.on_post_first_points();

-- ---------------------------------------------------------------- grants ---
revoke execute on function public.posts_moderation_guard() from public, anon, authenticated;
revoke execute on function public.stories_moderation_guard() from public, anon, authenticated;
revoke execute on function public.moderation_apply(text, uuid, text, text, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.moderation_apply(text, uuid, text, text, jsonb, boolean) to service_role;
revoke execute on function public.moderation_enqueue(text, uuid) from public, anon, authenticated;
revoke execute on function public.on_moderation_queue() from public, anon, authenticated;
revoke execute on function public.moderation_sweep() from public, anon, authenticated;
revoke execute on function public.on_post_first_points() from public, anon, authenticated;
revoke execute on function public.admin_moderation_queue(int) from public, anon;
grant execute on function public.admin_moderation_queue(int) to authenticated;
revoke execute on function public.admin_moderate(text, uuid, boolean) from public, anon;
grant execute on function public.admin_moderate(text, uuid, boolean) to authenticated;
