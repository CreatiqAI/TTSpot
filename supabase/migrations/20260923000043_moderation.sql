-- Moderation for store review (App Store 1.2 / Play UGC policy): every report
-- shows what was reported and who posted it, and admins can remove the content
-- and suspend the author. Suspension also bans the auth user, so the app can't
-- sign in or refresh its session any more.

alter table public.profiles add column if not exists suspended_at timestamptz;

-- Old post reports were filed as 'comment' with a post id; move them over.
update public.reports r set target_type = 'post'
  where r.target_type = 'comment'
    and not exists (select 1 from public.event_comments c where c.id = r.target_id)
    and exists (select 1 from public.posts p where p.id = r.target_id);
update public.reports r set target_type = 'post_comment'
  where r.target_type = 'comment'
    and not exists (select 1 from public.event_comments c where c.id = r.target_id)
    and exists (select 1 from public.post_comments c where c.id = r.target_id);

-- Owner + parent of a report target (parent = post for a post comment, meet for
-- a meet comment, conversation for a message).
create or replace function public.report_target_info(p_type text, p_id uuid,
  out label text, out owner_id uuid, out parent_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  case p_type
    when 'profile' then select '@' || p.username, p.id, null into label, owner_id, parent_id from public.profiles p where p.id = p_id;
    when 'event' then select e.title, e.organizer_id, null into label, owner_id, parent_id from public.events e where e.id = p_id;
    when 'comment' then select left(c.body, 60), c.user_id, c.event_id into label, owner_id, parent_id from public.event_comments c where c.id = p_id;
    when 'post' then select coalesce(nullif(left(coalesce(p.title, p.caption), 60), ''), 'Photo post'), p.author_id, null into label, owner_id, parent_id from public.posts p where p.id = p_id;
    when 'post_comment' then select left(c.body, 60), c.user_id, c.post_id into label, owner_id, parent_id from public.post_comments c where c.id = p_id;
    when 'message' then select left(m.body, 60), m.sender_id, m.conversation_id into label, owner_id, parent_id from public.messages m where m.id = p_id;
    when 'story' then select coalesce(nullif(left(s.caption, 60), ''), 'Moment'), s.author_id, null into label, owner_id, parent_id from public.stories s where s.id = p_id;
    when 'club' then select c.name, c.owner_id, null into label, owner_id, parent_id from public.clubs c where c.id = p_id;
    else null;
  end case;
end;
$$;
revoke execute on function public.report_target_info(text, uuid) from public, anon, authenticated;

drop function if exists public.admin_reports(int);
create function public.admin_reports(p_limit int default 100)
returns table (id uuid, reporter uuid, reporter_username text, target_type text, target_id uuid, reason text,
  created_at timestamptz, resolved_at timestamptz, target_label text, target_owner uuid,
  target_owner_username text, target_owner_suspended boolean, target_parent uuid, note text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select r.id, r.reporter_id, pr.username::text, r.target_type::text, r.target_id, r.reason, r.created_at, r.resolved_at,
      coalesce(i.label, '(removed)'), i.owner_id, po.username::text, po.suspended_at is not null, i.parent_id, r.note
    from public.reports r
    join public.profiles pr on pr.id = r.reporter_id
    cross join lateral public.report_target_info(r.target_type::text, r.target_id) i
    left join public.profiles po on po.id = i.owner_id
    order by r.resolved_at nulls first, r.created_at desc
    limit p_limit;
end;
$$;

-- Delete the reported content and resolve every open report on it.
create or replace function public.admin_remove_reported(p_report uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.reports;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  select * into r from public.reports where id = p_report;
  if r.id is null then raise exception 'Report not found'; end if;
  case r.target_type::text
    when 'event' then delete from public.events where id = r.target_id;
    when 'comment' then delete from public.event_comments where id = r.target_id;
    when 'post' then delete from public.posts where id = r.target_id;
    when 'post_comment' then delete from public.post_comments where id = r.target_id;
    when 'message' then delete from public.messages where id = r.target_id;
    when 'story' then delete from public.stories where id = r.target_id;
    when 'club' then delete from public.clubs where id = r.target_id;
    else raise exception 'Profiles can''t be removed, suspend the member instead';
  end case;
  update public.reports set resolved_at = now(), resolved_by = auth.uid(), note = coalesce(note, 'Content removed')
    where target_type = r.target_type and target_id = r.target_id and resolved_at is null;
end;
$$;

-- Suspend / restore a member. Suspending bans the auth user and ends their
-- sessions; the access token they hold expires within the hour.
create or replace function public.admin_set_suspended(p_user uuid, p_suspended boolean) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_user = auth.uid() then raise exception 'You can''t suspend yourself'; end if;
  update public.profiles set suspended_at = case when p_suspended then now() else null end where id = p_user;
  update auth.users set banned_until = case when p_suspended then 'infinity'::timestamptz else null end where id = p_user;
  if p_suspended then
    delete from auth.sessions where user_id = p_user;
  end if;
end;
$$;

revoke execute on function public.admin_remove_reported(uuid) from public, anon;
revoke execute on function public.admin_set_suspended(uuid, boolean) from public, anon;
grant execute on function public.admin_reports(int) to authenticated;
grant execute on function public.admin_remove_reported(uuid) to authenticated;
grant execute on function public.admin_set_suspended(uuid, boolean) to authenticated;
