-- Follow (0.3.52). Members follow drivers, clubs and partners without being
-- friends or joining. People already have public.follows; this adds clubs
-- and partners. What I follow lands in Home's "Following" and ranks higher in
-- "For you" (relevance +0.6, reason 'following'):
--
--   a driver   their posts (public.follows, as before)
--   a club     posts in the club (posts.club_id)
--   a partner  posts by or tagged to the partner (posts.vendor_id)
--
-- Anyone signed in can read the rows (follower counts, like public.follows);
-- each member adds and removes only their own. A club's owner can't follow
-- their own club and a partner can't follow their own shop. Blocked authors
-- stay out of both feeds (the block filters below are unchanged).

-- -------------------------------------------------------------- clubs ---
create table if not exists public.club_follows (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  club_id     uuid not null references public.clubs (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, club_id)
);
create index if not exists club_follows_club_idx on public.club_follows (club_id);

alter table public.club_follows enable row level security;
drop policy if exists "club_follows: read" on public.club_follows;
drop policy if exists "club_follows: add own" on public.club_follows;
drop policy if exists "club_follows: remove own" on public.club_follows;
create policy "club_follows: read" on public.club_follows for select to authenticated using (true);
create policy "club_follows: add own" on public.club_follows for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.clubs c where c.id = club_id and c.owner_id <> auth.uid())
  );
create policy "club_follows: remove own" on public.club_follows for delete to authenticated
  using (user_id = auth.uid());

revoke all on public.club_follows from anon, authenticated;
grant select, insert, delete on public.club_follows to authenticated;
grant all on public.club_follows to service_role;

-- ----------------------------------------------------------- partners ---
create table if not exists public.vendor_follows (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  vendor_id   uuid not null references public.vendors (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, vendor_id)
);
create index if not exists vendor_follows_vendor_idx on public.vendor_follows (vendor_id, created_at desc);

alter table public.vendor_follows enable row level security;
drop policy if exists "vendor_follows: read" on public.vendor_follows;
drop policy if exists "vendor_follows: add own" on public.vendor_follows;
drop policy if exists "vendor_follows: remove own" on public.vendor_follows;
create policy "vendor_follows: read" on public.vendor_follows for select to authenticated using (true);
create policy "vendor_follows: add own" on public.vendor_follows for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.vendors v where v.id = vendor_id and v.active and v.owner_id <> auth.uid())
  );
create policy "vendor_follows: remove own" on public.vendor_follows for delete to authenticated
  using (user_id = auth.uid());

revoke all on public.vendor_follows from anon, authenticated;
grant select, insert, delete on public.vendor_follows to authenticated;
grant all on public.vendor_follows to service_role;

-- -------------------------------------------------------------- feeds ---
-- As in 0094; only `followed_clubs`, `followed_vendors`, cand's vendor_id and
-- is_followed are new.
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
  ), followed_clubs as (
    select cf.club_id from public.club_follows cf where cf.user_id = (select id from me)
  ), followed_vendors as (
    select vf.vendor_id from public.vendor_follows vf where vf.user_id = (select id from me)
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
    select p.id, p.author_id, p.kind, p.created_at, p.place_id, p.club_id, p.vendor_id,
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
      (c.author_id in (select uid from followed)
        or c.club_id in (select club_id from followed_clubs)
        or c.vendor_id in (select vendor_id from followed_vendors)) as is_followed,
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

-- Following: friends, people, clubs and partners I follow, and my clubs,
-- newest first.
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
      or p.club_id in (select cf.club_id from public.club_follows cf where cf.user_id = (select id from me))
      or p.vendor_id in (select vf.vendor_id from public.vendor_follows vf where vf.user_id = (select id from me))
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

revoke all on function public.feed_for_you(int, uuid[], text, double precision, double precision) from public, anon;
revoke all on function public.feed_following(int, timestamptz) from public, anon;
grant execute on function public.feed_for_you(int, uuid[], text, double precision, double precision) to authenticated;
grant execute on function public.feed_following(int, timestamptz) to authenticated;
