-- Scheduled posts: the official accounts (@titi) post on a schedule.
-- A row waits here until publish_at, then publish_due_posts() (pg_cron,
-- every 5 minutes) turns it into a normal post. Official content is written
-- and checked by TT Spot, so it goes up already moderated ('ok').
create table if not exists public.scheduled_posts (
  id            uuid primary key default gen_random_uuid(),
  author_id     uuid not null references public.profiles (id) on delete cascade,
  caption       text not null check (char_length(caption) between 1 and 2200),
  photo_urls    text[] not null default '{}',
  cover_aspect  double precision not null default 0.8,
  publish_at    timestamptz not null,
  post_id       uuid references public.posts (id) on delete set null,
  posted_at     timestamptz,
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists scheduled_posts_due_idx on public.scheduled_posts (publish_at) where posted_at is null;
alter table public.scheduled_posts enable row level security;
drop policy if exists "scheduled_posts: admin" on public.scheduled_posts;
create policy "scheduled_posts: admin" on public.scheduled_posts for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create or replace function public.publish_due_posts() returns int
language plpgsql security definer set search_path = public as $$
declare
  r public.scheduled_posts;
  v_post uuid;
  n int := 0;
begin
  for r in select * from public.scheduled_posts where posted_at is null and publish_at <= now() order by publish_at for update skip locked loop
    insert into public.posts (author_id, kind, caption, photo_urls, cover_aspect, moderation, moderated_at)
    values (r.author_id, 'post', r.caption, r.photo_urls, r.cover_aspect, 'ok', now())
    returning id into v_post;
    update public.scheduled_posts set post_id = v_post, posted_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke all on function public.publish_due_posts() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'ttspot-scheduled-posts') then
    perform cron.unschedule('ttspot-scheduled-posts');
  end if;
  perform cron.schedule('ttspot-scheduled-posts', '*/5 * * * *', 'select public.publish_due_posts()');
end $$;
