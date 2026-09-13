-- Enum values must land in their own transaction before anything uses them.
alter type public.notification_type add value if not exists 'referral';
alter type public.notification_type add value if not exists 'points';
