-- A friend request that goes away without being accepted (declined with
-- respond_friend_request(…, false), or cancelled by the sender through
-- remove_friend) now takes its "wants to be friends" notification with it,
-- the way an accepted one already does (on_friendship_accept). Before this a
-- declined request stayed in Activity with a live Accept button that did
-- nothing. Rows already left behind are not touched.
create or replace function public.on_friendship_delete() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'pending' then
    delete from public.notifications
    where type = 'friend_request' and user_id = old.addressee_id and actor_id = old.requester_id;
  end if;
  return old;
end; $$;

drop trigger if exists friendships_after_delete on public.friendships;
create trigger friendships_after_delete after delete on public.friendships
  for each row execute function public.on_friendship_delete();
