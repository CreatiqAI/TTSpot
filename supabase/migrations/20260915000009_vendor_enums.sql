-- Phase 3 (vendors): new notification types, in their own transaction.
alter type public.notification_type add value if not exists 'partner';   -- application decided / new application (admins)
alter type public.notification_type add value if not exists 'voucher';   -- claim / redemption
