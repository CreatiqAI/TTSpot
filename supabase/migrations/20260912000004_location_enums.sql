-- New notification types for the location layer. Kept in its own migration
-- because Postgres refuses to *use* a new enum value in the same transaction
-- that added it.
alter type public.notification_type add value if not exists 'friend_request';
alter type public.notification_type add value if not exists 'friend_accepted';
alter type public.notification_type add value if not exists 'tt_now';
alter type public.notification_type add value if not exists 'checkin';
