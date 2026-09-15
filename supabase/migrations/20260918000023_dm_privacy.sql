-- "Who can message me": friends only, when the person set it in Settings.
create or replace function public.get_or_create_dm(p_other uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  conv uuid;
begin
  if me is null or p_other is null or me = p_other then
    raise exception 'invalid participants';
  end if;
  if exists (select 1 from public.blocks b where (b.blocker_id = p_other and b.blocked_id = me)) then
    raise exception 'You cannot message this person';
  end if;
  if coalesce((select p.settings->>'dm_from' from public.profiles p where p.id = p_other), 'everyone') = 'friends'
     and not public.is_friend(me, p_other) then
    raise exception 'This person only takes messages from friends';
  end if;
  select c.id into conv
  from public.conversations c
  where c.kind = 'dm'
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = me)
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = p_other)
  limit 1;
  if conv is null then
    insert into public.conversations (kind) values ('dm') returning id into conv;
    insert into public.conversation_members (conversation_id, user_id) values (conv, me), (conv, p_other);
  end if;
  return conv;
end;
$$;
