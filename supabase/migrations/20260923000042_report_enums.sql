-- Report targets for everything members can post (App Store guideline 1.2).
-- Enum values must be committed before use, so they get their own migration.
alter type public.report_target add value if not exists 'post';
alter type public.report_target add value if not exists 'post_comment';
alter type public.report_target add value if not exists 'message';
alter type public.report_target add value if not exists 'story';
alter type public.report_target add value if not exists 'club';
