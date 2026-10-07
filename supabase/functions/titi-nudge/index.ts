// titi-nudge
// Proactive TiTi: up to THREE short messages a member a day, one in each
// window (Malaysia time), written by the TiTi model from the member's own
// context, saved into their TiTi chat and pushed with the title "TiTi"
// (notification type titi_nudge → /titi).
//
//   morning   08:00-12:00     afternoon 13:00-18:00     evening 19:00-23:00
//
// Each member gets a random time in each window (a hash of user id + day +
// window, rules.ts plan()), at least 3 h apart; nothing 23:00-08:00.
// Called by pg_cron (titi_nudge_post(), every 30 min 08:00-22:30 MYT) with the
// header x-titi-secret; each run sends to the members whose time has come.
// Deploy with --no-verify-jwt (config.toml).
//
// Who: titi_nudge_candidates(slot): "TiTi tips" on (profiles.settings.titi_tips),
// a push token, not suspended, nothing yet in this window today, fewer than 8
// pushes in the last 24 h. Off unless platform_settings.titi_nudges_enabled;
// at most titi_nudges_daily_budget a day across everyone; BATCH a run.
//
// What (rules.ts pickTrigger; never the same trigger twice in a day; the
// first that fits, else a fun line; never invented facts):
//   morning    weather (MET Malaysia warning, or today's MET forecast says
//              rain / storms / haze, ≤3 forecast lines a week) → a meet they
//              joined today → road tax / insurance due ≤7 days → a car fact
//   afternoon  meets / TT ≤15 km later today → friends out now → a MET storm
//              warning → Friday points reset → an unopened box → a car tip
//   evening    a meet live now ≤15 km (and how many are there) → Sunday's
//              weekly recap → a busy spot ≤15 km → a joke / quote
// The line never names their car's make, model or colour ("your car").
//
// Body (all optional; only for whoever holds the secret):
//   { dry_run: true, user_ids: [...] }   what it WOULD send; sends and logs nothing
//   { test_user: "<uuid>" }              a real send to that one member now, even
//                                        while the switch is off, outside their
//                                        random time and without a push token
//   now: ISO time                        (dry run / test) pretend it's this time
//   slot: 1 | 2 | 3                      (dry run / test) use this window
//   ctx: {...}                           (dry run) override parts of their context
//                                        (e.g. live, nearby, sent_today, week)
//   weather: {...} | null                (dry run) pretend this is their weather
//   force_trigger + facts                (dry run / test) use this trigger and these facts
//   history: ["…"]                       (dry run) pretend these were their recent TiTi messages
//   lang: "en"|"zh"|"ms"                 (dry run / test) override the language
//
// Secrets: TITI_NUDGE_SECRET (= Vault titi_nudge_secret), OPENAI_API_KEY,
// TITI_MODEL (default gpt-5.4-mini).
import { createClient } from "npm:@supabase/supabase-js@2";
import { detectLang, type Lang } from "../_shared/lang.ts";
import {
  type Clock, clock, cleanLine, type Ctx, due, type Forecast, forecastEn, hm, km, type Loc, MAX_CHARS, mytMs, normState, notable, type Pick, pickTrigger,
  plan, type Slot, templateLine, timeMyt, type Trigger, type Warning, warningCovers, type WeatherFacts, WINDOWS, windowAt,
} from "./rules.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const SECRET = Deno.env.get("TITI_NUDGE_SECRET") ?? "";
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY");
const MODEL = Deno.env.get("TITI_MODEL") ?? "gpt-5.4-mini";

// Members a run (the rest wait for the next run, 30 min later), and model
// calls at once. ~1-2 s a call: 120 members ≈ 30 s.
const BATCH = 120;
const PARALLEL = 8;
// gpt-5.4-mini list prices, USD per 1M tokens (input, cached input, output).
const PRICE = { input: 0.75, cached: 0.075, output: 4.5 };

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body, null, 1), { status, headers: { "content-type": "application/json" } });

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

