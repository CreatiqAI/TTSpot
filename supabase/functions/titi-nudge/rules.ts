// Pure rules for titi-nudge (no Supabase, no network): time, weather text,
// which trigger fits, and checking / templating the line. Tested by
// titi-nudge/rules_test.ts.
import type { Lang } from "../_shared/lang.ts";

export const MAX_CHARS = 160;

// =================================================================== time ===

export type Clock = { ms: number; today: string; hour: number; weekday: number };
/** Malaysia time (UTC+8, no daylight saving). hour is fractional (9.5 = 9:30). */
export function clock(ms: number): Clock {
  const m = new Date(ms + 8 * 3600e3);
  return { ms, today: m.toISOString().slice(0, 10), hour: m.getUTCHours() + m.getUTCMinutes() / 60, weekday: m.getUTCDay() };
}
/** "9:30 PM" in Malaysia time. */
export function timeMyt(iso: string): string {
  const t = new Date(Date.parse(iso) + 8 * 3600e3);
  const h = t.getUTCHours();
  return `${h % 12 === 0 ? 12 : h % 12}:${String(t.getUTCMinutes()).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}
/** "12 Oct" */
export const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export const dayMonth = (d: string) => `${Number(d.slice(8, 10))} ${MONTHS[Number(d.slice(5, 7)) - 1]}`;

// ================================================================ weather ===

export type Loc = { id: string; name: string; kind: "town" | "district"; state: string | null; lat: number; lng: number };
export type Forecast = { location: { location_id: string; location_name: string }; date: string; morning_forecast: string; afternoon_forecast: string; night_forecast: string; min_temp: number; max_temp: number };
export type Warning = { warning_issue: { title_en: string }; valid_from: string | null; valid_to: string | null; text_en: string | null };

export function km(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** "WP Kuala Lumpur", "W.P. Kuala Lumpur", "KL" → "kuala lumpur"; Penang → pulau pinang. */
export function normState(s: string | null | undefined): string {
  let t = (s ?? "").toLowerCase().replace(/w\.\s*p\.?|\bwp\b|wilayah persekutuan/g, "").replace(/[^a-z ]/g, " ").replace(/\s+/g, " ").trim();
  if (t === "kl") t = "kuala lumpur";
  if (t === "penang") t = "pulau pinang";
  if (t === "malacca") t = "melaka";
  return t;
}

/** The Malay forecast in plain English: "Ribut petir di beberapa tempat" → "thunderstorms in some places". */
export function forecastEn(s: string | null | undefined): string {
  const t = (s ?? "").toLowerCase().trim();
  if (!t) return "";
  if (t.startsWith("tiada hujan")) return "no rain";
  const base = t.startsWith("ribut petir") ? "thunderstorms" : t.startsWith("hujan") ? "rain" : t.startsWith("mendung") ? "cloudy" : t.startsWith("jerebu") || t.startsWith("berjerebu") ? "haze" : t.startsWith("cerah") ? "fair" : t.startsWith("berangin") ? "windy" : t;
  const extent = t.includes("menyeluruh") ? "widespread " : "";
  const where = t.includes("satu dua tempat") ? " in one or two places" : t.includes("beberapa tempat") ? " in some places" : t.includes("kebanyakan tempat") ? " in most places" : "";
  const region = t.includes("kawasan pedalaman") ? " inland" : t.includes("kawasan pantai") ? " along the coast" : "";
  return `${extent}${base}${where}${region}`;
}
export const rainy = (s: string | null | undefined) => /hujan|ribut/i.test(s ?? "") && !/tiada hujan/i.test(s ?? "");

/** Does a live MET warning cover this member? States in the text may list
 * districts in brackets or after a colon; then their district or town must
 * be named, else the whole state counts. */
export function warningCovers(text: string, state: string, places: string[]): boolean {
  const st = normState(state);
  if (!st) return false;
  const lower = text.toLowerCase();
  for (const seg of lower.split(/•|\b\d\)\s/)) {
    const re = new RegExp(`\\b${st.replace(/ /g, "\\s+")}\\b`);
    const m = re.exec(seg.replace(/w\.\s*p\.\s*/g, ""));
    if (!m) continue;
    const clean = seg.replace(/w\.\s*p\.\s*/g, "");
    const detail = clean.slice(m.index + m[0].length).split(/\buntil\b/)[0].trim();
    if (!detail.startsWith("(") && !detail.startsWith(":")) return true;
    if (places.some((p) => p && detail.includes(p.toLowerCase()))) return true;
  }
  return false;
}

/** Validity times come as Malaysian local time without an offset. */
export const mytMs = (s: string | null) => (s ? Date.parse(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : `${s}+08:00`) : NaN);

export type WeatherFacts = { area: string; morning: string | null; afternoon: string | null; warning: string | null; temp: string | null };

// ================================================================ triggers ===

export type Trigger = "weather" | "meet" | "doc" | "box" | "points" | "fun";
export type Pick = { trigger: Trigger; ref: string | null; facts: Record<string, unknown> };

export type Ctx = {
  name: string | null;
  home_state: string | null;
  titi_tips: boolean;
  titi_lang: string | null;
  has_token: boolean;
  pushes_24h: number;
  nudged_today: boolean;
  car: { make: string | null; model: string | null; color: string | null; year: number | null } | null;
  location: { lat: number; lng: number } | null;
  recent: string[];
  meets_today: { id: string; title: string; venue: string | null; starts_at: string; going: boolean; reminded_today: boolean }[];
  docs: { car_id: string; model: string; kind: "road_tax" | "insurance"; due: string; days: number }[];
  doc_pinged_today: boolean;
  boxes: string[];
  week_key: string;
  post_done: boolean;
  /** Last 30 days, newest first. */
  nudges: { trigger: Trigger; ref: string | null; sent_at: string; text?: string }[];
};

// Car facts TiTi may share on a quiet day (true, timeless, no prices).
export const CAR_FACTS = [
  "The Proton Saga, Malaysia's first national car, launched in 1985.",
  "Perodua's first car was the Kancil, launched in 1994.",
  "Lamborghini made tractors before it made supercars.",
  "Ferrari's prancing horse first flew on WWI pilot Francesco Baracca's plane.",
  "Volkswagen means \"people's car\" in German.",
  "Toyota began as a loom maker, Toyoda Automatic Loom Works.",
  "Honda's first car was the T360 mini pickup truck in 1963.",
  "Porsche's first production car was the 356, from 1948.",
  "Roads are most slippery in the first minutes of rain, when oil lifts off the tarmac.",
  "Under-inflated tyres wear out faster on the edges and burn more fuel.",
  "Bird droppings can etch clear coat if left on paint for days in the sun.",
  "Coolant also protects the inside of the engine from corrosion, not just heat.",
  "Headlight lenses go yellow from UV; a restore kit can clear them up.",
  "Parking in the shade helps the dashboard and paint last longer.",
  "Wiper blades usually want replacing every 6 to 12 months in a hot, rainy climate.",
];

export const sinceH = (iso: string, now: number) => (now - Date.parse(iso)) / 3600e3;

/** The most useful thing to say right now, or null. Pure: easy to test. */
export function pickTrigger(c: Ctx, wx: WeatherFacts | null, now: Clock): Pick | null {
  const h = now.hour;
  const sent = (t: Trigger, ref?: string | null, withinH = 24 * 365) =>
    c.nudges.some((n) => n.trigger === t && (ref === undefined || n.ref === ref) && sinceH(n.sent_at, now.ms) < withinH);
  const countSince = (t: Trigger, withinH: number) => c.nudges.filter((n) => n.trigger === t && sinceH(n.sent_at, now.ms) < withinH).length;

  // (a) weather: a live warning (08:00-20:00), or a rainy forecast in the morning (twice a week at most).
  if (wx) {
    if (wx.warning && h < 20) return { trigger: "weather", ref: `warn:${now.today}`, facts: { weather: wx } };
    if ((wx.morning || wx.afternoon) && h < 11 && countSince("weather", 24 * 7) < 2) return { trigger: "weather", ref: `rain:${now.today}`, facts: { weather: { ...wx, warning: undefined } } };
  }
  // (b) a meet today, an hour or more away, that no reminder covered today.
  for (const m of c.meets_today) {
    if (m.reminded_today || Date.parse(m.starts_at) - now.ms < 3600e3 || sent("meet", `meet:${m.id}`)) continue;
    return { trigger: "meet", ref: `meet:${m.id}`, facts: { meet: { title: m.title, place: m.venue, starts: `today ${timeMyt(m.starts_at)}`, joined: m.going ? "going" : "bookmarked" } } };
  }
  // (c) road tax / insurance due within 7 days (after the 09:00 reminder, never the same day as it).
  if (h >= 9.5 && !c.doc_pinged_today) {
    for (const d of c.docs) {
      const ref = `doc:${d.car_id}:${d.kind}:${d.due}`;
      if (sent("doc", ref)) continue;
      return {
        trigger: "doc",
        ref,
        facts: { paper: { what: d.kind === "road_tax" ? "road tax" : "insurance", car: d.model, due: dayMonth(d.due), when: d.days === 0 ? "today" : d.days === 1 ? "tomorrow" : `in ${d.days} days` } },
      };
    }
  }
  // (d) an unopened blind box (afternoon; once a week per box).
  if (h >= 12 && c.boxes.length) {
    const box = c.boxes.find((b) => !sent("box", `box:${b}`, 24 * 7));
    if (box) return { trigger: "box", ref: `box:${box}`, facts: { blind_box: { unopened: c.boxes.length, how: "open it in Cards by shaking the phone" } } };
  }
  // (e) Friday afternoon: this week's +10 post is still open; limits reset at 6 PM.
  if (now.weekday === 5 && h >= 12 && h < 17.5 && !c.post_done && !sent("points", `points:${c.week_key}`)) {
    return { trigger: "points", ref: `points:${c.week_key}`, facts: { points: { reset: "today 6 PM", open: "the weekly +10 points for sharing a post" } } };
  }
  // (f) now and then, a fun line in the evening.
  if (h >= 17 && countSince("fun", 48) === 0 && countSince("fun", 24 * 7) < 3) {
    const seed = [...`${now.today}`].reduce((a, ch) => a + ch.charCodeAt(0), 0) + c.nudges.length;
    const fact = seed % 3 === 0 ? null : CAR_FACTS[seed % CAR_FACTS.length];
    return { trigger: "fun", ref: fact ? `fact:${CAR_FACTS.indexOf(fact)}` : "checkin", facts: fact ? { car_fact: fact } : { check_in: "just checking in on them and their car" } };
  }
  return null;
}

export const EMOJI = /\p{Extended_Pictographic}/gu;

/** Tidies the model's line; null when it breaks a rule (length, links,
 * hashtags, "I'm an AI", or a number that isn't in the facts). */
export function cleanLine(raw: string, facts: string): string | null {
  let t = raw.replace(/\s+/g, " ").trim().replace(/^["'“”‘’「」]+|["'“”‘’「」]+$/g, "").trim();
  if (!t) return null;
  // Keep the first emoji only (and the variation selectors / joiners with it).
  let seen = 0;
  t = t.replace(EMOJI, (m) => (++seen === 1 ? m : "")).replace(/(?<!\p{Extended_Pictographic})[️‍]/gu, "")
    .replace(/\s+/g, " ").replace(/\s+([.,!?])/g, "$1").trim();
  if (Array.from(t).length > MAX_CHARS) return null;
  if (/#|https?:|www\.|\[\[|\*\*/.test(t)) return null;
  if (/\b(AI|A\.I\.|artificial intelligence|language model|chat ?bot|bot)\b|人工智能|机器人|kecerdasan buatan/i.test(t)) return null;
  for (const n of t.match(/\d+/g) ?? []) if (!facts.includes(n)) return null;
  return t;
}

/** A ready-made line when the model is down or breaks the rules. */
export function templateLine(p: Pick, c: Ctx, lang: Lang): string {
  const car = c.car?.model ?? null;
  const f = p.facts as any;
  const L = {
    en: {
      weather: () => (f.weather?.warning ? `Storm warning for ${f.weather.area} ⛈️ slow down, lights on, and stay safe out there.` : `Rain likely around ${f.weather?.area} today ☔ go easy on the corners${car ? ` and bring the ${car} home shiny` : ""}.`),
      meet: () => `${f.meet?.title} is today, ${f.meet?.starts.replace("today ", "")}. See you there? 🏁`,
      doc: () => `Heads up: ${f.paper?.what} for the ${f.paper?.car} runs out ${f.paper?.when}. Sort it out early, okay?`,
      box: () => `There's an unopened box in your Cards 🎁 give the phone a shake!`,
      points: () => `Weekly points reset at 6 PM today. Share a post before then for your +10 ⭐`,
      fun: () => (f.car_fact ? `Fun fact: ${f.car_fact}` : `Just checking in. How's ${car ? `the ${car}` : "the ride"} treating you? 🚗`),
    },
    zh: {
      weather: () => (f.weather?.warning ? `${f.weather.area}有雷暴警告 ⛈️ 开车慢一点，注意安全哦。` : `${f.weather?.area}今天可能下雨 ☔ 过弯慢一点${car ? `，${car}要平安回家哦` : ""}。`),
      meet: () => `今天有 ${f.meet?.title}，${f.meet?.starts.replace("today ", "")} 开始，见你哦 🏁`,
      doc: () => `提醒：${f.paper?.car} 的${f.paper?.what === "road tax" ? "路税" : "保险"}${f.paper?.when === "today" ? "今天" : f.paper?.when === "tomorrow" ? "明天" : "快要"}到期，早点处理哦。`,
      box: () => `你的卡片里还有一个没开的盲盒 🎁 摇一摇手机吧！`,
      points: () => `每周积分今天 6 PM 重置，记得之前发个帖子拿 +10 ⭐`,
      fun: () => (f.car_fact ? `冷知识：${f.car_fact}` : `来关心一下你，${car ?? "你的车"}最近还好吗？🚗`),
    },
    ms: {
      weather: () => (f.weather?.warning ? `Amaran ribut petir di ${f.weather.area} ⛈️ perlahan sikit dan hati-hati ya.` : `Mungkin hujan di ${f.weather?.area} hari ini ☔ selekoh tu bawa perlahan ya.`),
      meet: () => `${f.meet?.title} hari ini, ${f.meet?.starts.replace("today ", "")}. Jumpa sana? 🏁`,
      doc: () => `Ingatan: ${f.paper?.what === "road tax" ? "cukai jalan" : "insurans"} ${f.paper?.car} tamat tidak lama lagi. Selesaikan awal ya.`,
      box: () => `Ada kotak misteri belum dibuka dalam Cards 🎁 goncang telefon!`,
      points: () => `Mata mingguan reset pukul 6 PM hari ini. Kongsi post sebelum itu untuk +10 ⭐`,
      fun: () => (f.car_fact ? `Fakta menarik: ${f.car_fact}` : `Saja tanya khabar. ${car ?? "Kereta"} okay ke? 🚗`),
    },
  }[lang][p.trigger]();
  const t = L.replace(/\s+/g, " ").trim();
  return Array.from(t).length > MAX_CHARS ? Array.from(t).slice(0, MAX_CHARS - 1).join("") + "…" : t;
}
