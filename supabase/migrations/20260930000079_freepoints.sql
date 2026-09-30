-- Points handed out by the TT Spot team (the admin "Give points" tool and
-- one-off gifts). A rule row so the member's history reads "Free points".
insert into public.point_rules (reason, points, label, description, sort)
values ('freepoints', 0, 'Free points', 'A gift from the TT Spot team.', 800)
on conflict (reason) do update set label = excluded.label, description = excluded.description;
