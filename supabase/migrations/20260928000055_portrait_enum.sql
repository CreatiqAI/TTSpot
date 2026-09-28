-- AI car portraits: one notification kind for "your portrait is ready".
-- (enum values must be added in their own transaction before they are used)
alter type public.notification_type add value if not exists 'portrait';