class Weather {
  private locs: Promise<Loc[]> | null = null;
  private forecasts: Promise<Forecast[]> | null = null;
  private warnings: Promise<Warning[]> | null = null;
  constructor(private readonly today: string, private readonly nowMs: number) {}

  locations(): Promise<Loc[]> {
    return (this.locs ??= Promise.resolve(admin.from("weather_locations").select("id, name, kind, state, lat, lng")).then(({ data }) => (data ?? []) as Loc[]));
  }
  /** MET Malaysia's forecast for TODAY only (data.gov.my). When the feed has
   * no rows for today (it lagged a week on 7 Oct 2026), there's no forecast
   * line: warnings only. */
  today_(): Promise<Forecast[]> {
    return (this.forecasts ??= fetch(`https://api.data.gov.my/weather/forecast/?filter=${this.today}@date&limit=1000`, { signal: AbortSignal.timeout(15000) })
      .then((r) => (r.ok ? r.json() : []))
      .then((rows: Forecast[]) => (Array.isArray(rows) ? rows.filter((r) => r.date === this.today) : []))
      .catch(() => []));
  }
  /** MET Malaysia's live land warnings (thunderstorms / heavy rain), valid now. */
  live(): Promise<Warning[]> {
    return (this.warnings ??= fetch("https://api.data.gov.my/weather/warning/?limit=50", { signal: AbortSignal.timeout(15000) })
      .then((r) => (r.ok ? r.json() : []))
      .then((list: Warning[]) =>
        list.filter((w) => {
          const title = w.warning_issue?.title_en ?? "";
          if (!/thunderstorm|heavy rain|continuous rain/i.test(title) || /sea|water|cyclone/i.test(title)) return false;
          const from = mytMs(w.valid_from), to = mytMs(w.valid_to);
          return !Number.isNaN(to) && to > this.nowMs && (Number.isNaN(from) || from <= this.nowMs + 3600e3);
        })
      )
      .catch(() => []));
  }

  /** Today's weather where this member is: the nearest town to their last
   * position (≤40 km), else their home state's forecast. Null: nothing
   * worth saying (no warning, no rain / storms / haze). */
  async forMember(pos: { lat: number; lng: number } | null, homeState: string | null): Promise<WeatherFacts | null> {
    const [locs, rows, warns] = await Promise.all([this.locations(), this.today_(), this.live()]);
    const byId = new Map(rows.map((r) => [r.location.location_id, r]));
    let area: string | null = null, state = homeState, row: Forecast | undefined, places: string[] = [];
    if (pos) {
      const near = (kind: Loc["kind"]) => locs.filter((l) => l.kind === kind).map((l) => ({ l, d: km(pos, l) })).sort((a, b) => a.d - b.d)[0];
      const town = near("town"), district = near("district");
      if (town && town.d <= 40) {
        area = town.l.name;
        state = town.l.state ?? district?.l.state ?? homeState;
        row = byId.get(town.l.id) ?? (district ? byId.get(district.l.id) : undefined);
        places = [town.l.name, district?.l.name ?? ""];
      }
    }
    if (!area && homeState) {
      area = homeState;
      row = rows.find((r) => r.location.location_id.startsWith("St") && normState(r.location.location_name) === normState(homeState));
    }
    if (!area || !state) return null;
    const warning = warns.find((w) => warningCovers(w.text_en ?? "", state!, places));
    const morning = row && notable(row.morning_forecast) ? forecastEn(row.morning_forecast) : null;
    const afternoon = row && notable(row.afternoon_forecast) ? forecastEn(row.afternoon_forecast) : null;
    if (!warning && !morning && !afternoon) return null;
    return {
      area,
      morning,
      afternoon,
      warning: warning ? `MET Malaysia ${warning.warning_issue.title_en.toLowerCase()} for the area until ${timeMyt(new Date(mytMs(warning.valid_to)).toISOString())}` : null,
      temp: row ? `${row.min_temp}-${row.max_temp}°C` : null,
    };
  }
}

