-- #tags, post search and my own post stats (0.3.53).
--
--   tags        posts.tags: the #words in a post's title and caption,
--               lowercase, de-duplicated, first 10, each 2 to 30 letters,
--               digits or underscores. A trigger fills it on every insert and
--               edit, so every client (old app versions too) gets it.
--   search      post_search: one tsvector per post over its title, tags, car
--               make / model, caption and place name ('simple' config, so
--               English and Malay words both match as typed). Kept beside the
--               post rather than on it, so `select *` on posts stays small.
--   tag page    tag_posts(tag, limit, offset): engagement x freshness, with
--               the same block / hide / suspended rules as the feeds.
--   search      search_posts(q, limit, offset): text rank x freshness x
--               engagement. search_tags(q, limit): matching tags and counts
--               (popular tags when q is empty).
--   my stats    my_post_stats(ids): views, saves, likes, comments and shares
--               for posts I wrote. Nobody else's.
--   ranking     feed_for_you gains a tag interest term (up to +0.5 relevance)
--               and the reason 'tag:<tag>'; related_posts scores +1.5 per
--               shared tag (3 at most). Both signatures are unchanged.

-- --------------------------------------------------------------- tags ---

alter table public.posts add column if not exists tags text[] not null default '{}';
alter table public.posts drop constraint if exists posts_tags_max;
alter table public.posts add constraint posts_tags_max check (cardinality(tags) <= 10);
create index if not exists posts_tags_idx on public.posts using gin (tags);

-- '#Myvi at #TTDI #myvi' -> {myvi, ttdi}. A # counts at the start or after a
-- character that isn't a letter, digit, underscore or & (so 'abc#x' and
-- '&#39;' are not tags). Words over 30 characters are not tags at all.
create or replace function public.parse_tags(p_text text) returns text[]
language sql immutable parallel safe set search_path = public as $$
  select coalesce(array_agg(t.tag order by t.first_at), '{}'::text[])
  from (
    select lower(r.m[2]) as tag, min(r.ord) as first_at
    from regexp_matches(coalesce(p_text, ''), '(^|[^[:alnum:]_&])#([[:alnum:]_]+)', 'g') with ordinality as r(m, ord)
    where char_length(r.m[2]) between 2 and 30
    group by lower(r.m[2])
    order by min(r.ord)
    limit 10
  ) t;
$$;

-- Tags always come from the text: anything a client sends is replaced.
create or replace function public.posts_fill_tags() returns trigger
language plpgsql set search_path = public as $$
begin
  new.tags := public.parse_tags(concat_ws(' ', new.title, new.caption));
  return new;
end;
$$;

drop trigger if exists posts_fill_tags on public.posts;
create trigger posts_fill_tags before insert or update of title, caption, tags on public.posts
  for each row execute function public.posts_fill_tags();

-- ------------------------------------------------------------- search ---

create table if not exists public.post_search (
  post_id  uuid primary key references public.posts (id) on delete cascade,
  tsv      tsvector not null
);
create index if not exists post_search_tsv_idx on public.post_search using gin (tsv);

-- Only the security definer RPCs below read it.
alter table public.post_search enable row level security;
revoke all on public.post_search from anon, authenticated;
grant all on public.post_search to service_role;

-- Title and tags weigh most, then the tagged car and the caption, then the place.
create or replace function public.post_search_doc(
  p_title text, p_caption text, p_tags text[], p_car uuid, p_place uuid, p_place_name text
) returns tsvector
language sql stable security definer set search_path = public as $$
  select setweight(to_tsvector('simple', coalesce(p_title, '')), 'A')
      || setweight(to_tsvector('simple', array_to_string(coalesce(p_tags, '{}'::text[]), ' ')), 'A')
      || setweight(to_tsvector('simple', coalesce((select concat_ws(' ', c.make, c.model) from public.cars c where c.id = p_car), '')), 'B')
      || setweight(to_tsvector('simple', coalesce(p_caption, '')), 'B')
      || setweight(to_tsvector('simple', coalesce((select pl.name from public.places pl where pl.id = p_place), p_place_name, '')), 'C');
$$;

create or replace function public.posts_index_search() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.post_search (post_id, tsv)
  values (new.id, public.post_search_doc(new.title, new.caption, new.tags, new.car_id, new.place_id, new.place_name))
  on conflict (post_id) do update set tsv = excluded.tsv;
  return null;
end;
$$;

drop trigger if exists posts_index_search on public.posts;
create trigger posts_index_search after insert or update of title, caption, tags, car_id, place_id, place_name on public.posts
  for each row execute function public.posts_index_search();

