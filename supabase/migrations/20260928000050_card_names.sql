-- Series 01–06 art landed (TiTi the cone). Names, taglines and tints now match
-- the posters; the art itself ships inside the app (assets/cards/c<n>.jpg) so
-- art_url stays null unless an admin overrides it. Series 07 (legendary) is
-- still a placeholder until its design arrives.
update public.card_types set name = 'Welcoming Friends',   description = 'Find your circle.',                    color = '#E00008' where id = 'c1';
update public.card_types set name = 'Offering Blessings',  description = 'Good people. Great journeys.',        color = '#F25C5C' where id = 'c2';
update public.card_types set name = 'Striking Poses',      description = 'Same TiTi. Different vibes.',         color = '#7C5CE6' where id = 'c3';
update public.card_types set name = 'Taking Photos',       description = 'Find the spot. Capture the moment.',  color = '#2B9BFF' where id = 'c4';
update public.card_types set name = 'Waiting for the Meet', description = 'Good cars. Greater company.',        color = '#B98B5E' where id = 'c5';
update public.card_types set name = 'Helping on the Road', description = 'Safer drives. Brighter journeys.',    color = '#3CB393' where id = 'c6';
update public.card_types set name = 'Legendary TiTi',      description = 'The rarest TiTi of all. Design coming soon.', color = '#F5B301' where id = 'c7';
