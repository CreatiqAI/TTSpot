-- Nicknames (备注): a private name a member gives someone else, like WeChat's
-- remark. Only the owner ever sees it: in their chat list, chat header, friends,
-- profile pages, and as the title of push notifications from that person (the
-- `push` Edge Function reads it with the service role).

create table if not exists public.contact_nicknames (
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  target_id   uuid not null references public.profiles (id) on delete cascade,
  nickname    text not null check (char_length(btrim(nickname)) between 1 and 40),
  updated_at  timestamptz not null default now(),
  primary key (owner_id, target_id),
  check (owner_id <> target_id)
);

alter table public.contact_nicknames enable row level security;

drop policy if exists "contact_nicknames: owner reads" on public.contact_nicknames;
drop policy if exists "contact_nicknames: owner adds" on public.contact_nicknames;
drop policy if exists "contact_nicknames: owner edits" on public.contact_nicknames;
drop policy if exists "contact_nicknames: owner removes" on public.contact_nicknames;
create policy "contact_nicknames: owner reads" on public.contact_nicknames for select to authenticated
  using (owner_id = auth.uid());
create policy "contact_nicknames: owner adds" on public.contact_nicknames for insert to authenticated
  with check (owner_id = auth.uid());
create policy "contact_nicknames: owner edits" on public.contact_nicknames for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "contact_nicknames: owner removes" on public.contact_nicknames for delete to authenticated
  using (owner_id = auth.uid());

revoke all on public.contact_nicknames from anon;
grant select, insert, update, delete on public.contact_nicknames to authenticated;
grant all on public.contact_nicknames to service_role;

-- Sets (or, with null / blank, clears) my nickname for p_target. Returns the
-- saved nickname, or null when it was cleared.
create or replace function public.set_contact_nickname(p_target uuid, p_nickname text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_name text := nullif(btrim(coalesce(p_nickname, '')), '');
begin
  if v_me is null then raise exception 'Sign in first'; end if;
  if p_target is null or p_target = v_me then raise exception 'Pick someone else'; end if;
  if v_name is null then
    delete from public.contact_nicknames where owner_id = v_me and target_id = p_target;
    return null;
  end if;
  if char_length(v_name) > 40 then raise exception 'Keep the nickname to 40 characters'; end if;
  if not exists (select 1 from public.profiles where id = p_target) then raise exception 'That member is gone'; end if;
  insert into public.contact_nicknames (owner_id, target_id, nickname)
  values (v_me, p_target, v_name)
  on conflict (owner_id, target_id) do update set nickname = excluded.nickname, updated_at = now();
  return v_name;
end;
$$;

-- Every nickname I've set, for the app's name lookups.
create or replace function public.my_contact_nicknames() returns table (target_id uuid, nickname text)
language sql stable security definer set search_path = public as $$
  select n.target_id, n.nickname from public.contact_nicknames n where n.owner_id = auth.uid();
$$;

revoke execute on function public.set_contact_nickname(uuid, text) from public, anon;
revoke execute on function public.my_contact_nicknames() from public, anon;
grant execute on function public.set_contact_nickname(uuid, text) to authenticated;
grant execute on function public.my_contact_nicknames() to authenticated;

-- ------------------------------------------------------ push capability ---
-- Android builds from this release draw chat pushes themselves (a
-- conversation with the sender's avatar), so the `push` function sends them
-- data-only. Older installs would show nothing for a data-only push, so a
-- phone opts in after registering its token; until then it keeps getting the
-- standard notification.
alter table public.push_tokens add column if not exists native_chat boolean not null default false;

create or replace function public.mark_push_token_native_chat(p_token text) returns void
language sql security definer set search_path = public as $$
  update public.push_tokens set native_chat = true, updated_at = now()
  where token = p_token and user_id = auth.uid();
$$;
revoke execute on function public.mark_push_token_native_chat(text) from public, anon;
grant execute on function public.mark_push_token_native_chat(text) to authenticated;
