-- Phase 4: club invites need their own notification type (separate transaction).
alter type public.notification_type add value if not exists 'club_invite';
