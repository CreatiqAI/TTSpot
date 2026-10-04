-- Close two gaps between photo moderation (0103) and the 0.3.53 features
-- built next to it (0097 / 0101 / 0102):
--
-- 1. Friend-post, mention and club-post pings fired at INSERT, while the post
--    was still 'pending', so a caption preview went out before the photo check.
--    They now fire when a post becomes 'ok' (at insert when the checker is off,
--    or on the update that clears it), and only the first time: an edited post
--    that is re-checked does not ping everyone again.
-- 2. The feed / tag / search RPCs are security definer, so they still ranked
--    hidden posts (the client then dropped them, leaving short pages and tag
--    counts that included them). They now skip anything not 'ok' (For you keeps
--    my own posts, which I can always see).
--
-- The functions are patched in place from their live definitions (exact
-- anchors, applied once), so their long bodies aren't copied here a second time.

do $patch$
declare
  v_def text;
  v_new text;
  r record;
begin
  for r in
    select * from (values
      ('feed_for_you',
       'where not (p.id = any (coalesce(p_exclude, ''{}''::uuid[])))',
       'where (p.moderation = ''ok'' or p.author_id = (select id from me)) and not (p.id = any (coalesce(p_exclude, ''{}''::uuid[])))'),
      ('feed_following',
       'where p.author_id <> (select id from me)',
       'where p.moderation = ''ok'' and p.author_id <> (select id from me)'),
      ('related_posts',
       'where p.id <> p_post',
       'where p.moderation = ''ok'' and p.id <> p_post'),
      ('tag_posts',
       'where (select tag from t) <> ''''',
       'where p.moderation = ''ok'' and (select tag from t) <> '''''),
      ('search_posts',
       'where (select tsq from q) is not null',
       'where p.moderation = ''ok'' and (select tsq from q) is not null'),
      ('search_tags',
       'where cardinality(p.tags) > 0',
       'where p.moderation = ''ok'' and cardinality(p.tags) > 0'),
      ('on_post_ping',
       E'begin\n',
       E'begin\n  -- Announced once: a re-checked edit doesn''t ping again (0105).\n  if tg_op = ''UPDATE'' and exists (select 1 from public.notifications n where n.post_id = new.id and n.type::text in (''friend_post'', ''mention'', ''club_post'')) then return null; end if;\n'),
      ('on_post_social',
       E'begin\n',
       E'begin\n  -- Announced once: a re-checked edit doesn''t ping again (0105).\n  if tg_op = ''UPDATE'' and exists (select 1 from public.notifications n where n.post_id = new.id and n.type::text in (''friend_post'', ''mention'', ''club_post'')) then return null; end if;\n')
    ) as t(fn, anchor, repl)
  loop
    select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.proname = r.fn and p.pronamespace = 'public'::regnamespace;
    if v_def is null then raise exception 'moderation gates: % not found', r.fn; end if;
    if position('p.moderation = ''ok''' in v_def) > 0 or position('(0105)' in v_def) > 0 then
      continue; -- already patched
    end if;
    if position(r.anchor in v_def) = 0 then raise exception 'moderation gates: anchor not found in %', r.fn; end if;
    -- Only the first occurrence (the trigger bodies' first "begin").
    v_new := overlay(v_def placing r.repl from position(r.anchor in v_def) for char_length(r.anchor));
    execute v_new;
  end loop;
end
$patch$;

-- Pings when a post becomes visible, not when it's written.
drop trigger if exists posts_after_insert_ping on public.posts;
create trigger posts_after_insert_ping after insert on public.posts
  for each row when (new.moderation = 'ok') execute function public.on_post_ping();
drop trigger if exists posts_ok_ping on public.posts;
create trigger posts_ok_ping after update of moderation on public.posts
  for each row when (new.moderation = 'ok' and old.moderation is distinct from 'ok') execute function public.on_post_ping();

drop trigger if exists posts_after_insert_social on public.posts;
create trigger posts_after_insert_social after insert on public.posts
  for each row when (new.moderation = 'ok') execute function public.on_post_social();
drop trigger if exists posts_ok_social on public.posts;
create trigger posts_ok_social after update of moderation on public.posts
  for each row when (new.moderation = 'ok' and old.moderation is distinct from 'ok') execute function public.on_post_social();
