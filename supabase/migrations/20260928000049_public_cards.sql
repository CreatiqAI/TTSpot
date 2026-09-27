-- Anyone signed in can see how many of each card a member holds (counts only,
-- never the card ids), so the profile Cards tab works for strangers too and
-- makes "ask them for a trade" obvious.
create or replace function public.public_cards(p_user uuid)
returns table (card_id text, held int)
language sql stable security definer set search_path = public as $$
  select uc.card_id, count(*)::int
  from public.user_cards uc
  where uc.user_id = p_user and uc.status = 'held' and auth.uid() is not null
  group by uc.card_id;
$$;