// ================================================================= writing ===

const LANG_NAME: Record<Lang, string> = {
  en: "English (casual, friendly; no Malay slang like 'lah' unless their own messages use it)",
  zh: "Simplified Chinese (casual, like a Malaysian Chinese friend texting)",
  ms: "Bahasa Melayu (santai, macam kawan WhatsApp)",
};

const INSTRUCTIONS = `You are TiTi, the orange traffic-cone mascot of TT Spot, a Malaysian car-community app, and the member's car soulmate: a warm, funny, caring buddy who loves their car as much as they do. Never official, never corporate, never salesy.

Write ONE push message to the member, from you. You text them up to three times a day (morning, afternoon, evening), so keep each one light and worth opening.
- ${MAX_CHARS} characters at most. One or two short sentences. Short beats clever.
- Plain text only. At most one emoji. No hashtags, no links, no quotes around it, no sign-off.
- Use ONLY the facts given. Never invent times, places, prices, numbers, weather, people or events. Leave out anything you aren't given.
- Never say or hint that you are an AI, a bot or an assistant.
- Lead with the news and keep its key detail (the time, the distance, how many, when it's due or resets, what to do). Keep meet, spot and place names exactly as given.
- Their car: never say its make, model, colour or year. Just "your car" or "your ride", and only when it fits.
- Usually skip their name; when you use it, never as the first word. Name friends only if they're given as friends.
- Fit the time of day given (a cheerful good morning, an easy evening tone), lightly.
- For a car fact, tip or joke: share the one given, keep its meaning and any numbers exactly, and add a small warm touch. Don't add facts of your own.
- Don't start the way your recent lines to them started.
- Warm and a little playful; caring advice when it helps (weather: umbrella, wipers, slow down on wet roads).
- Weather: a warning or storms / rain come first (say when: this morning, this afternoon); haze after. Credit MET when it's a warning.
- Write in the language given.

Examples of the voice (English):
MET says storms over PJ this afternoon ☔ grab an umbrella and go easy on the corners. Your ride wants to come home shiny.
Road tax for your car runs out in 3 days. Renew it tonight and drive easy 🙌
Morning! Fun fact: Lamborghini made tractors before supercars. Your car's family tree is wilder than you think 🚜
There's a TT session at Bangsar tonight at 9:30 PM, about 4 km from you. Worth a look? 🏁
A meet near you is live right now, 12 people checked in already 🔥
Weekly points reset at 6 PM today. One post before then and that +10 is yours ⭐`;

type Usage = { input: number; cached: number; output: number };
const costOf = (u: Usage) => ((u.input - u.cached) * PRICE.input + u.cached * PRICE.cached + u.output * PRICE.output) / 1e6;

function factsText(c: Ctx, p: Pick, lang: Lang, history: string[], slot: Slot, now: Clock): string {
  const first = (c.name ?? "").trim().split(/\s+/)[0] || null;
  const lastLines = (c.nudges ?? []).slice(0, 4).map((n) => n.text ?? "").filter(Boolean);
  const recent = history.slice(-5).map((m) => m.replace(/\s+/g, " ").trim().slice(0, 100)).filter(Boolean);
  const day = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][now.weekday];
  return [
    `Language: ${LANG_NAME[lang]}`,
    `Time of day: ${WINDOWS[slot - 1].name}, ${day} ${hm(now.hour)} (Malaysia)`,
    `Member's first name: ${first ?? "unknown (don't use a name)"}`,
    `Why you're writing (${p.trigger}): ${JSON.stringify(p.facts)}`,
    lastLines.length ? `Your last lines to them (don't start the same way):\n${lastLines.map((t) => `- ${t}`).join("\n")}` : null,
    recent.length ? `Their last messages to you (context only, oldest first):\n${recent.map((m) => `- ${m}`).join("\n")}` : "They haven't chatted with you yet.",
  ].filter(Boolean).join("\n");
}

