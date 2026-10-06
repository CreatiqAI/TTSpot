// titi-nudge
// Proactive TiTi: at most ONE short message a member a day, written by the
// TiTi model from the member's own context, saved into their TiTi chat and
// pushed with the title "TiTi" (notification type titi_nudge → /titi).
//
// Called by pg_cron (titi_nudge_post(), every 30 min 08:00-21:30 MYT) with the
// header x-titi-secret. Deploy with --no-verify-jwt (config.toml).
//
// Who: titi_nudge_candidates(): "TiTi tips" on (profiles.settings.titi_tips),
// a push token, not suspended, nothing from TiTi yet today, fewer than 8
// pushes in the last 24 h. Never 22:00-08:00 Malaysia time. Off unless
// platform_settings.titi_nudges_enabled; at most titi_nudges_daily_budget a
// day across everyone; BATCH members a run.
//
// What (the first that fits, in this order; nothing fits = nothing sent):
//   weather  rain or storms in their area today (MET Malaysia forecast for
//            the nearest town to their last position, else their home state),
//            08:00-11:00, at most twice a week; or a live MET thunderstorm /
//            heavy-rain warning naming their area, 08:00-20:00.
//   meet     a meet they joined or bookmarked starts later today (an hour or
//            more away) and no meet reminder reached them today.
//   doc      road tax or insurance due within 7 days, 09:30-21:00, once per
//            car / paper / due date, and not on a day the 09:00 reminder pinged.
//   box      an unopened blind box, 12:00-21:00, once a week per box.
//   points   Friday 12:00-17:30: this week's +10 post is still open (the
//            weekly limits reset at 6 PM).
//   fun      17:00-21:00, a car fact or a check-in, at most 3 a week and
//            never two days running.
//
// Body (all optional; only for whoever holds the secret):
//   { dry_run: true, user_ids: [...] }   what it WOULD send; sends and logs nothing
//   { test_user: "<uuid>" }              a real send to that one member, even
//                                        while the switch is off
//   force_trigger, facts                 (dry run / test) use this trigger and these facts
//   history: ["…"]                       (dry run) pretend these were their recent TiTi messages
//   lang: "en"|"zh"|"ms"                 (dry run / test) override the language
//   now: ISO time                        (dry run / test) pretend it's this time
//
// Secrets: TITI_NUDGE_SECRET (= Vault titi_nudge_secret), OPENAI_API_KEY,
// TITI_MODEL (default gpt-5.4-mini).
import { createClient } from "npm:@supabase/supabase-js@2";
import { detectLang, type Lang } from "../_shared/lang.ts";
import { cleanLine, type Clock, clock, type Ctx, type Forecast, forecastEn, km, type Loc, MAX_CHARS, mytMs, normState, type Pick, pickTrigger, rainy, templateLine, timeMyt, type Trigger, type Warning, warningCovers, type WeatherFacts } from "./rules.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const SECRET = Deno.env.get("TITI_NUDGE_SECRET") ?? "";
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY");
const MODEL = Deno.env.get("TITI_MODEL") ?? "gpt-5.4-mini";

