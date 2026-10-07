// Pure rules for titi-nudge (no Supabase, no network): the three daily
// windows and each member's random time in them, weather text, which trigger
// fits, and checking / templating the line. Tested by titi-nudge/rules_test.ts.
import type { Lang } from "../_shared/lang.ts";

export const MAX_CHARS = 160;

// =================================================================== time ===

export type Clock = { ms: number; today: string; hour: number; weekday: number };
/** Malaysia time (UTC+8, no daylight saving). hour is fractional (9.5 = 9:30). weekday: 0 Sunday … 6 Saturday. */
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
/** 9.25 → "9:15" */
export const hm = (h: number) => {
  const m = Math.round(h * 60);
  return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")}`;
};

// ================================================================ windows ===

// Three messages a member a day at most, one in each window (Malaysia time),
// nothing 23:00-08:00. The cron runs every 30 minutes 08:00-22:30, so each
// member's random time in a window is at least 30 minutes before its end:
// the run at or after that time sends it, still inside the window.
export type Slot = 1 | 2 | 3;
export type Window = { slot: Slot; name: "morning" | "afternoon" | "evening"; start: number; end: number };
export const WINDOWS: readonly Window[] = [
  { slot: 1, name: "morning", start: 8, end: 12 },
  { slot: 2, name: "afternoon", start: 13, end: 18 },
  { slot: 3, name: "evening", start: 19, end: 23 },
];
export const CRON_STEP_H = 0.5;
/** Hours between two TiTi messages to the same member. */
export const GAP_H = 3;
/** A run a few minutes early (or a slow previous run) still counts as 3 h. */
export const GAP_SLACK_H = 10 / 60;

export const windowAt = (hour: number): Window | null => WINDOWS.find((w) => hour >= w.start && hour < w.end) ?? null;