-- A car renamed (make / model) or a spot renamed: its posts are found by the new name.
create or replace function public.cars_reindex_posts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.make is distinct from old.make or new.model is distinct from old.model then
    insert into public.post_search (post_id, tsv)
    select p.id, public.post_search_doc(p.title, p.caption, p.tags, p.car_id, p.place_id, p.place_name)
    from public.posts p where p.car_id = new.id
    on conflict (post_id) do update set tsv = excluded.tsv;
  end if;
  return null;
end;
$$;

drop trigger if exists cars_reindex_posts on public.cars;
create trigger cars_reindex_posts after update of make, model on public.cars
  for each row execute function public.cars_reindex_posts();

create or replace function public.places_reindex_posts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.name is distinct from old.name then
    insert into public.post_search (post_id, tsv)
    select p.id, public.post_search_doc(p.title, p.caption, p.tags, p.car_id, p.place_id, p.place_name)
    from public.posts p where p.place_id = new.id
    on conflict (post_id) do update set tsv = excluded.tsv;
  end if;
  return null;
end;
$$;

drop trigger if exists places_reindex_posts on public.places;
create trigger places_reindex_posts after update of name on public.places
  for each row execute function public.places_reindex_posts();

-- Backfill: touching tags runs both triggers on every existing post, so each
-- gets its tags (before) and its search row (after).
update public.posts set tags = '{}' where true;

-- ----------------------------------------------------------- tag page ---

-- One page of a tag: best first. score = engagement x freshness, where
-- engagement = 1 + ln(1 + likes + 2 saves + 3 comments + 4 shares + opens / 2)
-- and freshness halves every 3 days (never below 0.1). "Fewer from this
-- person" sinks that author (x0.15), as in For you. total = every post with
-- the tag that I may see.
create or replace function public.tag_posts(p_tag text, p_limit int default 30, p_offset int default 0)
returns table (post_id uuid, score double precision, total bigint)
language sql stable security definer set search_path = public as $$
  with me as (
    select auth.uid() as id
  ), t as (
    select lower(regexp_replace(coalesce(p_tag, ''), '^#+', '')) as tag
  ), blocked as (
    select b.blocked_id as uid from public.blocks b where b.blocker_id = (select id from me)
    union select b.blocker_id from public.blocks b where b.blocked_id = (select id from me)
  ), hid_authors as (
    select distinct h.author_id from public.post_hides h where h.user_id = (select id from me) and h.scope = 'author'
  ), tagged as (
    select p.id, p.author_id, p.created_at
    from public.posts p
    join public.profiles a on a.id = p.author_id and a.suspended_at is null
    where (select tag from t) <> ''
      and p.tags @> array[(select tag from t)]
      and p.author_id not in (select uid from blocked)
      and not exists (select 1 from public.post_hides h where h.user_id = (select id from me) and h.post_id = p.id)
  ), cand as (
    select * from tagged order by created_at desc limit 1000
  ), scored as (
    select c.id, c.created_at,
      (1 + ln(1
          + (select count(*) from public.post_likes x where x.post_id = c.id)
          + 2 * (select count(*) from public.post_saves x where x.post_id = c.id)
          + 3 * (select count(*) from public.post_comments x where x.post_id = c.id)
          + 4 * (select count(*) from public.messages x where x.post_id = c.id)
          + 0.5 * coalesce((select st.openers from public.post_stats st where st.post_id = c.id), 0)))
      * (0.1 + 0.9 * power(0.5, extract(epoch from now() - c.created_at) / 3600.0 / 72.0))
      * (case when c.author_id in (select author_id from hid_authors) then 0.15 else 1 end) as score
    from cand c
  )
  select s.id, s.score::float8, (select count(*) from tagged)
  from scored s
  order by s.score desc, s.created_at desc, s.id
  limit greatest(1, least(coalesce(p_limit, 30), 60))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- -------------------------------------------------------------- search ---