async function callModel(input: string, instructions: string): Promise<{ text: string; usage: Usage }> {
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, instructions, input, reasoning: { effort: "none" }, max_output_tokens: 150, store: false }),
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) throw new Error(`openai ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const j = await res.json();
  // deno-lint-ignore no-explicit-any
  const text = j.output_text ?? (j.output ?? []).flatMap((o: any) => o.content ?? []).filter((c: any) => c.type === "output_text").map((c: any) => c.text).join("");
  const u = j.usage ?? {};
  return { text: String(text ?? ""), usage: { input: u.input_tokens ?? 0, cached: u.input_tokens_details?.cached_tokens ?? 0, output: u.output_tokens ?? 0 } };
}

async function write(c: Ctx, p: Pick, lang: Lang, history: string[], slot: Slot, now: Clock): Promise<{ text: string; usage: Usage; fallback: boolean }> {
  const usage: Usage = { input: 0, cached: 0, output: 0 };
  const facts = factsText(c, p, lang, history, slot, now);
  // Numbers in the line must come from this message's facts (not old lines);
  // their car's make / model must not appear.
  const allowed = JSON.stringify(p.facts);
  const carWords = [c.car?.make ?? "", c.car?.model ?? ""];
  const add = (u: Usage) => {
    usage.input += u.input;
    usage.cached += u.cached;
    usage.output += u.output;
  };
  if (OPENAI_KEY) {
    try {
      const a = await callModel(facts, INSTRUCTIONS);
      add(a.usage);
      const ok = cleanLine(a.text, allowed, carWords);
      if (ok) return { text: ok, usage, fallback: false };
      // One retry, told why.
      const b = await callModel(`${facts}\n\nYour last try broke a rule (too long, a link or hashtag, a number not in the facts, or it named their car): "${a.text.slice(0, 300)}". Write it again, under 140 characters, saying "your car" if you mention it.`, INSTRUCTIONS);
      add(b.usage);
      const ok2 = cleanLine(b.text, allowed, carWords);
      if (ok2) return { text: ok2, usage, fallback: false };
    } catch (e) {
      console.error("titi-nudge model", String(e).slice(0, 300));
    }
  }
  return { text: templateLine(p, lang), usage, fallback: true };
}

// ================================================================ sending ===

const TITI_SESSION_TITLE = "TiTi";

async function deliver(userId: string, p: Pick, text: string, lang: Lang, usage: Usage, fallback: boolean, slot: Slot, day: string) {
  const cost = costOf(usage);
  // The claim first: unique (user_id, day, slot) stops a second run racing in.
  const { data: log, error: logErr } = await admin.from("titi_nudges").insert({
    user_id: userId, day, slot, trigger: p.trigger, ref: p.ref, text, lang, model: fallback && usage.output === 0 ? "template" : MODEL,
    input_tokens: usage.input, cached_tokens: usage.cached, output_tokens: usage.output, cost_usd: cost.toFixed(6), fallback,
  }).select("id").single();
  if (logErr || !log) return { sent: false, reason: logErr?.code === "23505" ? "already sent in this window" : `log: ${logErr?.message}` };

  // Into their latest TiTi chat (the one the app opens), else a new one.
  let sessionId = ((await admin.from("titi_sessions").select("id").eq("user_id", userId).order("updated_at", { ascending: false }).limit(1).maybeSingle()).data as { id: string } | null)?.id;
  if (!sessionId) {
    const { data } = await admin.from("titi_sessions").insert({ user_id: userId, title: TITI_SESSION_TITLE }).select("id").single();
    sessionId = (data as { id: string } | null)?.id;
  }
  const messageId = crypto.randomUUID();
  const { error: msgErr } = await admin.from("titi_messages").insert({
    id: messageId, user_id: userId, session_id: sessionId, role: "assistant", content: text,
    parts: { nudge: { trigger: p.trigger } },
    usage: { model: MODEL, nudge: true, input_tokens: usage.input, cached_tokens: usage.cached, output_tokens: usage.output, fallback },
  });
  if (msgErr) console.error("titi-nudge message", msgErr.message);

  // The notification row; its insert trigger hands it to `push`.
  const { data: note, error: noteErr } = await admin.from("notifications").insert({ user_id: userId, type: "titi_nudge", body: text }).select("id").single();
  if (noteErr) console.error("titi-nudge notification", noteErr.message);

  await admin.from("titi_nudges").update({ session_id: sessionId ?? null, message_id: msgErr ? null : messageId, notification_id: (note as { id: string } | null)?.id ?? null }).eq("id", (log as { id: string }).id);
  return { sent: true, nudge_id: (log as { id: string }).id, session_id: sessionId, message_id: msgErr ? null : messageId, notification_id: (note as { id: string } | null)?.id ?? null, cost_usd: cost };
}

async function pool<T, R>(items: T[], n: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) {
      const k = i++;
      out[k] = await fn(items[k]);
    }
  }));
  return out;
}

const setting = async (key: string) => ((await admin.from("platform_settings").select("value").eq("key", key).maybeSingle()).data as { value: unknown } | null)?.value;
const on = (v: unknown) => v === true || v === "true" || v === 1 || v === "on";

// ================================================================ handler ===

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!SECRET || !safeEqual(req.headers.get("x-titi-secret") ?? "", SECRET)) return json({ error: "forbidden" }, 403);
  // deno-lint-ignore no-explicit-any
  const body: any = await req.json().catch(() => ({}));
  const dry = body.dry_run === true;
  const UUID = /^[0-9a-f-]{36}$/i;
  const testUser: string | null = typeof body.test_user === "string" && UUID.test(body.test_user) ? body.test_user : null;
  const manual = dry || !!testUser;
  const now = clock(manual && typeof body.now === "string" && !Number.isNaN(Date.parse(body.now)) ? Date.parse(body.now) : Date.now());
  const myt = `${now.today} ${hm(now.hour)}`;

  if (!manual && !on(await setting("titi_nudges_enabled"))) return json({ skipped: "titi_nudges_enabled is off" });

  // Which window. Outside 08-12 / 13-18 / 19-23 MYT nothing is sent; a dry run
  // or a test may name the window instead.
  const forcedSlot: Slot | null = manual && [1, 2, 3].includes(body.slot) ? body.slot : null;
  const win = forcedSlot ? WINDOWS[forcedSlot - 1] : windowAt(now.hour);
  if (!win) return json({ skipped: "outside the windows (08-12, 13-18, 19-23 MYT)", myt });
  const slot = win.slot;

  // Who.
  let ids: string[];
  let dueInfo = new Map<string, number>();
  if (dry) ids = (Array.isArray(body.user_ids) ? body.user_ids : []).filter((x: unknown) => typeof x === "string" && UUID.test(x)).slice(0, 20);
  else if (testUser) ids = [testUser];
  else {
    const budget = Number(await setting("titi_nudges_daily_budget") ?? 900) || 0;
    const { data: used } = await admin.rpc("titi_nudges_today");
    const left = budget - Number(used ?? 0);
    if (left <= 0) return json({ skipped: "daily budget used", budget, myt });
    const { data, error } = await admin.rpc("titi_nudge_candidates", { p_slot: slot, p_limit: 20000 });
    if (error) return json({ error: error.message }, 500);
    // Keep the members whose random time in this window has come (earliest first).
    const ready = ((data ?? []) as { user_id: string; last_sent_at: string | null }[])
      .map((r) => ({ id: r.user_id, d: due(r.user_id, now, [], r.last_sent_at ? Date.parse(r.last_sent_at) : null) }))
      .filter((r) => r.d.slot === slot)
      .sort((a, b) => (a.d as { target: number }).target - (b.d as { target: number }).target);
    ids = ready.slice(0, Math.min(BATCH, left)).map((r) => r.id);
    dueInfo = new Map(ready.map((r) => [r.id, (r.d as { target: number }).target]));
  }
  if (!ids.length) return json({ myt, window: win.name, sent: 0, candidates: 0 });

  const { data: ctxAll, error: ctxErr } = await admin.rpc("titi_nudge_context", { p_users: ids });
  if (ctxErr) return json({ error: ctxErr.message }, 500);
  const weather = new Weather(now.today, now.ms);
  const forced: Trigger | null = manual && typeof body.force_trigger === "string" ? body.force_trigger as Trigger : null;

  const results = await pool(ids, PARALLEL, async (id) => {
    // deno-lint-ignore no-explicit-any
    const raw = (ctxAll as Record<string, any>)?.[id] as Ctx | undefined;
    if (!raw) return { user: id, skipped: "no such member" };
    const c: Ctx = dry && body.ctx && typeof body.ctx === "object" ? { ...raw, ...body.ctx, id } : raw;

    // The rules a real send must pass (a dry run reports them and carries on;
    // a test send ignores the timing and the push token).
    const sentSlots = (c.sent_today ?? []).map((s) => s.slot);
    const lastMs = c.nudges?.length ? Math.max(...c.nudges.map((n) => Date.parse(n.sent_at))) : null;
    const d = due(id, now, sentSlots, lastMs);
    const timing = forcedSlot ? null : d.slot === null ? d.reason : null;
    const blockers = [
      !c.titi_tips && "TiTi tips is off",
      !testUser && !c.has_token && "no push token",
      sentSlots.includes(slot) && `already sent this ${win.name}`,
      c.pushes_24h >= 8 && "8 pushes in the last 24 h",
      !testUser && timing,
    ].filter(Boolean) as string[];
    if (blockers.length && !dry) return { user: id, skipped: blockers.join(", ") };

    const history = dry && Array.isArray(body.history) ? body.history.map(String) : (c.recent ?? []).map(String);
    const lang: Lang = manual && ["en", "zh", "ms"].includes(body.lang) ? body.lang
      : dry && Array.isArray(body.history) ? detectLang(history)
      : (["en", "zh", "ms"].includes(c.titi_lang ?? "") ? c.titi_lang as Lang : detectLang(history));

    let pick: Pick;
    if (forced && body.facts && typeof body.facts === "object") pick = { trigger: forced, ref: `test:${forced}`, facts: body.facts };
    else {
      // Weather matters in the morning (forecast + warnings) and afternoon (warnings).
      const wx = dry && "weather" in body ? (body.weather as WeatherFacts | null)
        : slot === 3 ? null : await weather.forMember(c.location, c.home_state).catch(() => null);
      pick = pickTrigger(c, wx, now, slot);
      if (forced && pick.trigger !== forced) return { user: id, skipped: `force_trigger ${forced}: nothing for it right now`, would_pick: pick.trigger };
    }

    const w = await write(c, pick, lang, history, slot, now);
    const cost = costOf(w.usage);
    const times = plan(id, now.today).map(hm);
    if (dry) {
      return {
        user: id, window: win.name, would_send: blockers.length === 0, blockers, todays_times: times, trigger: pick.trigger, ref: pick.ref, lang,
        text: w.text, chars: Array.from(w.text).length, fallback: w.fallback, usage: w.usage, cost_usd: Number(cost.toFixed(6)), facts: pick.facts,
      };
    }
    const sent = await deliver(id, pick, w.text, lang, w.usage, w.fallback, slot, now.today);
    return { user: id, window: win.name, target: dueInfo.has(id) ? hm(dueInfo.get(id)!) : null, trigger: pick.trigger, lang, text: w.text, fallback: w.fallback, usage: w.usage, ...sent };
  });

  // deno-lint-ignore no-explicit-any
  const sent = results.filter((r: any) => r.sent).length;
  console.log(`titi-nudge ${dry ? "dry" : testUser ? "test" : "cron"} ${win.name} candidates=${ids.length} sent=${sent}`);
  return json({ dry_run: dry, myt, window: win.name, candidates: ids.length, sent, results });
});
