-- Ranked "For you" (0.3.51). Until now the Home grid was every post, newest
-- first. Now it is ranked per member, the way RedNote and Instagram do it:
--
--   score = quality x freshness x relevance x novelty x (cold start) x (jitter)
--
--   quality    how well the post does with the people who saw it: likes 1,
--              saves 2, comments 3, shares into chats 4, opens 0.5, smoothed
--              over unique viewers so a new post is not judged on 2 views
--              (RedNote's "CES" idea).
--   freshness  halves every 2 days, never below 0.12, so a great older post
--              can still come back.
--   relevance  1 + friend / follow / clubmate (Instagram's relationship
--              signal) + how much I engage with this author + the car makes,
--              spots and post kinds I like, save, comment on and open
--              (RedNote's interest tags) + my own car's make + near me.
--   novelty    seen tiles sink (x0.6 per feed session), opened ones sink
--              more, posts I liked or saved drop back, "Not interested" hides
--              the post and dampens its author and make.
--   cold start a post under a day old with under 30 viewers gets x1.5, so
--              every new post gets a first audience (RedNote's traffic pool).
--   jitter     +/-10%, seeded per refresh, so each pull feels new but pages
--              stay stable.
--   diversity  the 2nd post by the same author in a page is x0.7, the 3rd
--              x0.49, and so on.
--
-- The app logs what came on screen (log_post_views) and post page visits
-- with time spent (log_post_open). Following becomes friends + people I
-- follow + my clubs, newest first (there's no Follow button any more, so
-- that tab was always empty). Post pages get "More like this" (related_posts).

-- ------------------------------------------------------------ signals ---

-- What each member has seen and opened. Written only by the RPCs below.
create table if not exists public.post_views (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  post_id     uuid not null references public.posts (id) on delete cascade,
  seen        int not null default 0,      -- feed sessions the post came on screen
  opens       int not null default 0,      -- post page visits
  dwell_ms    bigint not null default 0,   -- time on the post page, 3 min max per visit
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index if not exists post_views_post_idx on public.post_views (post_id);

alter table public.post_views enable row level security;
drop policy if exists "post_views: read own" on public.post_views;
create policy "post_views: read own" on public.post_views for select to authenticated using (user_id = auth.uid());
revoke all on public.post_views from anon, authenticated;
grant select on public.post_views to authenticated;
grant all on public.post_views to service_role;

-- Unique viewers / openers per post, kept by the same RPCs (one row per post,
-- so ranking never has to count post_views).
create table if not exists public.post_stats (
  post_id   uuid primary key references public.posts (id) on delete cascade,
  viewers   int not null default 0,
  openers   int not null default 0,
  dwell_ms  bigint not null default 0
);
alter table public.post_stats enable row level security;
revoke all on public.post_stats from anon, authenticated;
grant all on public.post_stats to service_role;

-- "Not interested" (scope 'post') and "Fewer from this person" (scope 'author').
create table if not exists public.post_hides (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  post_id     uuid not null references public.posts (id) on delete cascade,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  scope       text not null default 'post' check (scope in ('post', 'author')),
  created_at  timestamptz not null default now(),
  primary key (user_id, post_id)
);
create index if not exists post_hides_user_author_idx on public.post_hides (user_id, author_id);

alter table public.post_hides enable row level security;
drop policy if exists "post_hides: read own" on public.post_hides;
drop policy if exists "post_hides: remove own" on public.post_hides;
create policy "post_hides: read own" on public.post_hides for select to authenticated using (user_id = auth.uid());
create policy "post_hides: remove own" on public.post_hides for delete to authenticated using (user_id = auth.uid());
revoke all on public.post_hides from anon, authenticated;
grant select, delete on public.post_hides to authenticated;
grant all on public.post_hides to service_role;

-- Lookups the ranking makes per viewer / per candidate.
create index if not exists post_comments_user_idx on public.post_comments (user_id, created_at desc);
create index if not exists messages_post_idx on public.messages (post_id) where post_id is not null;
create index if not exists cars_owner_idx on public.cars (owner_id);

-- Posts that came on screen in a feed (once per post per feed session; the
-- app de-duplicates). My own posts are not counted.
create or replace function public.log_post_views(p_ids uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or p_ids is null or cardinality(p_ids) = 0 then return; end if;
  with ids as (
    select distinct i as post_id from unnest(p_ids[1:60]) as i
  ), up as (
    insert into public.post_views as v (user_id, post_id, seen)
    select v_me, ids.post_id, 1
    from ids join public.posts p on p.id = ids.post_id and p.author_id <> v_me
    on conflict (user_id, post_id) do update set seen = v.seen + 1, last_seen = now()
    returning v.post_id, (v.xmax = 0) as fresh
  )
  insert into public.post_stats as s (post_id, viewers)
  select up.post_id, 1 from up where up.fresh
  on conflict (post_id) do update set viewers = s.viewers + 1;
end;
$$;

-- A post page visit, sent when I leave it, with the time I spent there.
create or replace function public.log_post_open(p_post uuid, p_dwell_ms int default 0) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_dwell bigint := least(greatest(coalesce(p_dwell_ms, 0), 0), 180000);
  v_fresh boolean;
  v_first_open boolean;
begin
  if v_me is null or p_post is null then return; end if;
  if not exists (select 1 from public.posts where id = p_post and author_id <> v_me) then return; end if;
  insert into public.post_views as v (user_id, post_id, seen, opens, dwell_ms)
  values (v_me, p_post, 1, 1, v_dwell)
  on conflict (user_id, post_id) do update set opens = v.opens + 1, dwell_ms = v.dwell_ms + v_dwell, last_seen = now()
  returning (v.xmax = 0), (v.opens = 1) into v_fresh, v_first_open;
  insert into public.post_stats as s (post_id, viewers, openers, dwell_ms)
  values (p_post, case when v_fresh then 1 else 0 end, case when v_first_open then 1 else 0 end, v_dwell)
  on conflict (post_id) do update set
    viewers = s.viewers + excluded.viewers,
    openers = s.openers + excluded.openers,
    dwell_ms = s.dwell_ms + excluded.dwell_ms;
end;
$$;

-- "Not interested" / "Fewer from @someone". Undo deletes the row.
create or replace function public.hide_post(p_post uuid, p_scope text default 'post') returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'Sign in first'; end if;
  if coalesce(p_scope, 'post') not in ('post', 'author') then raise exception 'Unknown choice'; end if;
  insert into public.post_hides (user_id, post_id, author_id, scope)
  select v_me, p.id, p.author_id, coalesce(p_scope, 'post')
  from public.posts p where p.id = p_post and p.author_id <> v_me
  on conflict (user_id, post_id) do update set scope = excluded.scope, created_at = now();
end;
$$;

-- -------------------------------------------------------------- feeds ---

-- The make a post is about: its tagged car, else its author's main car.
create or replace function public.post_make(p_car uuid, p_author uuid) returns text
language sql stable security definer set search_path = public as $$
  select lower(coalesce(
    (select c.make from public.cars c where c.id = p_car),
    (select c.make from public.cars c where c.owner_id = p_author order by c.is_default desc, c.created_at limit 1)
  ));
$$;

-- One page of "For you": the best p_limit posts not in p_exclude (the ids the
-- app already shows). p_seed changes on each pull-to-refresh. p_lat/p_lng is
-- where I am, when the app already knows it (it never asks just for this).
-- reason: friend | following | club | nearby | make:<make> | popular | new | mine | for_you
create or replace function public.feed_for_you(
  p_limit int default 20,
  p_exclude uuid[] default '{}',
  p_seed text default '',
  p_lat double precision default null,
  p_lng double precision default null
) returns table (post_id uuid, score double precision, reason text)
language sql stable security definer set search_path = public as $$
  with me as (
    select auth.uid() as id
  ), my as (
    select pr.home_state from public.profiles pr where pr.id = (select id from me)
  ), blocked as (
    select b.blocked_id as uid from public.blocks b where b.blocker_id = (select id from me)
    union select b.blocker_id from public.blocks b where b.blocked_id = (select id from me)
  ), friends as (
    select case when f.requester_id = (select id from me) then f.addressee_id else f.requester_id end as uid
    from public.friendships f
    where f.status = 'accepted' and (f.requester_id = (select id from me) or f.addressee_id = (select id from me))
  ), followed as (
    select fo.followee_id as uid from public.follows fo where fo.follower_id = (select id from me)
  ), my_clubs as (
    select cm.club_id from public.club_members cm where cm.user_id = (select id from me)
  ), clubmates as (
    select distinct cm.user_id as uid from public.club_members cm
    where cm.club_id in (select club_id from my_clubs) and cm.user_id <> (select id from me)
  ),
  -- What I liked, saved, commented on and opened lately: my interests.
  signals as (
    select l.post_id, 1.0::float8 as w from public.post_likes l
      where l.user_id = (select id from me) and l.created_at > now() - interval '120 days'
    union all select s.post_id, 2.0 from public.post_saves s
      where s.user_id = (select id from me) and s.created_at > now() - interval '120 days'
    union all select c.post_id, 2.0 from public.post_comments c
      where c.user_id = (select id from me) and c.created_at > now() - interval '120 days'
    union all select v.post_id, least(v.opens, 3) * 0.4 + least(v.dwell_ms, 60000) / 60000.0 from public.post_views v
      where v.user_id = (select id from me) and v.opens > 0 and v.last_seen > now() - interval '120 days'
  ), sig_posts as (
    select s.w, p.author_id, p.place_id, p.kind, public.post_make(p.car_id, p.author_id) as make
    from signals s join public.posts p on p.id = s.post_id
    where p.author_id <> (select id from me)
  ),
  author_aff as (select author_id, sum(w) as w from sig_posts group by author_id),
  make_aff   as (select make, sum(w) as w from sig_posts where make is not null group by make),
  place_aff  as (select place_id, sum(w) as w from sig_posts where place_id is not null group by place_id),
  kind_aff   as (select kind, sum(w) as w from sig_posts group by kind),
  tops as (
    select (select max(w) from make_aff) as make_max,
           (select max(w) from place_aff) as place_max,
           (select max(w) from kind_aff) as kind_max
  ),
  my_makes as (
    select distinct lower(c.make) as make from public.cars c where c.owner_id = (select id from me)
  ),
  hid_authors as (
    select h.author_id,
           count(*) filter (where h.scope = 'author') as by_author,
           count(*) filter (where h.scope = 'post') as by_post
    from public.post_hides h where h.user_id = (select id from me) group by h.author_id
  ), hid_makes as (
    select public.post_make(p.car_id, p.author_id) as make, count(*) as n
    from public.post_hides h join public.posts p on p.id = h.post_id
    where h.user_id = (select id from me) group by 1
  ),
  -- The newest 600 posts I may see and the app isn't already showing.
  cand as (
    select p.id, p.author_id, p.kind, p.created_at, p.place_id, p.club_id,
           public.post_make(p.car_id, p.author_id) as make,
           coalesce(p.lat, pl.lat) as plat, coalesce(p.lng, pl.lng) as plng
    from public.posts p
    left join public.places pl on pl.id = p.place_id
    join public.profiles a on a.id = p.author_id and a.suspended_at is null
    where not (p.id = any (coalesce(p_exclude, '{}'::uuid[])))
      and p.author_id not in (select uid from blocked)
      and not exists (select 1 from public.post_hides h where h.user_id = (select id from me) and h.post_id = p.id)
    order by p.created_at desc
    limit 600
  ),
  feats as (
    select c.*,
      (select count(*) from public.post_likes x where x.post_id = c.id) as likes,
      (select count(*) from public.post_saves x where x.post_id = c.id) as saves,
      (select count(*) from public.post_comments x where x.post_id = c.id) as comments,
      (select count(*) from public.messages x where x.post_id = c.id) as shares,
      coalesce(st.viewers, 0) as viewers,
      coalesce(st.openers, 0) as openers,
      v.seen as my_seen, v.opens as my_opens,
      exists (select 1 from public.post_likes x where x.post_id = c.id and x.user_id = (select id from me))
        or exists (select 1 from public.post_saves x where x.post_id = c.id and x.user_id = (select id from me)) as engaged,
      c.author_id = (select id from me) as mine,
      c.author_id in (select uid from friends) as is_friend,
      c.author_id in (select uid from followed) as is_followed,
      (c.author_id in (select uid from clubmates) or c.club_id in (select club_id from my_clubs)) as is_club,
      case when p_lat is null or p_lng is null or c.plat is null or c.plng is null then null
           else 111.32 * sqrt(power(c.plat - p_lat, 2) + power((c.plng - p_lng) * cos(radians(p_lat)), 2)) end as km,
      extract(epoch from now() - c.created_at) / 3600.0 as age_h,
      a.home_state = (select home_state from my) as same_state,
      coalesce(aa.w, 0) as author_w,
      coalesce(ma.w / nullif((select make_max from tops), 0), 0) as make_w,
      coalesce(pa.w / nullif((select place_max from tops), 0), 0) as place_w,
      coalesce(ka.w / nullif((select kind_max from tops), 0), 0) as kind_w,
      c.make in (select make from my_makes) as my_make,
      coalesce(ha.by_author, 0) as hid_author, coalesce(ha.by_post, 0) as hid_post,
      coalesce(hm.n, 0) as hid_make
    from cand c
    join public.profiles a on a.id = c.author_id
    left join public.post_stats st on st.post_id = c.id
    left join public.post_views v on v.user_id = (select id from me) and v.post_id = c.id
    left join author_aff aa on aa.author_id = c.author_id
    left join make_aff ma on ma.make = c.make
    left join place_aff pa on pa.place_id = c.place_id
    left join kind_aff ka on ka.kind = c.kind
    left join hid_authors ha on ha.author_id = c.author_id
    left join hid_makes hm on hm.make = c.make
  ),
  scored as (
    select f.*,
      (f.likes + 2 * f.saves + 3 * f.comments + 4 * f.shares)::float8 as ces,
      -- quality
      ((f.likes + 2 * f.saves + 3 * f.comments + 4 * f.shares + 0.5 * f.openers + 2.0) / (f.viewers + 10.0)
        + 0.08 * ln(1 + f.likes + 2 * f.saves + 3 * f.comments + 4 * f.shares)) as quality,
      -- freshness
      (0.12 + 0.88 * power(0.5, f.age_h / 48.0)) as fresh,
      -- relevance
      (1.0
        + case when f.is_friend then 0.8 else 0 end
        + case when f.is_followed then 0.6 else 0 end
        + case when f.is_club then 0.4 else 0 end
        + 0.35 * ln(1 + f.author_w)
        + 0.7 * f.make_w
        + case when f.my_make then 0.3 else 0 end
        + 0.4 * f.place_w
        + 0.2 * f.kind_w
        + case when f.km is null then 0 when f.km < 15 then 0.5 when f.km < 50 then 0.25 else 0 end
        + case when f.same_state then 0.15 else 0 end) as relevance,
      -- novelty
      ((case when f.mine then 0.3 else 1 end)
        * (case when coalesce(f.my_opens, 0) > 0 then 0.25 else power(0.6, least(coalesce(f.my_seen, 0), 4)) end)
        * (case when f.engaged then 0.3 else 1 end)
        * (case when f.hid_author > 0 then 0.15 else power(0.6, least(f.hid_post, 4)) end)
        * power(0.7, least(f.hid_make, 4))) as novelty,
      case when f.age_h < 24 and f.viewers < 30 then 1.5 else 1 end as cold,
      0.9 + 0.2 * ((hashtext(f.id::text || coalesce(p_seed, ''))::bigint + 2147483648) / 4294967295.0) as jitter
    from feats f
  ),
  ranked as (
    select s.*,
      s.quality * s.fresh * s.relevance * s.novelty * s.cold * s.jitter
        * power(0.7, row_number() over (partition by s.author_id order by s.quality * s.fresh * s.relevance * s.novelty * s.cold * s.jitter desc) - 1) as final
    from scored s
  )
  select r.id, r.final::float8,
    case
      when r.mine then 'mine'
      when r.is_friend then 'friend'
      when r.is_followed then 'following'
      when r.is_club then 'club'
      when r.km is not null and r.km < 15 then 'nearby'
      when r.make_w >= 0.5 or r.my_make then 'make:' || r.make
      when r.ces >= 5 then 'popular'
      when r.age_h < 24 then 'new'
      else 'for_you'
    end
  from ranked r
  order by r.final desc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

-- Following: friends, people I follow and my clubs, newest first.
create or replace function public.feed_following(p_limit int default 40, p_before timestamptz default null)
returns table (post_id uuid)
language sql stable security definer set search_path = public as $$
  with me as (select auth.uid() as id)
  select p.id
  from public.posts p
  join public.profiles a on a.id = p.author_id and a.suspended_at is null
  where p.author_id <> (select id from me)
    and (
      p.author_id in (
        select case when f.requester_id = (select id from me) then f.addressee_id else f.requester_id end
        from public.friendships f
        where f.status = 'accepted' and (f.requester_id = (select id from me) or f.addressee_id = (select id from me))
      )
      or p.author_id in (select fo.followee_id from public.follows fo where fo.follower_id = (select id from me))
      or p.club_id in (select cm.club_id from public.club_members cm where cm.user_id = (select id from me))
    )
    and p.author_id not in (
      select b.blocked_id from public.blocks b where b.blocker_id = (select id from me)
      union select b.blocker_id from public.blocks b where b.blocked_id = (select id from me)
    )
    and not exists (select 1 from public.post_hides h where h.user_id = (select id from me) and h.post_id = p.id)
    and (p_before is null or p.created_at < p_before)
  order by p.created_at desc
  limit greatest(1, least(coalesce(p_limit, 40), 100));
$$;

-- "More like this" under a post: same car, make, model, spot, meet, author,
-- nearby, then quality and freshness.
create or replace function public.related_posts(p_post uuid, p_limit int default 12)
returns table (post_id uuid)
language sql stable security definer set search_path = public as $$
  with me as (
    select auth.uid() as id
  ), src as (
    select p.id, p.author_id, p.car_id, p.place_id, p.event_id, p.kind,
           public.post_make(p.car_id, p.author_id) as make,
           (select lower(c.model) from public.cars c where c.id = p.car_id) as model,
           coalesce(p.lat, pl.lat) as plat, coalesce(p.lng, pl.lng) as plng
    from public.posts p left join public.places pl on pl.id = p.place_id
    where p.id = p_post
  ), cand as (
    select p.id, p.author_id, p.car_id, p.place_id, p.event_id, p.kind, p.created_at,
           public.post_make(p.car_id, p.author_id) as make,
           (select lower(c.model) from public.cars c where c.id = p.car_id) as model,
           coalesce(p.lat, pl.lat) as plat, coalesce(p.lng, pl.lng) as plng
    from public.posts p
    left join public.places pl on pl.id = p.place_id
    join public.profiles a on a.id = p.author_id and a.suspended_at is null
    where p.id <> p_post
      and p.author_id not in (
        select b.blocked_id from public.blocks b where b.blocker_id = (select id from me)
        union select b.blocker_id from public.blocks b where b.blocked_id = (select id from me)
      )
      and not exists (select 1 from public.post_hides h where h.user_id = (select id from me) and h.post_id = p.id)
    order by p.created_at desc
    limit 400
  )
  select c.id
  from cand c cross join src s
  order by (
      case when c.car_id is not null and c.car_id = s.car_id then 3 else 0 end
    + case when c.make is not null and c.make = s.make then 2 else 0 end
    + case when c.model is not null and c.model = s.model and c.make = s.make then 1.5 else 0 end
    + case when c.place_id is not null and c.place_id = s.place_id then 2 else 0 end
    + case when c.event_id is not null and c.event_id = s.event_id then 2 else 0 end
    + case when c.author_id = s.author_id then 1 else 0 end
    + case when c.kind = s.kind then 0.3 else 0 end
    + case when c.plat is not null and s.plat is not null
             and 111.32 * sqrt(power(c.plat - s.plat, 2) + power((c.plng - s.plng) * cos(radians(s.plat)), 2)) < 20 then 1 else 0 end
    + 0.5 * ln(1 + (select count(*) from public.post_likes x where x.post_id = c.id)
                 + 2 * (select count(*) from public.post_saves x where x.post_id = c.id)
                 + 3 * (select count(*) from public.post_comments x where x.post_id = c.id))
    + 0.5 * power(0.5, extract(epoch from now() - c.created_at) / 604800.0)
  ) desc, c.created_at desc
  limit greatest(1, least(coalesce(p_limit, 12), 30));
$$;

revoke all on function public.log_post_views(uuid[]) from public, anon;
revoke all on function public.log_post_open(uuid, int) from public, anon;
revoke all on function public.hide_post(uuid, text) from public, anon;
revoke all on function public.post_make(uuid, uuid) from public, anon;
revoke all on function public.feed_for_you(int, uuid[], text, double precision, double precision) from public, anon;
revoke all on function public.feed_following(int, timestamptz) from public, anon;
revoke all on function public.related_posts(uuid, int) from public, anon;
grant execute on function public.log_post_views(uuid[]) to authenticated;
grant execute on function public.log_post_open(uuid, int) to authenticated;
grant execute on function public.hide_post(uuid, text) to authenticated;
grant execute on function public.post_make(uuid, uuid) to authenticated;
grant execute on function public.feed_for_you(int, uuid[], text, double precision, double precision) to authenticated;
grant execute on function public.feed_following(int, timestamptz) to authenticated;
grant execute on function public.related_posts(uuid, int) to authenticated;