-- Posts for a search box: every word must match (as a prefix, so "myv"
-- finds Myvi). score = text rank x freshness (halves every 2 weeks, never
-- below 0.3) x engagement (1 + 0.3 ln(1 + likes + 2 saves + 3 comments +
-- 4 shares + opens / 2)). Same block / hide / suspended rules as the feeds.
create or replace function public.search_posts(p_q text, p_limit int default 30, p_offset int default 0)
returns table (post_id uuid, score double precision)
language sql stable security definer set search_path = public as $$
  with me as (
    select auth.uid() as id
  ), words as (
    select distinct w.w from regexp_split_to_table(lower(coalesce(p_q, '')), '[^[:alnum:]]+') as w(w)
    where w.w <> '' and char_length(w.w) <= 40
    limit 8
  ), q as (
    select case when count(*) = 0 then null else to_tsquery('simple', string_agg(w || ':*', ' & ')) end as tsq from words
  ), blocked as (
    select b.blocked_id as uid from public.blocks b where b.blocker_id = (select id from me)
    union select b.blocker_id from public.blocks b where b.blocked_id = (select id from me)
  ), hid_authors as (
    select distinct h.author_id from public.post_hides h where h.user_id = (select id from me) and h.scope = 'author'
  ), matches as (
    select p.id, p.author_id, p.created_at, ts_rank(s.tsv, (select tsq from q)) as rank
    from public.post_search s
    join public.posts p on p.id = s.post_id
    join public.profiles a on a.id = p.author_id and a.suspended_at is null
    where (select tsq from q) is not null
      and s.tsv @@ (select tsq from q)
      and p.author_id not in (select uid from blocked)
      and not exists (select 1 from public.post_hides h where h.user_id = (select id from me) and h.post_id = p.id)
    order by rank desc, p.created_at desc
    limit 500
  ), scored as (
    select m.id, m.created_at,
      m.rank
      * (0.3 + 0.7 * power(0.5, extract(epoch from now() - m.created_at) / 3600.0 / 336.0))
      * (1 + 0.3 * ln(1
          + (select count(*) from public.post_likes x where x.post_id = m.id)
          + 2 * (select count(*) from public.post_saves x where x.post_id = m.id)
          + 3 * (select count(*) from public.post_comments x where x.post_id = m.id)
          + 4 * (select count(*) from public.messages x where x.post_id = m.id)
          + 0.5 * coalesce((select st.openers from public.post_stats st where st.post_id = m.id), 0)))
      * (case when m.author_id in (select author_id from hid_authors) then 0.15 else 1 end) as score
    from matches m
  )
  select s.id, s.score::float8
  from scored s
  order by s.score desc, s.created_at desc, s.id
  limit greatest(1, least(coalesce(p_limit, 30), 60))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- Tags that start with what I typed ('#My' -> myvi, myvi_gen3), the exact
