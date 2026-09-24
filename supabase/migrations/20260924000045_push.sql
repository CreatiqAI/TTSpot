-- Push notifications. Phones register FCM tokens; every new notification row
-- and chat message pings the `push` Edge Function through pg_net, which works
-- out the recipients, respects Settings toggles / mutes / blocks, and sends via
-- Firebase Cloud Messaging.
--
-- The hook reads two Vault secrets, created once outside this repo (it's public):
--   select vault.create_secret('<random>', 'push_hook_secret');
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/push', 'push_hook_url');
-- and the function gets the same value as PUSH_HOOK_SECRET. Without them the
-- hook does nothing, so inserts never depend on push being set up.

create extension if not exists pg_net;

create table if not exists public.push_tokens (
  token       text primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  platform    text not null check (platform in ('ios', 'android')),
  updated_at  timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
create policy "push_tokens: read own" on public.push_tokens for select to authenticated using (user_id = auth.uid());

-- A phone that switches accounts keeps its token, so registering moves it over.
create or replace function public.register_push_token(p_token text, p_platform text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  insert into public.push_tokens (token, user_id, platform) values (p_token, auth.uid(), p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end;
$$;

create or replace function public.unregister_push_token(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from public.push_tokens where token = p_token and user_id = auth.uid();
$$;

revoke execute on function public.register_push_token(text, text) from public, anon;
revoke execute on function public.unregister_push_token(text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

create or replace function public.push_hook() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
  v_url text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_hook_secret';
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'push_hook_url';
  if v_secret is null or v_url is null then return new; end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('table', tg_table_name, 'id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  return new; -- push must never block a message or a notification
end;
$$;
revoke execute on function public.push_hook() from public, anon, authenticated;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push after insert on public.notifications for each row execute function public.push_hook();
drop trigger if exists messages_push on public.messages;
create trigger messages_push after insert on public.messages for each row execute function public.push_hook();