/** FNV-1a, 32 bit: the same member, day and window always give the same number. */
export function hash32(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** This member's three target times today (fractional MYT hours), random
 * inside each window but at least 3 h apart: morning 08:00-11:29, afternoon
 * 13:00-17:29, evening 19:00-22:29. */
export function plan(userId: string, day: string): [number, number, number] {
  const t = WINDOWS.map((w) => {
    const minutes = Math.round((w.end - w.start - CRON_STEP_H) * 60); // 210 / 270 / 210
    return w.start + (hash32(`${userId}|${day}|${w.slot}`) % minutes) / 60;
  });
  // Push later times back so they're 3 h apart (always fits: the latest
  // morning time 11:29 → afternoon ≥ 14:29; afternoon 17:29 → evening ≥ 20:29).
  t[1] = Math.max(t[1], t[0] + GAP_H);
  t[2] = Math.max(t[2], t[1] + GAP_H);
  return [t[0], t[1], t[2]];
}

export type Due = { slot: Slot; window: Window["name"]; target: number } | { slot: null; reason: string };

/** Is this member's message for the current window due now? `sentToday`:
 * the slots already sent today; `lastSentMs`: their latest TiTi message. */
export function due(userId: string, now: Clock, sentToday: number[], lastSentMs: number | null): Due {
  const w = windowAt(now.hour);
  if (!w) return { slot: null, reason: "outside the windows (08-12, 13-18, 19-23 MYT)" };
  if (sentToday.includes(w.slot)) return { slot: null, reason: `already sent this ${w.name}` };
  const target = plan(userId, now.today)[w.slot - 1];
  if (now.hour < target) return { slot: null, reason: `${w.name} time is ${hm(target)}` };
  if (lastSentMs !== null && now.ms - lastSentMs < (GAP_H - GAP_SLACK_H) * 3600e3) return { slot: null, reason: "less than 3 h since the last one" };
  return { slot: w.slot, window: w.name, target };
}

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
export const hazy = (s: string | null | undefined) => /jerebu/i.test(s ?? "");
/** Worth a morning line: rain, storms or haze. */
export const notable = (s: string | null | undefined) => rainy(s) || hazy(s);

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

export type WeatherFacts = { area: string; morning: string | null; afternoon: string | null; night?: string | null; warning: string | null; temp: string | null };

// ================================================================ triggers ===

// Real triggers (something true about them right now) and fun ones (a line
// from the lists below). Never the same trigger twice in a day.
export const REAL = ["weather", "meet", "doc", "nearby", "friends", "points", "box", "live", "busy", "recap"] as const;
export const FUN = ["fact", "tip", "joke"] as const;
export type Trigger = typeof REAL[number] | typeof FUN[number] | "fun";
export type Pick = { trigger: Trigger; ref: string | null; facts: Record<string, unknown> };

export type NearEvent = { id: string; title: string; type: string; venue: string | null; starts_at: string; km: number; going: number };
export type LiveEvent = { id: string; title: string; type: string; venue: string | null; km: number; here: number };
export type Ctx = {
  id: string;
  name: string | null;
  home_state: string | null;
  titi_tips: boolean;
  titi_lang: string | null;
  has_token: boolean;
  pushes_24h: number;
  /** Their car; only used to keep make / model OUT of the line. */
  car: { make: string | null; model: string | null; color: string | null; year: number | null } | null;
  location: { lat: number; lng: number } | null;
  recent: string[];
  meets_today: { id: string; title: string; venue: string | null; starts_at: string; going: boolean; reminded_today: boolean }[];
  docs: { car_id: string; model: string; kind: "road_tax" | "insurance"; due: string; days: number }[];
  doc_pinged_today: boolean;
  boxes: string[];
  week_key: string;
  post_done: boolean;
  /** Public / friends' / own club's meets and TT sessions ≤15 km away, later today, not joined. */
  nearby: NearEvent[];
  /** Meets happening now ≤15 km away (not one they're checked in to), with how many checked in. */
  live: LiveEvent[];
  /** Friends at a meet or a spot right now. */
  friends_out: { count: number; names: string[] };
  /** The busiest spot ≤15 km away today. */
  busy: { id: string; name: string; km: number; checkins: number; going: number } | null;
  /** Since the weekly reset (Friday 6 PM): check-ins (meets + spots) and points earned. */
  week: { checkins: number; points: number };
  /** Today's TiTi messages. */
  sent_today: { slot: number; trigger: Trigger; sent_at: string }[];
  /** Last 30 days, newest first. */
  nudges: { trigger: Trigger; ref: string | null; sent_at: string; text?: string }[];
};

// Fun lines TiTi may share when nothing real fits. True, timeless, no prices.
// Index = ref ("fact:3"), so only ever ADD to the end of a list.
export const CAR_FACTS = [
  "The Proton Saga, Malaysia's first national car, launched in 1985.",
  "Perodua's first car was the Kancil, launched in 1994.",
  "Lamborghini made tractors before it made supercars.",
  "Ferrari's prancing horse first flew on WWI pilot Francesco Baracca's plane.",
  "Volkswagen means \"people's car\" in German.",
  "Toyota began as a loom maker, Toyoda Automatic Loom Works.",
  "Honda's first production car was the T360 mini pickup truck, from 1963.",
  "Porsche's first production car was the 356, from 1948.",
  "The Mazda MX-5 is in Guinness World Records as the best-selling two-seat sports car.",
  "The Toyota Corolla is the best-selling car nameplate of all time.",
  "Subaru is the Japanese name for the Pleiades star cluster; that's the stars on the badge.",
  "Audi's four rings stand for the four companies that merged into Auto Union in 1932.",
  "Mercedes was named after Mercedes Jellinek, the daughter of an early dealer.",
  "The Nissan Skyline GT-R got its \"Godzilla\" nickname from Australia's Wheels magazine in 1989.",
  "Karl Benz's Patent Motorwagen of 1886 is often called the first true car.",
  "In 1888 Bertha Benz made the first long-distance car trip, about 106 km, without telling her husband.",
  "The Ford Model T was built from 1908 to 1927.",
  "Mary Anderson patented the windscreen wiper in 1903.",
  "Sepang International Circuit opened in 1999 and hosted Formula 1 until 2017.",
  "Volvo introduced the three-point seat belt in 1959 and let every carmaker use the patent.",
  "The McLaren F1 puts the driver's seat in the middle, with a passenger on each side.",
  "The Toyota Prius, launched in 1997, was the first mass-produced hybrid car.",
  "Some Rolls-Royce models hide an umbrella inside the door.",
  "The original Mini, designed by Alec Issigonis, launched in 1959.",
  "The Proton Satria GTi had its handling tuned by Lotus, which Proton owned at the time.",
  "The Perodua Myvi first launched in 2005.",
  "The word \"car\" goes back to the Latin \"carrus\", a wheeled wagon.",
  "The Ferrari F40 was the last new Ferrari Enzo Ferrari himself launched.",
  "Lexus launched in 1989 with the LS 400.",
  "Ayrton Senna helped test the first Honda NSX at Suzuka.",
  "The Le Mans 24 Hours was first run in 1923.",
  "The first Formula 1 World Championship race was at Silverstone in 1950.",
  "The first speeding fine went to Walter Arnold in England in 1896, for about 8 mph.",
  "Tommi Mäkinen won four World Rally titles in a row, 1996 to 1999, in Mitsubishi Lancer Evos.",
  "Aston Martin's name comes partly from the Aston Hill climb in England.",
  "The Toyota AE86 is nicknamed \"Hachi-Roku\", Japanese for eight-six.",
  "The Nürburgring Nordschleife is about 20.8 km of corners.",
  "Koenigsegg's ghost badge honours the air force squadron whose old hangar it moved into.",
  "The original Volkswagen Beetle was built in Mexico until 2003.",
  "Malaysia drives on the left, like the UK, Japan and Singapore.",
];
export const CAR_TIPS = [
  "Roads are most slippery in the first minutes of rain, when oil lifts off the tarmac.",
  "Under-inflated tyres wear out faster on the edges and burn more fuel.",
  "Bird droppings can etch clear coat in the sun; wipe them off early.",
  "Coolant also protects the inside of the engine from corrosion, not just heat.",
  "Headlight lenses go yellow from UV; a restore kit can clear them up.",
  "Parking in the shade helps the dashboard and paint last longer.",
  "Wiper blades usually want replacing every 6 to 12 months in a hot, rainy climate.",
  "Check tyre pressure when the tyres are cold, before a drive.",
  "The right tyre pressure is on the sticker in the driver's door frame, not the number on the tyre.",
  "Washing the car in the midday sun leaves water spots; early morning or evening is kinder.",
  "In heavy rain, headlights on and hazards off while you're moving.",
  "If the car aquaplanes, ease off the throttle and keep the wheel straight; don't stamp on the brakes.",
  "On wet roads, leave a much bigger gap to the car in front.",
  "A car that keeps pulling to one side may have a slow puncture.",
  "Rotating your tyres now and then helps them wear evenly.",
  "Microfibre towels are much kinder to paint than old t-shirts.",
  "A sunshade on the windscreen keeps the cabin noticeably cooler.",
  "Never open the coolant cap on a hot engine; let it cool first.",
  "Check the spare tyre's pressure too; it's the one everyone forgets.",
  "Brake fluid soaks up moisture over time, so it needs changing every couple of years.",
];
export const CAR_JOKES = [
  "Washing the car is the most reliable way to make it rain.",
  "Why did the tyre go to therapy? It was tired of being under pressure.",
  "What's a car's favourite meal? Brake-fast.",
  "Car people don't have hobbies. We have projects that never finish.",
  "Mods are like snacks: you only planned on one.",
  "A clean car drives faster. Not scientifically. Emotionally.",
  "The fastest way to find a parking spot is to drive past it once.",
  "Traffic jams: the only time everyone gets to admire your car slowly.",
  "My car makes a funny noise when I tell it jokes. I think it's laughing. I hope it's laughing.",
  "Night drives fix moods. Not science, just facts.",
  "Every \"just one more mod\" comes with a small sigh from the wallet.",
  "The fuel light is not a challenge. It is not a challenge. It is not.",
  "Shift happens.",
  "Why don't cars ever feel alone? They always carry a spare.",
  "Parking in KL is a sport. Unofficial, but very competitive.",
  "\"Aerodynamics are for people who can't build engines.\" Often credited to Enzo Ferrari.",
  "Your car doesn't judge your singing. That's true love.",
  "Some people meditate. Car people go for a drive with no destination.",
  "A full tank and an empty road: the dream combo.",
  "Why was the car so calm? It knew how to brake its stress.",
];
const FUN_LIST: Record<typeof FUN[number], string[]> = { fact: CAR_FACTS, tip: CAR_TIPS, joke: CAR_JOKES };

export const sinceH = (iso: string, now: number) => (now - Date.parse(iso)) / 3600e3;

/** A fun line of this kind they haven't had in the last 30 days (else the
 * one they had longest ago), chosen by member + day + window. */
export function funPick(kind: typeof FUN[number], c: Ctx, now: Clock, slot: Slot): Pick {
  const list = FUN_LIST[kind];
  const lastUsed = new Map<number, number>();
  for (const n of c.nudges) {
    const m = /^(fact|tip|joke):(\d+)$/.exec(n.ref ?? "");
    if (m && m[1] === kind && !lastUsed.has(Number(m[2]))) lastUsed.set(Number(m[2]), Date.parse(n.sent_at));
  }
  const start = hash32(`${c.id}|${now.today}|${slot}|${kind}`) % list.length;
  let best = -1, bestAt = Infinity;
  for (let k = 0; k < list.length; k++) {
    const i = (start + k) % list.length;
    const at = lastUsed.get(i);
    if (at === undefined) {
      best = i;
      break;
    }
    if (at < bestAt) bestAt = at, best = i;
  }
  const key = kind === "fact" ? "car_fact" : kind === "tip" ? "car_tip" : "joke";
  return { trigger: kind, ref: `${kind}:${best}`, facts: { [key]: list[best] } };
}

const FUN_ORDER: Record<Slot, typeof FUN[number][]> = { 1: ["fact", "tip", "joke"], 2: ["tip", "fact", "joke"], 3: ["joke", "fact", "tip"] };
const TYPE_NAME: Record<string, string> = { meet: "meet", tt: "TT session", convoy: "convoy", trackday: "track day", charity: "charity drive", official: "event" };
/** Distance for the facts: 4.2 → 4, 0.6 → "under 1". */
const kmAway = (k: number): number | string => (k < 1 ? "under 1" : Math.round(k));
const kmEn = (k: unknown) => (k === "under 1" ? "under 1 km away" : `about ${k} km away`);

/** What TiTi says in this window: the first real thing that fits, else a fun
 * line. Never the same trigger twice in a day. Pure: easy to test. */
export function pickTrigger(c: Ctx, wx: WeatherFacts | null, now: Clock, slot: Slot): Pick {
  const h = now.hour;
  const usedToday = new Set<string>(c.sent_today.map((s) => s.trigger));
  const sent = (t: Trigger, ref?: string | null, withinH = 24 * 365) =>
    c.nudges.some((n) => n.trigger === t && (ref === undefined || n.ref === ref) && sinceH(n.sent_at, now.ms) < withinH);
  const countSince = (t: Trigger, withinH: number) => c.nudges.filter((n) => n.trigger === t && sinceH(n.sent_at, now.ms) < withinH).length;
  const ok = (t: Trigger) => !usedToday.has(t);

  const weatherWarning = (): Pick | null =>
    wx?.warning && ok("weather") ? { trigger: "weather", ref: `warn:${now.today}`, facts: { weather: { area: wx.area, warning: wx.warning } } } : null;

  const morning = (): Pick | null => {
    // Real weather today: a live MET warning, or MET's forecast says rain /
    // storms / haze for their area (at most 3 forecast lines a week).
    const w = weatherWarning();
    if (w) return { ...w, facts: { weather: { ...wx, night: undefined } } };
    if (wx && (wx.morning || wx.afternoon) && ok("weather") && countSince("weather", 24 * 7) < 3) {
      return { trigger: "weather", ref: `fc:${now.today}`, facts: { weather: { area: wx.area, morning: wx.morning, afternoon: wx.afternoon, temp: wx.temp } } };
    }
    // A meet they joined / bookmarked later today (an hour or more away) that no reminder covered today.
    if (ok("meet")) {
      for (const m of c.meets_today) {
        if (m.reminded_today || Date.parse(m.starts_at) - now.ms < 3600e3 || sent("meet", `meet:${m.id}`)) continue;
        return { trigger: "meet", ref: `meet:${m.id}`, facts: { meet: { title: m.title, place: m.venue, starts: `today ${timeMyt(m.starts_at)}`, they_are: m.going ? "going" : "interested (bookmarked)" } } };
      }
    }
    // Road tax / insurance due within 7 days (after the 09:00 reminder, never the same day as it).
    if (ok("doc") && h >= 9.5 && !c.doc_pinged_today) {
      for (const d of c.docs) {
        const ref = `doc:${d.car_id}:${d.kind}:${d.due}`;
        if (sent("doc", ref)) continue;
        return { trigger: "doc", ref, facts: { paper: { what: d.kind === "road_tax" ? "road tax" : "insurance", for: "their car", due: dayMonth(d.due), when: d.days === 0 ? "today" : d.days === 1 ? "tomorrow" : `in ${d.days} days` } } };
      }
    }
    return null;
  };

  const afternoon = (): Pick | null => {
    // Something near them later today (≤15 km): a meet or TT they haven't joined.
    if (ok("nearby")) {
      const e = c.nearby.find((x) => !sent("nearby", `near:${x.id}`));
      if (e) {
        return {
          trigger: "nearby", ref: `near:${e.id}`,
          facts: { near_you_today: { what: TYPE_NAME[e.type] ?? "meet", title: e.title, place: e.venue, starts: `today ${timeMyt(e.starts_at)}`, km_away: kmAway(e.km), going: e.going, more_today: Math.max(0, c.nearby.length - 1) || undefined } },
        };
      }
    }
    // Friends out right now (at a meet or a spot).
    if (ok("friends") && c.friends_out.count > 0) {
      return { trigger: "friends", ref: `friends:${now.today}`, facts: { friends_out_now: { count: c.friends_out.count, names: c.friends_out.names, where: "out at a meet or a spot right now (they can see them on the map); not necessarily near them" } } };
    }
    // A live MET storm warning (if the morning didn't already talk weather).
    const w = weatherWarning();
    if (w) return w;
    // Friday: this week's +10 post is still open; limits reset at 6 PM.
    if (ok("points") && now.weekday === 5 && h < 17.75 && !c.post_done && !sent("points", `points:${c.week_key}`)) {
      return { trigger: "points", ref: `points:${c.week_key}`, facts: { points: { reset: "today 6 PM", open: "the weekly +10 points for sharing a post" } } };
    }
    // An unopened blind box (once a week per box).
    if (ok("box") && c.boxes.length) {
      const box = c.boxes.find((b) => !sent("box", `box:${b}`, 24 * 7));
      if (box) return { trigger: "box", ref: `box:${box}`, facts: { blind_box: { unopened: c.boxes.length, how: "open it in Cards by shaking the phone" } } };
    }
    return null;
  };

  const evening = (): Pick | null => {
    // Live now near them: a meet happening right now, and how many are there.
    if (ok("live")) {
      const e = c.live.find((x) => !sent("live", `live:${x.id}`));
      if (e) return { trigger: "live", ref: `live:${e.id}`, facts: { live_now: { what: TYPE_NAME[e.type] ?? "meet", title: e.title, place: e.venue, km_away: kmAway(e.km), checked_in: e.here } } };
    }
    // Sunday evening: a mini recap of their week so far (only if there's something to recap).
    if (ok("recap") && now.weekday === 0 && (c.week.checkins > 0 || c.week.points > 0) && !sent("recap", `recap:${c.week_key}`)) {
      return { trigger: "recap", ref: `recap:${c.week_key}`, facts: { this_week: { checkins: c.week.checkins, points_earned: c.week.points, since: "Friday 6 PM" } } };
    }
    // A spot near them that's busy tonight.
    if (ok("busy") && c.busy && !sent("busy", `busy:${c.busy.id}:${now.today}`)) {
      const b = c.busy;
      return { trigger: "busy", ref: `busy:${b.id}:${now.today}`, facts: { busy_spot: { what: "a spot (a place, not an event) that's busy today", name: b.name, km_away: kmAway(b.km), members_checked_in_today: b.checkins || undefined, going_to_meets_there_today: b.going || undefined } } };
    }
    return null;
  };

  const real = slot === 1 ? morning() : slot === 2 ? afternoon() : evening();
  if (real) return real;
  const kind = FUN_ORDER[slot].find((k) => ok(k)) ?? FUN_ORDER[slot][0];
  return funPick(kind, c, now, slot);
}

export const EMOJI = /\p{Extended_Pictographic}/gu;

/** Tidies the model's line; null when it breaks a rule (length, links,
 * hashtags, "I'm an AI", a number that isn't in the facts, or naming their
 * car's make / model). */
export function cleanLine(raw: string, facts: string, carWords: string[] = []): string | null {
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
  const lower = t.toLowerCase();
  for (const w of carWords) {
    const x = (w ?? "").trim().toLowerCase();
    if (x.length >= 3 && !facts.toLowerCase().includes(x) && new RegExp(`(^|[^\\p{L}\\p{N}])${x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}($|[^\\p{L}\\p{N}])`, "u").test(lower)) return null;
  }
  return t;
}

/** A ready-made line when the model is down or breaks the rules. */
export function templateLine(p: Pick, lang: Lang): string {
  // deno-lint-ignore no-explicit-any
  const f = p.facts as any;
  const wx = f.weather ?? {};
  const fc = wx.afternoon ?? wx.morning ?? "";
  const n = f.near_you_today ?? {}, lv = f.live_now ?? {}, fr = f.friends_out_now ?? {}, b = f.busy_spot ?? {}, wk = f.this_week ?? {};
  const fun = f.car_fact ?? f.car_tip ?? f.joke ?? "";
  const L: Record<Lang, Record<string, () => string>> = {
    en: {
      weather: () => (wx.warning ? `Storm warning for ${wx.area} ⛈️ slow down, lights on, and stay safe out there.` : `MET says ${fc} around ${wx.area} today ☔ go easy out there and look after your ride.`),
      meet: () => `${f.meet?.title} is today, ${f.meet?.starts.replace("today ", "")}. See you there? 🏁`,
      doc: () => `Heads up: your car's ${f.paper?.what} runs out ${f.paper?.when}. Sort it out early, okay?`,
      nearby: () => `${n.title} is on today at ${n.starts?.replace("today ", "")}, ${kmEn(n.km_away)} 🏁 fancy a look?`,
      friends: () => `${fr.names?.length ? fr.names.join(" and ") : `${fr.count} of your friends`} ${fr.count === 1 ? "is" : "are"} out right now. Peek at the map? 👀`,
      points: () => `Weekly points reset at 6 PM today. Share a post before then for your +10 ⭐`,
      box: () => `There's an unopened box in your Cards 🎁 give the phone a shake!`,
      live: () => `${lv.title} is live right now, ${kmEn(lv.km_away)}, ${lv.checked_in} checked in 🔥`,
      busy: () => `${b.name} is busy today, ${kmEn(b.km_away)}. Good night for a drive? 🚗`,
      recap: () => `Your week so far: ${wk.checkins} check-ins, ${wk.points_earned} points ⭐ nice going!`,
      fact: () => `Fun fact: ${fun}`,
      tip: () => `Quick tip: ${fun}`,
      joke: () => fun,
      fun: () => fun || `Just checking in. How's your ride treating you? 🚗`,
    },
    zh: {
      weather: () => (wx.warning ? `${wx.area}有雷暴警告 ⛈️ 开车慢一点，注意安全哦。` : `气象局说${wx.area}今天可能下雨 ☔ 开车小心哦。`),
      meet: () => `今天有 ${f.meet?.title}，${f.meet?.starts.replace("today ", "")} 开始，见你哦 🏁`,
      doc: () => `提醒：你的车${f.paper?.what === "road tax" ? "路税" : "保险"}${f.paper?.when === "today" ? "今天" : f.paper?.when === "tomorrow" ? "明天" : "快要"}到期，早点处理哦。`,
      nearby: () => `今天 ${n.starts?.replace("today ", "")} 附近有 ${n.title} 🏁 要去看看吗？`,
      friends: () => `你有 ${fr.count} 个朋友现在在外面，看看地图吧 👀`,
      points: () => `每周积分今天 6 PM 重置，记得之前发个帖子拿 +10 ⭐`,
      box: () => `你的卡片里还有一个没开的盲盒 🎁 摇一摇手机吧！`,
      live: () => `${lv.title} 正在进行中，已经有 ${lv.checked_in} 人签到 🔥`,
      busy: () => `${b.name} 今天很热闹，要不要去兜兜风？🚗`,
      recap: () => `这周到现在：${wk.checkins} 次签到，${wk.points_earned} 积分 ⭐ 不错哦！`,
      fact: () => `冷知识：${fun}`,
      tip: () => `小贴士：${fun}`,
      joke: () => fun,
      fun: () => fun || `来关心一下你，你的车最近还好吗？🚗`,
    },
    ms: {
      weather: () => (wx.warning ? `Amaran ribut petir di ${wx.area} ⛈️ perlahan sikit dan hati-hati ya.` : `MET kata mungkin hujan di ${wx.area} hari ini ☔ bawa elok-elok ya.`),
      meet: () => `${f.meet?.title} hari ini, ${f.meet?.starts.replace("today ", "")}. Jumpa sana? 🏁`,
      doc: () => `Ingatan: ${f.paper?.what === "road tax" ? "cukai jalan" : "insurans"} kereta awak tamat tidak lama lagi. Selesaikan awal ya.`,
      nearby: () => `${n.title} hari ini pukul ${n.starts?.replace("today ", "")}, dekat dengan awak 🏁 nak tengok?`,
      friends: () => `${fr.count} kawan awak tengah keluar sekarang. Tengok peta? 👀`,
      points: () => `Mata mingguan reset pukul 6 PM hari ini. Kongsi post sebelum itu untuk +10 ⭐`,
      box: () => `Ada kotak misteri belum dibuka dalam Cards 🎁 goncang telefon!`,
      live: () => `${lv.title} tengah berlangsung sekarang, ${lv.checked_in} orang dah check in 🔥`,
      busy: () => `${b.name} meriah hari ini. Malam yang sesuai untuk drive? 🚗`,
      recap: () => `Minggu ni setakat ini: ${wk.checkins} check-in, ${wk.points_earned} mata ⭐ bagus!`,
      fact: () => `Fakta menarik: ${fun}`,
      tip: () => `Tip: ${fun}`,
      joke: () => fun,
      fun: () => fun || `Saja tanya khabar. Kereta okay ke? 🚗`,
    },
  };
  const t = (L[lang][p.trigger] ?? L[lang].fun)().replace(/\s+/g, " ").trim();
  return Array.from(t).length > MAX_CHARS ? Array.from(t).slice(0, MAX_CHARS - 1).join("") + "…" : t;
}