-- one first, then by how many posts I may see carry them. Empty q: the most
-- used tags of the last 60 days (the composer's # suggestions).
create or replace function public.search_tags(p_q text default '', p_limit int default 8)
returns table (tag text, posts bigint)
language sql stable security definer set search_path = public as $$
  with me as (
    select auth.uid() as id
  ), qq as (
    select lower(regexp_replace(coalesce(p_q, ''), '[^[:alnum:]_]', '', 'g')) as q
  ), blocked as (
    select b.blocked_id as uid from public.blocks b where b.blocker_id = (select id from me)
    union select b.blocker_id from public.blocks b where b.blocked_id = (select id from me)
  )
  select t.tag, count(*) as posts
  from public.posts p
  join public.profiles a on a.id = p.author_id and a.suspended_at is null
  cross join lateral unnest(p.tags) as t(tag)
  where cardinality(p.tags) > 0
    and (case when (select q from qq) = '' then p.created_at > now() - interval '60 days'
              else starts_with(t.tag, (select q from qq)) end)
    and p.author_id not in (select uid from blocked)
    and not exists (select 1 from public.post_hides h where h.user_id = (select id from me) and h.post_id = p.id)
  group by t.tag
  order by (t.tag = (select q from qq)) desc, count(*) desc, t.tag
  limit greatest(1, least(coalesce(p_limit, 8), 30));
$$;

-- ----------------------------------------------------------- my stats ---

-- Numbers for posts I wrote: unique viewers (post_stats, which never counts
-- the author), saves, likes, comments, shares into chats. Ids that aren't
-- mine return nothing.
create or replace function public.my_post_stats(p_ids uuid[])
returns table (post_id uuid, views int, saves int, likes int, comments int, shares int)
language sql stable security definer set search_path = public as $$
  select p.id,
    coalesce((select st.viewers from public.post_stats st where st.post_id = p.id), 0),
    (select count(*)::int from public.post_saves x where x.post_id = p.id),
    (select count(*)::int from public.post_likes x where x.post_id = p.id),
    (select count(*)::int from public.post_comments x where x.post_id = p.id),
    (select count(*)::int from public.messages x where x.post_id = p.id)
  from public.posts p
  where auth.uid() is not null
    and p.author_id = auth.uid()
    and p.id = any (coalesce(p_ids[1:100], '{}'::uuid[]));
$$;

-- -------------------------------------------------------------- feeds ---

-- As in 0095; only the tag interest is new: sig_posts' and cand's tags,
-- tag_aff, tops.tag_max, feats.tag_w / top_tag (the candidate's tag I engage
-- with most, over the most I engage with any tag, like make_w), +0.5 tag_w in
-- relevance, and the reason 'tag:<tag>' when that tag is a strong interest
-- (tag_w >= 0.5) and beats the make.
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
    select s.w, p.author_id, p.place_id, p.kind, public.post_make(p.car_id, p.author_id) as make, p.tags
    from signals s join public.posts p on p.id = s.post_id
    where p.author_id <> (select id from me)
  ),
  author_aff as (select author_id, sum(w) as w from sig_posts group by author_id),
  make_aff   as (select make, sum(w) as w from sig_posts where make is not null group by make),
  place_aff  as (select place_id, sum(w) as w from sig_posts where place_id is not null group by place_id),
  kind_aff   as (select kind, sum(w) as w from sig_posts group by kind),
  tag_aff    as (select t.tag, sum(sp.w) as w from sig_posts sp cross join lateral unnest(sp.tags) as t(tag) group by t.tag),
  tops as (
    select (select max(w) from make_aff) as make_max,
           (select max(w) from place_aff) as place_max,
           (select max(w) from kind_aff) as kind_max,
           (select max(w) from tag_aff) as tag_max
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
           coalesce(p.lat, pl.lat) as plat, coalesce(p.lng, pl.lng) as plng,
           p.tags
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
      coalesce(tg.w / nullif((select tag_max from tops), 0), 0) as tag_w,
      tg.tag as top_tag,
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
    left join lateral (
      select ta.tag, ta.w from unnest(c.tags) as ct(tag) join tag_aff ta on ta.tag = ct.tag
      order by ta.w desc, ta.tag limit 1
    ) tg on true
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
        + 0.5 * f.tag_w
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
      when r.tag_w >= 0.5 and r.tag_w > r.make_w then 'tag:' || r.top_tag
      when r.make_w >= 0.5 or r.my_make then 'make:' || r.make
      when r.ces >= 5 then 'popular'
      when r.age_h < 24 then 'new'
      else 'for_you'
    end
  from ranked r
  order by r.final desc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

-- "More like this": as in 0094, plus +1.5 for each tag the two posts share
-- (3 tags at most).
create or replace function public.related_posts(p_post uuid, p_limit int default 12)
returns table (post_id uuid)
language sql stable security definer set search_path = public as $$
  with me as (
    select auth.uid() as id
  ), src as (
    select p.id, p.author_id, p.car_id, p.place_id, p.event_id, p.kind,
           public.post_make(p.car_id, p.author_id) as make,
           (select lower(c.model) from public.cars c where c.id = p.car_id) as model,
           coalesce(p.lat, pl.lat) as plat, coalesce(p.lng, pl.lng) as plng,
           p.tags
    from public.posts p left join public.places pl on pl.id = p.place_id
    where p.id = p_post
  ), cand as (
    select p.id, p.author_id, p.car_id, p.place_id, p.event_id, p.kind, p.created_at,
           public.post_make(p.car_id, p.author_id) as make,
           (select lower(c.model) from public.cars c where c.id = p.car_id) as model,
           coalesce(p.lat, pl.lat) as plat, coalesce(p.lng, pl.lng) as plng,
           p.tags
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
    + 1.5 * least(3, cardinality(array(select unnest(c.tags) intersect select unnest(s.tags))))
    + 0.5 * ln(1 + (select count(*) from public.post_likes x where x.post_id = c.id)
                 + 2 * (select count(*) from public.post_saves x where x.post_id = c.id)
                 + 3 * (select count(*) from public.post_comments x where x.post_id = c.id))
    + 0.5 * power(0.5, extract(epoch from now() - c.created_at) / 604800.0)
  ) desc, c.created_at desc
  limit greatest(1, least(coalesce(p_limit, 12), 30));
$$;

-- -------------------------------------------------------------- grants ---

revoke all on function public.parse_tags(text) from public, anon;
revoke all on function public.post_search_doc(text, text, text[], uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.tag_posts(text, int, int) from public, anon;
revoke all on function public.search_posts(text, int, int) from public, anon;
revoke all on function public.search_tags(text, int) from public, anon;
revoke all on function public.my_post_stats(uuid[]) from public, anon;
revoke all on function public.feed_for_you(int, uuid[], text, double precision, double precision) from public, anon;
revoke all on function public.related_posts(uuid, int) from public, anon;
grant execute on function public.parse_tags(text) to authenticated;
grant execute on function public.tag_posts(text, int, int) to authenticated;
grant execute on function public.search_posts(text, int, int) to authenticated;
grant execute on function public.search_tags(text, int) to authenticated;
grant execute on function public.my_post_stats(uuid[]) to authenticated;
grant execute on function public.feed_for_you(int, uuid[], text, double precision, double precision) to authenticated;
grant execute on function public.related_posts(uuid, int) to authenticated;
