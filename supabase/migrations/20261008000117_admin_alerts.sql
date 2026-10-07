-- =============================================================================
-- 0117 admin_alerts: admins get a push + an Activity row when something waits
-- for their review (batch 0.3.61).
--
-- notification_type 'admin', body '<kind>:<detail>' (the app's AdminAlert and
-- push/index.ts adminAlert() read it):
--   report:<target_type>:<reason>   a member reported something (reports insert)
--   spot:<place name>               a member suggested a spot (place_suggestions insert)
--   verify:<place name>             a sticker check-in photo went to 'review'
--                                   (the AI was unsure, or the 24 h stale sweep)
--   flagged:<post|moment>:<why>     the photo check hid a post / moment
--                                   (moderation became 'flagged')
-- actor = the member behind it (reporter, suggester, checker-in, author);
-- post_id = the post for a reported or flagged post (Activity shows its cover).
--
-- Throttle: one push per admin per kind while they have an unread, pushed
-- alert of that kind from the last 30 minutes; later ones in the burst still
-- land in Activity, silent (no push). Reading Activity re-arms the push.
-- An admin is never alerted about their own action (like notify()).
-- Partner / club / organizer applications keep their 'partner' rows (0009).
--
-- Every trigger swallows its own errors: an alert must never block a report,
-- a suggestion, a check-in or the photo check. Safe to re-run.
-- =============================================================================

alter type public.notification_type add value if not exists 'admin';

-- --------------------------------------------------------------- helper ---
create or replace function public.notify_admins(p_kind text, p_body text, p_actor uuid default null, p_post uuid default null)
returns int
language plpgsql security definer set search_path = public as $$
declare
  a uuid;
  v_silent boolean;
  n int := 0;
begin
  for a in select id from public.profiles where is_admin and id is distinct from p_actor loop
    -- Two reports at once: the second waits for the first's row, then sees it.
    perform pg_advisory_xact_lock(hashtext('admin_alert:' || a || ':' || p_kind));
    select exists (
      select 1 from public.notifications
       where user_id = a and type = 'admin' and read_at is null and not silent
         and created_at > now() - interval '30 minutes'
         and split_part(body, ':', 1) = p_kind
    ) into v_silent;
    insert into public.notifications (user_id, actor_id, type, post_id, body, silent)
    values (a, p_actor, 'admin', p_post, p_kind || ':' || coalesce(p_body, ''), v_silent);
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke execute on function public.notify_admins(text, text, uuid, uuid) from public, anon, authenticated;

-- One line, no newlines, at most [n] characters.
create or replace function public.admin_alert_clip(p text, n int default 80) returns text
language sql immutable as $$
  select case when length(t) > n then left(t, n - 1) || '…' else t end
    from (select btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')) as t) x;
$$;

-- -------------------------------------------------------------- reports ---
create or replace function public.on_report_alert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify_admins(
    'report',
    new.target_type::text || ':' || public.admin_alert_clip(new.reason),
    new.reporter_id,
    case when new.target_type::text = 'post' and exists (select 1 from public.posts where id = new.target_id) then new.target_id end
  );
  return new;
exception when others then
  raise warning 'admin alert (report %) failed: %', new.id, sqlerrm;
  return new;
end;
$$;
drop trigger if exists reports_admin_alert on public.reports;
create trigger reports_admin_alert after insert on public.reports
  for each row execute function public.on_report_alert();

-- ------------------------------------------------------ spot suggestions ---
create or replace function public.on_place_suggestion_alert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify_admins('spot', public.admin_alert_clip(new.name), new.user_id);
  return new;
exception when others then
  raise warning 'admin alert (suggestion %) failed: %', new.id, sqlerrm;
  return new;
end;
$$;
drop trigger if exists place_suggestions_admin_alert on public.place_suggestions;
create trigger place_suggestions_admin_alert after insert on public.place_suggestions
  for each row when (new.status = 'pending') execute function public.on_place_suggestion_alert();

-- ------------------------------------------- sticker check-ins to review ---
create or replace function public.on_spot_verification_alert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify_admins(
    'verify',
    public.admin_alert_clip((select name from public.places where id = new.place_id)),
    new.user_id
  );
  return new;
exception when others then
  raise warning 'admin alert (verification %) failed: %', new.id, sqlerrm;
  return new;
end;
$$;
drop trigger if exists spot_verifications_admin_alert on public.spot_verifications;
create trigger spot_verifications_admin_alert after insert on public.spot_verifications
  for each row when (new.status = 'review') execute function public.on_spot_verification_alert();
drop trigger if exists spot_verifications_admin_alert_upd on public.spot_verifications;
create trigger spot_verifications_admin_alert_upd after update of status on public.spot_verifications
  for each row when (new.status = 'review' and old.status is distinct from 'review') execute function public.on_spot_verification_alert();

-- ------------------------------------------ posts / moments the check hid ---
-- moderation_reason reads 'Flagged: <categories>' (moderate-content/decide.ts).
create or replace function public.on_moderation_flag_alert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_kind text := case when tg_table_name = 'posts' then 'post' else 'moment' end;
begin
  perform public.notify_admins(
    'flagged',
    v_kind || ':' || public.admin_alert_clip(regexp_replace(coalesce(new.moderation_reason, ''), '^\s*Flagged:\s*', '', 'i')),
    new.author_id,
    case when v_kind = 'post' then new.id end
  );
  return new;
exception when others then
  raise warning 'admin alert (% %) failed: %', v_kind, new.id, sqlerrm;
  return new;
end;
$$;
drop trigger if exists posts_flag_alert on public.posts;
create trigger posts_flag_alert after insert on public.posts
  for each row when (new.moderation = 'flagged') execute function public.on_moderation_flag_alert();
drop trigger if exists posts_flag_alert_upd on public.posts;
create trigger posts_flag_alert_upd after update of moderation on public.posts
  for each row when (new.moderation = 'flagged' and old.moderation is distinct from 'flagged') execute function public.on_moderation_flag_alert();
drop trigger if exists stories_flag_alert on public.stories;
create trigger stories_flag_alert after insert on public.stories
  for each row when (new.moderation = 'flagged') execute function public.on_moderation_flag_alert();
drop trigger if exists stories_flag_alert_upd on public.stories;
create trigger stories_flag_alert_upd after update of moderation on public.stories
  for each row when (new.moderation = 'flagged' and old.moderation is distinct from 'flagged') execute function public.on_moderation_flag_alert();
