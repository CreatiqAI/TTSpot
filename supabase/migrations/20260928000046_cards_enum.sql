-- Blind box cards: one notification kind for trades and prize redemptions.
-- (enum values must be added in their own transaction before they are used)
alter type public.notification_type add value if not exists 'cards';
