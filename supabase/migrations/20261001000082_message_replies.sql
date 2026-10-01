-- =============================================================================
-- Chat replies and voice-note waveforms.
--   * messages.reply_to   = the message this one quotes. Must be in the same
--                           conversation; cleared when the original is deleted.
--   * messages.audio_wave = the voice note's loudness as ~50 bars of 0..100,
--                           drawn in the playback bubble.
-- Messages have no update policy, so both are set once, at insert.
-- =============================================================================

alter table public.messages
  add column if not exists reply_to   uuid references public.messages (id) on delete set null,
  add column if not exists audio_wave smallint[];

-- Deleting a message nulls its replies' reply_to; index it so that's a lookup.
create index if not exists messages_reply_to_idx on public.messages (reply_to) where reply_to is not null;

alter table public.messages drop constraint if exists messages_audio_wave_check;
alter table public.messages add constraint messages_audio_wave_check check (
  audio_wave is null
  or (
    cardinality(audio_wave) between 1 and 120
    and array_position(audio_wave, null) is null
    and 0 <= all (audio_wave)
    and 100 >= all (audio_wave)
  )
);

-- A reply must quote a message from the same chat. Runs as the sender, so
-- the original also has to be one they can read.
create or replace function public.check_message_reply() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if new.reply_to is null then return new; end if;
  if new.reply_to = new.id or not exists (
    select 1 from public.messages m where m.id = new.reply_to and m.conversation_id = new.conversation_id
  ) then
    raise exception 'You can only reply to a message in this chat';
  end if;
  return new;
end; $$;

drop trigger if exists messages_check_reply on public.messages;
create trigger messages_check_reply
  before insert or update of reply_to, conversation_id on public.messages
  for each row execute function public.check_message_reply();
