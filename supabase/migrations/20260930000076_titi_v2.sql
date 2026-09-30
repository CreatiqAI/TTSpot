-- =============================================================================
-- TiTi v2: separate chats, photos, and action cards.
--
--   titi_sessions(id, user_id, title, created_at, updated_at)
--     One chat with TiTi. The member keeps a list of past chats and starts new
--     ones. The function creates a chat on the first question of a new one and
--     titles it after the first answer; members may rename or delete their own.
--     updated_at follows the latest message (trigger).
--   titi_messages.session_id
--     Every message belongs to a chat. What is already there moves into one
--     chat per member. A question saved without one (the 0.3.42 app talks to
--     the function without chats) lands in the member's latest chat, or a new
--     one (trigger), so older builds keep working.
--   Questions may carry photos: parts = {"images": ["<uid>/<file>.jpg", ...]},
--     1-4 files, only from the member's own folder of titi-uploads. A question
--     with photos may have no text.
--   Answers may carry action cards: parts.actions[<uuid>] = {kind, label,
--     title, ..., status}. TiTi only proposes; the app does the action when the
--     member taps, then titi_action_status() stamps it "done" (or "dismissed")
--     so the card reloads that way. Answers stay function-only (service role).
--   storage bucket titi-uploads: PRIVATE. Members read, add and delete files in
--     their own <uid>/ folder only. The function signs short-lived URLs as the
--     member so the model can see the photo; nobody else ever can.
--   The daily limit (titi_daily) stays per member, across all chats.
-- Safe to re-run.
-- =============================================================================

