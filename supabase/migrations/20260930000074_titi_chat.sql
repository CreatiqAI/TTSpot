-- =============================================================================
-- TiTi chat: the cone becomes an in-app assistant (supabase/functions/titi).
--
--   titi_messages(id, user_id, role, content, parts, usage, created_at)
--     One row per question and per answer. `content` is the answer as shown:
--     a line "---" starts a new bubble and [[meet:<id>]] / [[spot:<id>]] /
--     [[club:<id>]] / [[car:<id>]] mark where a card sits. `parts` holds the
--     real card data ({"cards": {"meet:<id>": {...}}, "chips": [...]}), `usage`
--     the model's token counts for that answer.
--     Members read their own chat, add their own questions and clear it.
--     Answers are written by the function with the service role, so nobody can
--     plant a fake TiTi reply (it would feed the model's history) or a fake
--     usage log.
--   titi_daily(user_id, day, messages, input_tokens, cached_tokens, output_tokens)
--     The daily limit and the cost log. `day` is the Malaysian date. Kept when a
--     chat is cleared, so clearing never resets the limit or hides the cost.
--   titi_take_turn(p_user, p_limit) returns int
--     Counts one question if the member is under today's limit: the new count,
--     or -1 when over it. Service role only (the function calls it).
--   titi_log_usage(p_user, p_input, p_cached, p_output)
--     Adds one answer's tokens to today's row. Service role only.
--   titi_usage_by_day (view)
--     For the owner in the SQL editor: members, questions and tokens per day.
-- =============================================================================

create table if not exists public.titi_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       text not null check (role in ('user', 'assistant')),
  content    text not null default '' check (char_length(content) <= 12000),
  parts      jsonb,
  usage      jsonb,
  created_at timestamptz not null default now()
);
create index if not exists titi_messages_user_idx on public.titi_messages (user_id, created_at desc);

alter table public.titi_messages enable row level security;

drop policy if exists "titi_messages: read own" on public.titi_messages;
drop policy if exists "titi_messages: ask" on public.titi_messages;
drop policy if exists "titi_messages: clear own" on public.titi_messages;
create policy "titi_messages: read own" on public.titi_messages for select to authenticated using (user_id = auth.uid());
-- Questions only; answers come from the function.
create policy "titi_messages: ask" on public.titi_messages for insert to authenticated
  with check (user_id = auth.uid() and role = 'user' and usage is null and parts is null and char_length(content) between 1 and 2000);
create policy "titi_messages: clear own" on public.titi_messages for delete to authenticated using (user_id = auth.uid());

-- This project still auto-grants new tables to anon and authenticated; RLS
-- already blocks the rest, but keep the grants to what the policies allow.
revoke all on public.titi_messages from anon, authenticated;
grant select, insert, delete on public.titi_messages to authenticated;
grant all on public.titi_messages to service_role;

-- ------------------------------------------------------------ daily limit ---

create table if not exists public.titi_daily (
  user_id       uuid not null references public.profiles (id) on delete cascade,
  day           date not null,
  messages      int not null default 0,
  input_tokens  bigint not null default 0,
  cached_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  primary key (user_id, day)
);
create index if not exists titi_daily_day_idx on public.titi_daily (day);

alter table public.titi_daily enable row level security;
drop policy if exists "titi_daily: read own" on public.titi_daily;
create policy "titi_daily: read own" on public.titi_daily for select to authenticated using (user_id = auth.uid());

revoke all on public.titi_daily from anon, authenticated;
grant select on public.titi_daily to authenticated;
grant all on public.titi_daily to service_role;

create or replace function public.titi_take_turn(p_user uuid, p_limit int) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_day date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_n   int;
begin
  insert into public.titi_daily as d (user_id, day, messages) values (p_user, v_day, 1)
  on conflict (user_id, day) do update set messages = d.messages + 1
    where d.messages < p_limit
  returning d.messages into v_n;
  return coalesce(v_n, -1);
end;
$$;

create or replace function public.titi_log_usage(p_user uuid, p_input bigint, p_cached bigint, p_output bigint) returns void
language sql security definer set search_path = public as $$
  insert into public.titi_daily as d (user_id, day, input_tokens, cached_tokens, output_tokens)
  values (p_user, (now() at time zone 'Asia/Kuala_Lumpur')::date, greatest(p_input, 0), greatest(p_cached, 0), greatest(p_output, 0))
  on conflict (user_id, day) do update set
    input_tokens  = d.input_tokens  + excluded.input_tokens,
    cached_tokens = d.cached_tokens + excluded.cached_tokens,
    output_tokens = d.output_tokens + excluded.output_tokens;
$$;

revoke all on function public.titi_take_turn(uuid, int) from public, anon, authenticated;
revoke all on function public.titi_log_usage(uuid, bigint, bigint, bigint) from public, anon, authenticated;
grant execute on function public.titi_take_turn(uuid, int) to service_role;
grant execute on function public.titi_log_usage(uuid, bigint, bigint, bigint) to service_role;

-- ------------------------------------------------------------ owner's view ---

create or replace view public.titi_usage_by_day
with (security_invoker = true) as
select day,
       count(*)::int          as members,
       sum(messages)::int     as questions,
       sum(input_tokens)      as input_tokens,
       sum(cached_tokens)     as cached_tokens,
       sum(output_tokens)     as output_tokens
from public.titi_daily
group by day
order by day desc;

revoke all on public.titi_usage_by_day from public, anon, authenticated;
grant select on public.titi_usage_by_day to service_role;
