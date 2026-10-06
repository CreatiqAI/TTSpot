-- 0112 drop_president_bonus: the official-club president no longer earns a
-- bonus when members check in at the club's meets (owner decision
-- 2026-10-06; after the points restructure it was 1 point a check-in).
-- Past bonus rows stay in the ledger; the rule is kept, inactive, so its
-- history still has a label.

create or replace function public.on_checkin_points()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_pts int := public.rule_points('meet_checkin');
begin
  perform public.award_points(new.user_id, v_pts, 'meet_checkin', 'event', new.event_id::text, null, 'meet_checkin:' || new.event_id || ':' || new.user_id);
  perform public.settle_referral(new.user_id);
  return new;
end;
$function$;

update public.point_rules set points = 0, active = false where reason = 'club_president_bonus';