const BATCH = 40;
const PARALLEL = 5;
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
  today_(): Promise<Forecast[]> {
    return (this.forecasts ??= fetch(`https://api.data.gov.my/weather/forecast/?filter=${this.today}@date&limit=1000`)
      .then((r) => (r.ok ? r.json() : []))
      .catch(() => []));
  }
  live(): Promise<Warning[]> {
    return (this.warnings ??= fetch("https://api.data.gov.my/weather/warning/?limit=50")
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
   * position (≤40 km), else their home state's forecast. Null: nothing known. */
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
    const morning = row && rainy(row.morning_forecast) ? forecastEn(row.morning_forecast) : null;
    const afternoon = row && rainy(row.afternoon_forecast) ? forecastEn(row.afternoon_forecast) : null;
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

Write ONE push message to the member, from you.
- ${MAX_CHARS} characters at most. One or two short sentences. Short beats clever.
- Plain text only. At most one emoji. No hashtags, no links, no quotes around it, no sign-off.
- Use ONLY the facts given. Never invent times, places, prices, numbers, weather or events. Leave out anything you aren't given.
- Never say or hint that you are an AI, a bot or an assistant.
- Lead with the news and always keep its key detail: the time, when it's due, when it resets, what to do.
- Usually skip their name; when you use it, never as the first word. Mention their car only when it fits naturally (rain, road tax, a drive), like it's a friend.
- Don't start the way your recent lines to them started.
- Warm and a little playful; caring advice when it helps (weather: umbrella, wipers, slow down on wet roads).
- If their recent messages to you show what they care about, you may nod to it, lightly, without quoting them.
- Write in the language given.

Examples of the voice (English):
Rain's rolling into PJ this afternoon ☔ grab an umbrella and go easy on the corners, okay? Your Myvi wants to come home shiny.
Road tax for the Civic runs out in 3 days. Renew it tonight and drive easy tomorrow 🙌
Psst, there's an unopened box in your Cards. Give the phone a shake, I can't wait to see what's inside!
Weekly points reset at 6 PM today. One post before then and that +10 is yours ⭐`;

type Usage = { input: number; cached: number; output: number };
const costOf = (u: Usage) => ((u.input - u.cached) * PRICE.input + u.cached * PRICE.cached + u.output * PRICE.output) / 1e6;

function factsText(c: Ctx, p: Pick, lang: Lang, history: string[]): string {
  const first = (c.name ?? "").trim().split(/\s+/)[0] || null;
  const car = c.car ? [c.car.color, c.car.make, c.car.model].filter(Boolean).join(" ") : null;
  const lastLines = (c.nudges ?? []).slice(0, 3).map((n) => n.text ?? "").filter(Boolean);
  const recent = history.slice(-5).map((m) => m.replace(/\s+/g, " ").trim().slice(0, 100)).filter(Boolean);
  return [
    `Language: ${LANG_NAME[lang]}`,
    `Member's first name: ${first ?? "unknown (don't use a name)"}`,
    `Their car: ${car ?? "unknown (don't name a car)"}`,
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

async function write(c: Ctx, p: Pick, lang: Lang, history: string[]): Promise<{ text: string; usage: Usage; fallback: boolean }> {
  const usage: Usage = { input: 0, cached: 0, output: 0 };
  const facts = factsText(c, p, lang, history);
  // Numbers in the line must come from this message's facts (not old lines).
  const allowed = `${JSON.stringify(p.facts)} ${c.car?.model ?? ""} ${c.car?.make ?? ""}`;
  const add = (u: Usage) => {
    usage.input += u.input;
    usage.cached += u.cached;
    usage.output += u.output;
  };
  if (OPENAI_KEY) {
    try {
      const a = await callModel(facts, INSTRUCTIONS);
      add(a.usage);
      const ok = cleanLine(a.text, allowed);
      if (ok) return { text: ok, usage, fallback: false };
      // One retry, told why.
      const b = await callModel(`${facts}\n\nYour last try broke a rule (too long, a link or hashtag, or a number not in the facts): "${a.text.slice(0, 300)}". Write it again, under 140 characters.`, INSTRUCTIONS);
      add(b.usage);
      const ok2 = cleanLine(b.text, allowed);
      if (ok2) return { text: ok2, usage, fallback: false };
    } catch (e) {
      console.error("titi-nudge model", String(e).slice(0, 300));
    }
  }
  return { text: templateLine(p, c, lang), usage, fallback: true };
}

// ================================================================ sending ===

const TITI_SESSION_TITLE = "TiTi";

async function deliver(userId: string, p: Pick, text: string, lang: Lang, usage: Usage, fallback: boolean) {
  const cost = costOf(usage);
  // The 1-a-day claim first: unique (user_id, day) stops a second run racing in.
  const { data: log, error: logErr } = await admin.from("titi_nudges").insert({
    user_id: userId, trigger: p.trigger, ref: p.ref, text, lang, model: fallback && usage.output === 0 ? "template" : MODEL,
    input_tokens: usage.input, cached_tokens: usage.cached, output_tokens: usage.output, cost_usd: cost.toFixed(6), fallback,
  }).select("id").single();
  if (logErr || !log) return { sent: false, reason: logErr?.code === "23505" ? "already nudged today" : `log: ${logErr?.message}` };

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

  if (!manual) {
    if (!on(await setting("titi_nudges_enabled"))) return json({ skipped: "titi_nudges_enabled is off" });
  }
  // Quiet hours: never 22:00-08:00 Malaysia time (dry runs only report it).
  const quiet = now.hour < 8 || now.hour >= 22;
  if (quiet && !dry) return json({ skipped: "quiet hours (22:00-08:00 MYT)", myt_hour: now.hour });

  // Who.
  let ids: string[];
  if (dry) ids = (Array.isArray(body.user_ids) ? body.user_ids : []).filter((x: unknown) => typeof x === "string" && UUID.test(x)).slice(0, 20);
  else if (testUser) ids = [testUser];
  else {
    const budget = Number(await setting("titi_nudges_daily_budget") ?? 300) || 0;
    const { data: used } = await admin.rpc("titi_nudges_today");
    const left = budget - Number(used ?? 0);
    if (left <= 0) return json({ skipped: "daily budget used", budget });
    const { data, error } = await admin.rpc("titi_nudge_candidates", { p_limit: Math.min(BATCH, left) });
    if (error) return json({ error: error.message }, 500);
    ids = ((data ?? []) as string[]);
  }
  if (!ids.length) return json({ sent: 0, candidates: 0 });

  const { data: ctxAll, error: ctxErr } = await admin.rpc("titi_nudge_context", { p_users: ids });
  if (ctxErr) return json({ error: ctxErr.message }, 500);
  const weather = new Weather(now.today, now.ms);
  const forced: Trigger | null = manual && ["weather", "meet", "doc", "box", "points", "fun"].includes(body.force_trigger) ? body.force_trigger : null;

  const results = await pool(ids, PARALLEL, async (id) => {
    // deno-lint-ignore no-explicit-any
    const c = (ctxAll as Record<string, any>)?.[id] as Ctx | undefined;
    if (!c) return { user: id, skipped: "no such member" };
    // The rules a real send must pass (a dry run reports them and carries on).
    const blockers = [
      !c.titi_tips && "TiTi tips is off",
      !c.has_token && "no push token",
      c.nudged_today && "already nudged today",
      c.pushes_24h >= 8 && "8 pushes in the last 24 h",
      quiet && "quiet hours",
    ].filter(Boolean) as string[];
    if (blockers.length && !dry) return { user: id, skipped: blockers.join(", ") };

    const history = dry && Array.isArray(body.history) ? body.history.map(String) : (c.recent ?? []).map(String);
    const lang: Lang = manual && ["en", "zh", "ms"].includes(body.lang) ? body.lang
      : dry && Array.isArray(body.history) ? detectLang(history)
      : (["en", "zh", "ms"].includes(c.titi_lang ?? "") ? c.titi_lang as Lang : detectLang(history));

    let pick: Pick | null;
    if (forced && body.facts && typeof body.facts === "object") pick = { trigger: forced, ref: `test:${forced}`, facts: body.facts };
    else {
      const wx = await weather.forMember(c.location, c.home_state).catch(() => null);
      pick = pickTrigger(c, wx, now);
      if (forced && pick?.trigger !== forced) return { user: id, skipped: `force_trigger ${forced}: nothing for it right now`, would_pick: pick?.trigger ?? null };
    }
    if (!pick) return { user: id, skipped: "nothing worth saying right now" };

    const w = await write(c, pick, lang, history);
    const cost = costOf(w.usage);
    if (dry) return { user: id, would_send: blockers.length === 0, blockers, trigger: pick.trigger, ref: pick.ref, lang, text: w.text, chars: Array.from(w.text).length, fallback: w.fallback, usage: w.usage, cost_usd: Number(cost.toFixed(6)), facts: pick.facts };
    const d = await deliver(id, pick, w.text, lang, w.usage, w.fallback);
    return { user: id, trigger: pick.trigger, lang, text: w.text, fallback: w.fallback, usage: w.usage, ...d };
  });

  const sent = results.filter((r: any) => r.sent).length;
  console.log(`titi-nudge ${dry ? "dry" : testUser ? "test" : "cron"} candidates=${ids.length} sent=${sent}`);
  return json({ dry_run: dry, myt: `${now.today} ${Math.floor(now.hour)}:${String(Math.round((now.hour % 1) * 60)).padStart(2, "0")}`, candidates: ids.length, sent, results });
});
