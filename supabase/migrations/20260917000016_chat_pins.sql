-- =============================================================================
-- Chats: pin up to 3 conversations, and "delete" a chat for yourself (it is
-- hidden until someone writes in it again).
-- =============================================================================
alter table public.conversation_members
  add column pinned_at timestamptz,
  add column hidden_at timestamptz;

create or replace function public.set_conversation_pin(p_conversation uuid, p_pin boolean) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_pin then
    select count(*) into n from public.conversation_members where user_id = auth.uid() and pinned_at is not null and conversation_id <> p_conversation;
    if n >= 3 then raise exception 'You can pin up to 3 chats'; end if;
  end if;
  update public.conversation_members set pinned_at = case when p_pin then now() else null end
  where conversation_id = p_conversation and user_id = auth.uid();
end;
$$;

create or replace function public.hide_conversation(p_conversation uuid) returns void
language sql security definer set search_path = public as $$
  update public.conversation_members set hidden_at = now(), pinned_at = null
  where conversation_id = p_conversation and user_id = auth.uid();
$$;
