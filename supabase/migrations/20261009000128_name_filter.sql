-- Name filter: members can't pick rude, hateful or impersonating names.
--
-- Covers every public name a member chooses:
--   profiles.username (handle) and profiles.display_name,
--   clubs.name and clubs.handle,
--   conversations.title (friends' groups only),
--   events.title,
--   partner_applications.business_name (partner and organizer applications).
-- Private contact nicknames only show to their owner, so they are left alone.
--
-- 1. public.blocked_terms: the list. Admins manage it; nobody else can read
--    it (the checker is security definer). Terms are stored normalised
--    (lowercase, no spaces, dots, underscores or dashes).
-- 2. public.name_problem(text, kind): null when the name is fine, else a
--    short reason. Kinds: 'handle' (usernames, club handles), 'name'
--    (display names, club names) and 'title' (group, event and business
--    names: no reserved-name check, so "Official launch" or "Police Day"
--    events still work).
--    Matching, on lowercase text with common leetspeak mapped
--    (0>o 1>i or l 3>e 4>a 5>s 7>t @>a $>s !>i), each form also tried with
--    repeated letters collapsed ("fuuuck"):
--      word      = a whole token, or the whole name once spaces and
--                  punctuation are gone ("s.h.i.t"). "Sussex", "Dickson",
--                  "Assam" and "Cocktail" pass.
--      substring = anywhere in the name with spaces and punctuation gone.
--                  Only long, unambiguous terms.
--      reserved  = (handle / name only) the whole name, its first token
--                  ("ttspot_official", "admin kumar"), the first token
--                  followed by digits ("admin123"), or, for terms of 6+
--                  letters, any start ("ttspotofficial"). Short ones need a
--                  break, so "polished", "modified" and "titiwangsa" pass.
-- 3. public.check_name(text, kind): the same answer for the app to show
--    while the member types (anon too: sign-up comes before onboarding).
--    Only ever returns the reason, never the matched term. Admins get null.
-- 4. BEFORE INSERT/UPDATE triggers raise the reason when the value changes.
--    Admins and SQL / the service role (auth.uid() is null) are exempt, so
--    the official @titi and @ttspot accounts can be set. Rows whose name
--    doesn't change are never checked, so old names don't block edits.

-- 1. The list ----------------------------------------------------------------

create table if not exists public.blocked_terms (
  term text primary key,
  kind text not null check (kind in ('word', 'substring', 'reserved'))
);

comment on table public.blocked_terms is
  'Terms members can''t use in public names. word = whole token, substring = anywhere (long, unambiguous terms only), reserved = handle/name start. Stored lowercase without spaces, dots, underscores or dashes.';

alter table public.blocked_terms enable row level security;

drop policy if exists "blocked_terms: admins" on public.blocked_terms;
create policy "blocked_terms: admins" on public.blocked_terms
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

revoke all on public.blocked_terms from anon;

-- Keep terms in the same shape the checker compares against.
create or replace function public.blocked_terms_normalise()
returns trigger
language plpgsql
set search_path = public
as $fn$
begin
  new.term := lower(regexp_replace(btrim(new.term), '[[:space:]._-]+', '', 'g'));
  if new.term = '' then raise exception 'Term is empty'; end if;
  return new;
end;
$fn$;

drop trigger if exists blocked_terms_normalise on public.blocked_terms;
create trigger blocked_terms_normalise
  before insert or update on public.blocked_terms
  for each row execute function public.blocked_terms_normalise();

-- Seed. Short on purpose, so normal names don't trip it.
insert into public.blocked_terms (term, kind) values
  -- English profanity and insults
  ('fuck', 'substring'), ('motherfucker', 'substring'), ('fuk', 'word'), ('fck', 'word'),
  ('fuq', 'word'), ('stfu', 'word'), ('shit', 'word'), ('shits', 'word'), ('shitty', 'word'),
  ('shithead', 'substring'), ('bullshit', 'substring'), ('bitch', 'substring'),
  ('bastard', 'substring'), ('asshole', 'substring'), ('jackass', 'substring'),
  ('dumbass', 'substring'), ('ass', 'word'), ('arse', 'word'), ('cunt', 'word'),
  ('twat', 'word'), ('wanker', 'substring'), ('dick', 'word'), ('dickhead', 'substring'),
  ('cock', 'word'), ('cocksucker', 'substring'), ('prick', 'word'), ('piss', 'word'),
  ('pissoff', 'substring'), ('retard', 'word'), ('retarded', 'word'), ('kys', 'word'),
  -- English sexual terms
  ('sex', 'word'), ('porn', 'word'), ('porno', 'word'), ('pornstar', 'substring'),
  ('pornhub', 'substring'), ('xxx', 'word'), ('pussy', 'word'),
  ('slut', 'word'), ('whore', 'substring'), ('nude', 'word'), ('nudes', 'word'),
  ('naked', 'word'), ('boob', 'word'), ('boobs', 'word'), ('tits', 'word'),
  ('titties', 'substring'), ('penis', 'word'), ('vagina', 'substring'), ('horny', 'word'),
  ('milf', 'word'), ('dildo', 'substring'), ('blowjob', 'substring'), ('handjob', 'substring'),
  ('cum', 'word'), ('jizz', 'substring'), ('orgasm', 'substring'), ('anal', 'word'),
  ('anus', 'word'), ('fap', 'word'), ('hentai', 'substring'), ('onlyfans', 'substring'),
  ('rape', 'word'), ('rapist', 'word'), ('pedo', 'word'), ('paedo', 'word'),
  ('pedophile', 'substring'),
  -- Malay profanity and insults
  ('babi', 'word'), ('puki', 'word'), ('pukimak', 'substring'), ('pukimakkau', 'substring'),
  ('sial', 'word'), ('sialan', 'word'), ('bangsat', 'substring'), ('butoh', 'word'),
  ('pantat', 'substring'), ('kote', 'word'), ('kotek', 'word'), ('pepek', 'word'),
  ('haramjadah', 'substring'), ('sundal', 'word'),
  ('jalang', 'word'), ('pelacur', 'substring'), ('bodoh', 'word'), ('bangang', 'word'),
  ('lahanat', 'substring'), ('jubur', 'word'), ('kepalabapak', 'substring'),
  ('kepalabapakkau', 'substring'),
  -- Hokkien / Cantonese / Tamil romanised profanity used in Malaysia
  ('cibai', 'substring'), ('chibai', 'substring'), ('cheebai', 'substring'),
  ('cheebye', 'substring'), ('chibye', 'substring'), ('cb', 'word'), ('knn', 'word'),
  ('kanina', 'substring'), ('kannina', 'substring'), ('kaninabu', 'substring'),
  ('lanjiao', 'substring'), ('lanjiu', 'substring'), ('lanciao', 'substring'),
  ('lancau', 'substring'), ('diu', 'word'), ('diulei', 'substring'), ('diunei', 'substring'),
  ('pokgai', 'substring'), ('phokgai', 'substring'), ('pukkai', 'substring'),
  ('hamsap', 'substring'), ('hamsup', 'substring'), ('sohai', 'word'),
  ('pundek', 'substring'), ('punda', 'word'), ('thevidiya', 'substring'),
  ('thevdiya', 'substring'), ('ommala', 'substring'), ('koothi', 'substring'),
  -- Chinese characters (simplified and traditional)
  ('操', 'word'), ('操你', 'substring'), ('操他', 'substring'), ('操她', 'substring'),
  ('肏', 'substring'), ('屌', 'substring'), ('鸡巴', 'substring'), ('雞巴', 'substring'),
  ('婊', 'substring'), ('他妈的', 'substring'), ('他媽的', 'substring'),
  ('你妈的', 'substring'), ('你媽的', 'substring'), ('干你娘', 'substring'),
  ('幹你娘', 'substring'), ('傻逼', 'substring'), ('傻屄', 'substring'), ('屄', 'substring'),
  ('草泥马', 'substring'), ('王八蛋', 'substring'), ('狗娘养', 'substring'),
  ('狗娘養', 'substring'), ('贱人', 'substring'), ('賤人', 'substring'),
  ('骚货', 'substring'), ('騷貨', 'substring'), ('仆街', 'substring'), ('撲街', 'substring'),
  ('閪', 'substring'), ('冚家铲', 'substring'), ('冚家鏟', 'substring'),
  -- Racial slurs
  ('keling', 'word'), ('kling', 'word'), ('tongsan', 'word'), ('nigger', 'substring'),
  ('nigga', 'substring'), ('negro', 'word'), ('chink', 'word'), ('gook', 'word'),
  ('paki', 'word'), ('kafir', 'word'), ('coon', 'word'), ('faggot', 'substring'),
  ('fag', 'word'),
  -- Hate and extremism
  ('nazi', 'word'), ('nazis', 'word'), ('hitler', 'substring'), ('isis', 'word'),
  ('heil', 'word'), ('kkk', 'word'), ('taliban', 'substring'), ('alqaeda', 'substring'),
  ('swastika', 'substring'), ('whitepower', 'substring'), ('terrorist', 'substring'),
  -- Drugs
  ('ganja', 'word'), ('syabu', 'substring'), ('meth', 'word'),
  ('cocaine', 'substring'), ('kokain', 'substring'), ('heroin', 'word'),
  ('ketamine', 'substring'), ('marijuana', 'substring'), ('mdma', 'word'),
  ('pilkuda', 'substring'),
  -- Reserved: TT Spot, staff and authorities
  ('ttspot', 'reserved'), ('tt_spot', 'reserved'), ('titi', 'reserved'),
  ('admin', 'reserved'), ('administrator', 'reserved'), ('moderator', 'reserved'),
  ('mod', 'reserved'), ('support', 'reserved'), ('helpdesk', 'reserved'),
  ('customerservice', 'reserved'), ('official', 'reserved'), ('staff', 'reserved'),
  ('polis', 'reserved'), ('police', 'reserved'), ('pdrm', 'reserved'), ('jpj', 'reserved'),
  ('sultan', 'reserved'), ('agong', 'reserved'), ('agung', 'reserved'),
  ('kerajaan', 'reserved')
on conflict (term) do nothing;

-- 2. The checker --------------------------------------------------------------

create or replace function public.name_problem(p_text text, p_kind text default 'name')
returns text
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  c_bad constant text := 'That name isn''t allowed. Try another.';
  c_reserved constant text := 'That name is reserved.';
  v_kind text := case when p_kind in ('handle', 'name', 'title') then p_kind else 'name' end;
  v_low text := lower(btrim(coalesce(p_text, '')));
  v_leet text[];
  v_forms text[];
  v_form text;
  v_strip text;
  v_tokens text[];
  v_first text;
  v_first_raw text;
  v_term text;
  i int;
begin
  if v_low = '' then return null; end if;

  -- Leetspeak: 1 reads as i or l, so try both. @ $ ! become letters too.
  v_leet := array[translate(v_low, '013457@$!', 'oieastasi'),
                  translate(v_low, '013457@$!', 'oleastasi')];
  v_forms := v_leet
          || regexp_replace(v_leet[1], '(.)\1+', '\1', 'g')
          || regexp_replace(v_leet[2], '(.)\1+', '\1', 'g');

  -- Rude, sexual, hateful and drug terms.
  foreach v_form in array v_forms loop
    v_strip := regexp_replace(v_form, '[^[:alnum:]]+', '', 'g');
    v_tokens := array_remove(regexp_split_to_array(v_form, '[^[:alnum:]]+'), '');
    if exists (
      select 1 from public.blocked_terms b
      where (b.kind = 'substring' and strpos(v_strip, b.term) > 0)
         or (b.kind = 'word' and (b.term = any(v_tokens) or b.term = v_strip))
    ) then
      return c_bad;
    end if;
  end loop;

  if v_kind = 'title' then return null; end if;

  -- Reserved names: TT Spot, staff and authorities. Uses the leet forms
  -- without collapsing, so "ttspot" stays "ttspot". The raw first token keeps
  -- @ $ ! in place, so its positions line up with the leet form's.
  v_first_raw := (array_remove(regexp_split_to_array(v_low, '[^[:alnum:]@$!]+'), ''))[1];
  for i in 1 .. 2 loop
    v_strip := regexp_replace(v_leet[i], '[^[:alnum:]]+', '', 'g');
    v_first := (array_remove(regexp_split_to_array(v_leet[i], '[^[:alnum:]]+'), ''))[1];
    for v_term in select b.term from public.blocked_terms b where b.kind = 'reserved' loop
      if v_strip = v_term
         or v_first = v_term
         or (char_length(v_term) >= 6 and left(v_strip, char_length(v_term)) = v_term)
         or (left(v_first, char_length(v_term)) = v_term
             and substr(v_first_raw, char_length(v_term) + 1) ~ '^[0-9]+$') then
        return c_reserved;
      end if;
    end loop;
  end loop;

  return null;
end;
$fn$;

revoke all on function public.name_problem(text, text) from public, anon, authenticated;

comment on function public.name_problem(text, text) is
  'Null when a public name is fine, else a short reason. Kinds: handle, name, title. Used by the name triggers and check_name.';

-- 3. For the app, while the member types ------------------------------------

create or replace function public.check_name(p_text text, p_kind text default 'name')
returns text
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if auth.uid() is not null and public.is_admin() then return null; end if;
  return public.name_problem(left(coalesce(p_text, ''), 200), p_kind);
end;
$fn$;

revoke all on function public.check_name(text, text) from public;
grant execute on function public.check_name(text, text) to anon, authenticated;

-- 4. The triggers -------------------------------------------------------------

-- Arguments come in pairs: column name, kind. Only a value that is new or
-- changed is checked.
create or replace function public.name_filter_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else null end;
  v_col text;
  v_val text;
  v_reason text;
  i int := 0;
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  while i < tg_nargs loop
    v_col := tg_argv[i];
    v_val := v_new ->> v_col;
    if v_val is not null
       and (tg_op = 'INSERT' or v_val is distinct from (v_old ->> v_col)) then
      v_reason := public.name_problem(v_val, tg_argv[i + 1]);
      if v_reason is not null then
        raise exception using message = v_reason, hint = 'name_filter';
      end if;
    end if;
    i := i + 2;
  end loop;
  return new;
end;
$fn$;

drop trigger if exists profiles_name_filter on public.profiles;
create trigger profiles_name_filter
  before insert or update of username, display_name on public.profiles
  for each row execute function public.name_filter_guard('username', 'handle', 'display_name', 'name');

drop trigger if exists clubs_name_filter on public.clubs;
create trigger clubs_name_filter
  before insert or update of name, handle on public.clubs
  for each row execute function public.name_filter_guard('name', 'name', 'handle', 'handle');

drop trigger if exists conversations_name_filter on public.conversations;
create trigger conversations_name_filter
  before insert or update of title on public.conversations
  for each row when (new.kind = 'group')
  execute function public.name_filter_guard('title', 'title');

drop trigger if exists events_name_filter on public.events;
create trigger events_name_filter
  before insert or update of title on public.events
  for each row execute function public.name_filter_guard('title', 'title');

drop trigger if exists partner_applications_name_filter on public.partner_applications;
create trigger partner_applications_name_filter
  before insert or update of business_name on public.partner_applications
  for each row execute function public.name_filter_guard('business_name', 'title');