create table if not exists public.titi_sessions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  title      text check (title is null or char_length(title) <= 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists titi_sessions_user_idx on public.titi_sessions (user_id, updated_at desc);

alter table public.titi_sessions enable row level security;
drop policy if exists "titi_sessions: read own" on public.titi_sessions;
drop policy if exists "titi_sessions: start own" on public.titi_sessions;
drop policy if exists "titi_sessions: rename own" on public.titi_sessions;
drop policy if exists "titi_sessions: delete own" on public.titi_sessions;
create policy "titi_sessions: read own" on public.titi_sessions for select to authenticated using (user_id = auth.uid());
create policy "titi_sessions: start own" on public.titi_sessions for insert to authenticated with check (user_id = auth.uid());
create policy "titi_sessions: rename own" on public.titi_sessions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "titi_sessions: delete own" on public.titi_sessions for delete to authenticated using (user_id = auth.uid());

revoke all on public.titi_sessions from anon, authenticated;
grant select, insert, delete on public.titi_sessions to authenticated;
grant update (title) on public.titi_sessions to authenticated;
grant all on public.titi_sessions to service_role;

-- ---------------------------------------------------- messages → chats ---

alter table public.titi_messages add column if not exists session_id uuid references public.titi_sessions (id) on delete cascade;
create index if not exists titi_messages_session_idx on public.titi_messages (session_id, created_at desc);

-- One chat per member for the messages already there, titled with their
-- first question.
insert into public.titi_sessions (user_id, title, created_at, updated_at)
select m.user_id,
       (select case when char_length(q) > 40 then rtrim(left(q, 39)) || '…' else nullif(q, '') end
          from (select regexp_replace(trim(f.content), '\s+', ' ', 'g') as q
                  from public.titi_messages f
                 where f.user_id = m.user_id and f.role = 'user'
                 order by f.created_at limit 1) x),
       min(m.created_at), max(m.created_at)
from public.titi_messages m
where m.session_id is null
  and not exists (select 1 from public.titi_sessions s where s.user_id = m.user_id)
group by m.user_id;

update public.titi_messages m
   set session_id = (select s.id from public.titi_sessions s where s.user_id = m.user_id order by s.updated_at desc limit 1)
 where m.session_id is null;

-- A message without a chat joins the member's latest chat (or starts one).
create or replace function public.titi_messages_session() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.session_id is null then
    select s.id into new.session_id from public.titi_sessions s
     where s.user_id = new.user_id order by s.updated_at desc limit 1;
    if new.session_id is null then
      insert into public.titi_sessions (user_id) values (new.user_id) returning id into new.session_id;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists titi_messages_session on public.titi_messages;
create trigger titi_messages_session before insert on public.titi_messages
  for each row execute function public.titi_messages_session();

alter table public.titi_messages alter column session_id set not null;

-- The chat list is ordered by the latest message.
create or replace function public.titi_touch_session() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.titi_sessions set updated_at = greatest(updated_at, new.created_at) where id = new.session_id;
  return null;
end;
$$;
drop trigger if exists titi_touch_session on public.titi_messages;
create trigger titi_touch_session after insert on public.titi_messages
  for each row execute function public.titi_touch_session();

revoke execute on function public.titi_messages_session() from public, anon, authenticated;
revoke execute on function public.titi_touch_session() from public, anon, authenticated;

-- ------------------------------------------------------- questions ---

-- A question is text (1-2000 characters), or 1-4 photos from the member's own
-- folder with up to 2000 characters of text. Nothing else goes in parts.
create or replace function public.titi_question_ok(p_content text, p_parts jsonb) returns boolean
language sql stable set search_path = public as $$
  select case
    when p_parts is null then char_length(p_content) between 1 and 2000
    else jsonb_typeof(p_parts) = 'object'
     and (p_parts - 'images') = '{}'::jsonb
     and jsonb_typeof(p_parts -> 'images') = 'array'
     and jsonb_array_length(p_parts -> 'images') between 1 and 4
     and char_length(p_content) <= 2000
     and not exists (
       select 1 from jsonb_array_elements(p_parts -> 'images') e
        where jsonb_typeof(e) <> 'string'
           or (e #>> '{}') !~ ('^' || auth.uid()::text || '/[A-Za-z0-9_.-]{1,80}$')
           or (e #>> '{}') like '%..%')
  end;
$$;
revoke execute on function public.titi_question_ok(text, jsonb) from public, anon;
grant execute on function public.titi_question_ok(text, jsonb) to authenticated;

drop policy if exists "titi_messages: ask" on public.titi_messages;
create policy "titi_messages: ask" on public.titi_messages for insert to authenticated
  with check (
    user_id = auth.uid() and role = 'user' and usage is null
    and exists (select 1 from public.titi_sessions s where s.id = session_id and s.user_id = auth.uid())
    and public.titi_question_ok(content, parts)
  );

-- ---------------------------------------------------------- actions ---

-- The member tapped an action card (done) or waved it off (dismissed).
-- [p_route]: where the card leads afterwards, e.g. a claimed voucher's QR.
-- False when no answer of mine has that card (yet: the answer is saved a
-- moment after it finishes streaming).
create or replace function public.titi_action_status(p_action text, p_status text, p_route text default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_n int;
  v_set jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if p_status not in ('done', 'dismissed') then raise exception 'Unknown status'; end if;
  if p_action !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'Unknown action'; end if;
  if p_route is not null and p_route !~ '^/[A-Za-z0-9/_?=&.-]{1,120}$' then raise exception 'Bad route'; end if;
  v_set := jsonb_build_object('status', p_status, 'at', now());
  if p_route is not null then v_set := v_set || jsonb_build_object('result_route', p_route); end if;
  update public.titi_messages m
     set parts = jsonb_set(m.parts, array['actions', p_action], (m.parts -> 'actions' -> p_action) || v_set)
   where m.user_id = auth.uid() and m.role = 'assistant' and m.parts -> 'actions' ? p_action;
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$$;
revoke execute on function public.titi_action_status(text, text, text) from public, anon;
grant execute on function public.titi_action_status(text, text, text) to authenticated;

-- ---------------------------------------------------------- photos ---

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('titi-uploads', 'titi-uploads', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "titi-uploads: owner read" on storage.objects;
create policy "titi-uploads: owner read" on storage.objects for select to authenticated
  using (bucket_id = 'titi-uploads' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "titi-uploads: owner upload" on storage.objects;
create policy "titi-uploads: owner upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'titi-uploads' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "titi-uploads: owner delete" on storage.objects;
create policy "titi-uploads: owner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'titi-uploads' and (storage.foldername(name))[1] = auth.uid()::text);
