-- Existing public names that the name filter (20261009000128) would refuse
-- if they were typed today. Run after the migration (or with it, --tx).
-- Nothing is changed: the triggers only check new or changed values.
select * from (
  select 'profiles.username' as col, id::text as row_id, username::text as value, public.name_problem(username::text, 'handle') as reason from public.profiles
  union all
  select 'profiles.display_name', id::text, display_name, public.name_problem(display_name, 'name') from public.profiles
  union all
  select 'clubs.name', id::text, name, public.name_problem(name, 'name') from public.clubs
  union all
  select 'clubs.handle', id::text, handle::text, public.name_problem(handle::text, 'handle') from public.clubs
  union all
  select 'conversations.title', id::text, title, public.name_problem(title, 'title') from public.conversations where kind = 'group'
  union all
  select 'events.title', id::text, title, public.name_problem(title, 'title') from public.events
  union all
  select 'partner_applications.business_name', id::text, business_name, public.name_problem(business_name, 'title') from public.partner_applications
) r
where reason is not null
order by col, value;
