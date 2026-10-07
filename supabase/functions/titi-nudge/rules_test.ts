// deno test supabase/functions/titi-nudge/rules_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { detectLang, langOf } from "../_shared/lang.ts";
import {
  CAR_FACTS, CAR_JOKES, CAR_TIPS, cleanLine, clock, type Ctx, due, forecastEn, GAP_H, MAX_CHARS, notable, pickTrigger, plan, rainy, templateLine,
  type Trigger, warningCovers, type WeatherFacts, windowAt,
} from "./rules.ts";

// 2026-10-07 is a Wednesday; 2026-10-09 a Friday; 2026-10-11 a Sunday. Times below are MYT.
const at = (s: string) => clock(Date.parse(`${s}+08:00`));
const iso = (s: string) => new Date(Date.parse(`${s}+08:00`)).toISOString();

const base: Ctx = {
  id: "693b5344-1cf8-4366-96e7-ca196edfcf4d",
  name: "Aiman", home_state: "Kuala Lumpur", titi_tips: true, titi_lang: null, has_token: true, pushes_24h: 0,
  car: { make: "Perodua", model: "Myvi", color: "white", year: null }, location: { lat: 3.1, lng: 101.7 }, recent: [],
  meets_today: [], docs: [], doc_pinged_today: false, boxes: [], week_key: "2026-10-02", post_done: true,
  nearby: [], live: [], friends_out: { count: 0, names: [] }, busy: null, week: { checkins: 0, points: 0 },
  sent_today: [], nudges: [],
};
const rain: WeatherFacts = { area: "Petaling Jaya", morning: null, afternoon: "thunderstorms in some places", warning: null, temp: "25-34°C" };
const sentAt = (trigger: Trigger, ref: string, when: string) => ({ trigger, ref, sent_at: iso(when) });

// ------------------------------------------------------------- windows ---

Deno.test("windows: 08-12, 13-18, 19-23; nothing else", () => {
  for (const [h, slot] of [[7.99, null], [8, 1], [11.99, 1], [12, null], [12.5, null], [13, 2], [17.99, 2], [18.5, null], [19, 3], [22.99, 3], [23, null], [2, null]] as const) {
    assertEquals(windowAt(h)?.slot ?? null, slot, `hour ${h}`);
  }
});

Deno.test("plan: inside each window, 30 min before its end, at least 3 h apart, stable", () => {
  const days = ["2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11"];
  const seen = new Set<string>();
  for (let i = 0; i < 2000; i++) {
    const id = crypto.randomUUID();
    const day = days[i % days.length];
    const [a, b, c] = plan(id, day);
    assert(a >= 8 && a < 11.5, `morning ${a}`);
    assert(b >= 13 && b < 17.5, `afternoon ${b}`);
    assert(c >= 19 && c < 22.5, `evening ${c}`);
    assert(b - a >= GAP_H - 1e-9 && c - b >= GAP_H - 1e-9, `gap ${a} ${b} ${c}`);
    assertEquals(plan(id, day), [a, b, c], "same member + day = same times");
    seen.add(`${Math.floor(a)}`);
  }
  assert(seen.size >= 3, "morning times spread over the window");
  assert(plan(base.id, "2026-10-07")[0] !== plan(base.id, "2026-10-08")[0] || plan(base.id, "2026-10-07")[2] !== plan(base.id, "2026-10-08")[2], "changes day to day");
});

Deno.test("plan: the next 30-min cron run after each time is still inside the window, and runs keep 3 h", () => {
  for (let i = 0; i < 2000; i++) {
    const t = plan(crypto.randomUUID(), "2026-10-07");
    const run = t.map((x) => Math.ceil(x * 2 - 1e-9) / 2); // first run at or after the target
    assert(run[0] < 12 && run[1] < 18 && run[2] < 23, `runs ${run}`);
    assert(run[1] - run[0] >= GAP_H && run[2] - run[1] >= GAP_H, `run gap ${run}`);
  }
});

Deno.test("due: only once the member's time has come, once per window, 3 h after the last", () => {
  const id = base.id;
  const day = "2026-10-07";
  const [m, a, e] = plan(id, day);
  const atH = (h: number) => clock(Date.parse(`${day}T00:00:00+08:00`) + h * 3600e3);
  assertEquals(due(id, atH(m - 0.1), [], null).slot, null, "before the morning time");
  assertEquals(due(id, atH(m + 0.01), [], null).slot, 1);
  assertEquals(due(id, atH(m + 0.01), [1], null).slot, null, "morning already sent");
  assertEquals(due(id, atH(a + 0.01), [1], atH(m).ms).slot, 2);
  assertEquals(due(id, atH(a + 0.01), [1], atH(a - 1).ms).slot, null, "sent an hour ago (a test, a late run)");
  assertEquals(due(id, atH(e + 0.01), [1, 2], atH(a).ms).slot, 3);
  assertEquals(due(id, atH(23.2), [], null).slot, null, "23:00-08:00 is quiet");
  assertEquals(due(id, atH(7.5), [], null).slot, null);
  assertEquals(due(id, atH(12.5), [], null).slot, null, "12:00-13:00 gap");
});

// ------------------------------------------------------------- morning ---

Deno.test("morning: MET warning or a notable forecast first, max 3 forecast lines a week", () => {
  assertEquals(pickTrigger(base, rain, at("2026-10-07T08:30:00"), 1).trigger, "weather");
  assertEquals(pickTrigger(base, { ...rain, afternoon: null, morning: null, warning: "MET Malaysia thunderstorms warning" }, at("2026-10-07T08:30:00"), 1).trigger, "weather");
  const three = { ...base, nudges: ["2026-10-04", "2026-10-05", "2026-10-06"].map((d) => sentAt("weather", `fc:${d}`, `${d}T09:00:00`)) };
  assertEquals(pickTrigger(three, rain, at("2026-10-07T08:30:00"), 1).trigger, "fact", "3 forecast lines this week: a fact instead");
  assertEquals(pickTrigger(three, { ...rain, warning: "x" }, at("2026-10-07T08:30:00"), 1).trigger, "weather", "a warning still goes");
  assertEquals(pickTrigger(base, null, at("2026-10-07T08:30:00"), 1).trigger, "fact", "nothing: a good-morning fact");
});

Deno.test("morning: a joined meet today, an hour away, not reminded", () => {
  const m = { id: "e1", title: "Friday Night TT", venue: "Bangsar", starts_at: iso("2026-10-07T21:00:00"), going: true, reminded_today: false };
  assertEquals(pickTrigger({ ...base, meets_today: [m] }, null, at("2026-10-07T10:00:00"), 1).trigger, "meet");
  assertEquals(pickTrigger({ ...base, meets_today: [m] }, rain, at("2026-10-07T10:00:00"), 1).trigger, "weather", "weather first");
  assertEquals(pickTrigger({ ...base, meets_today: [{ ...m, reminded_today: true }] }, null, at("2026-10-07T10:00:00"), 1).trigger, "fact");
});

Deno.test("morning: doc after 09:30, never on a reminder day, once per paper, no car model", () => {
  const d = { car_id: "c1", model: "Myvi", kind: "road_tax" as const, due: "2026-10-10", days: 3 };
  const c = { ...base, docs: [d] };
  assertEquals(pickTrigger(c, null, at("2026-10-07T09:00:00"), 1).trigger, "fact");
  const p = pickTrigger(c, null, at("2026-10-07T10:00:00"), 1);
  assertEquals(p.trigger, "doc");
  assertEquals((p.facts as any).paper.when, "in 3 days");
  assert(!JSON.stringify(p.facts).includes("Myvi"), "the car's model is not in the facts");
  assertEquals(pickTrigger({ ...c, doc_pinged_today: true }, null, at("2026-10-07T10:00:00"), 1).trigger, "fact");
  assertEquals(pickTrigger({ ...c, nudges: [sentAt("doc", p.ref!, "2026-10-05T10:00:00")] }, null, at("2026-10-07T10:00:00"), 1).trigger, "fact");
});

// ----------------------------------------------------------- afternoon ---

Deno.test("afternoon: nearby tonight → friends out → points (Fri) → box → tip", () => {
  const near = { id: "n1", title: "Bangsar TT", type: "tt", venue: "Bangsar", starts_at: iso("2026-10-09T21:30:00"), km: 4.2, going: 6 };
  const fri = at("2026-10-09T14:00:00");
  const all = { ...base, nearby: [near], friends_out: { count: 2, names: ["Keith", "Lala"] }, post_done: false, boxes: ["b1"] };
  assertEquals(pickTrigger(all, null, fri, 2).trigger, "nearby");
  assertEquals((pickTrigger(all, null, fri, 2).facts as any).near_you_today.km_away, 4);
  assertEquals(pickTrigger({ ...all, nearby: [] }, null, fri, 2).trigger, "friends");
  assertEquals(pickTrigger({ ...all, nearby: [], friends_out: { count: 0, names: [] } }, null, fri, 2).trigger, "points");
  assertEquals(pickTrigger({ ...all, nearby: [], friends_out: { count: 0, names: [] } }, null, at("2026-10-09T17:50:00"), 2).trigger, "box", "after 17:45 no points line");
  assertEquals(pickTrigger({ ...all, nearby: [], friends_out: { count: 0, names: [] } }, null, at("2026-10-08T14:00:00"), 2).trigger, "box", "not Thursday");
  assertEquals(pickTrigger(base, null, fri, 2).trigger, "tip");
  // The same nearby meet isn't announced twice.
  assertEquals(pickTrigger({ ...base, nearby: [near], nudges: [sentAt("nearby", "near:n1", "2026-10-08T15:00:00")] }, null, fri, 2).trigger, "tip");
});

Deno.test("afternoon: a storm warning, unless the morning already talked weather", () => {
  const warn = { ...rain, warning: "MET Malaysia thunderstorms warning for the area until 8:00 PM" };
  assertEquals(pickTrigger(base, warn, at("2026-10-07T15:00:00"), 2).trigger, "weather");
  const morningWeather = { ...base, sent_today: [{ slot: 1, trigger: "weather" as const, sent_at: iso("2026-10-07T09:00:00") }] };
  assertEquals(pickTrigger(morningWeather, warn, at("2026-10-07T15:00:00"), 2).trigger, "tip");
  assertEquals(pickTrigger(base, rain, at("2026-10-07T15:00:00"), 2).trigger, "tip", "a forecast alone is morning-only");
});

// ------------------------------------------------------------- evening ---

Deno.test("evening: live now → Sunday recap → busy spot → joke", () => {
  const live = { id: "l1", title: "Sunday Night Meet", type: "meet", venue: "Plaza", km: 0.6, here: 12 };
  const busy = { id: "p1", name: "Kopi Garage", km: 3, checkins: 4, going: 0 };
  const sun = at("2026-10-11T20:00:00");
  const all = { ...base, live: [live], busy, week: { checkins: 2, points: 30 } };
  const p = pickTrigger(all, null, sun, 3);
  assertEquals(p.trigger, "live");
  assertEquals((p.facts as any).live_now.checked_in, 12);
  assertEquals((p.facts as any).live_now.km_away, "under 1");
  assertEquals(pickTrigger({ ...all, live: [] }, null, sun, 3).trigger, "recap");
  assertEquals(pickTrigger({ ...all, live: [] }, null, at("2026-10-10T20:00:00"), 3).trigger, "busy", "recap is Sunday only");
  assertEquals(pickTrigger({ ...all, live: [], week: { checkins: 0, points: 0 } }, null, sun, 3).trigger, "busy", "nothing to recap");
  assertEquals(pickTrigger(base, null, sun, 3).trigger, "joke");
});

// ------------------------------------------------------- once a day each ---

Deno.test("never the same trigger twice in a day; fun lines rotate", () => {
  const today = (t: Trigger, slot: number) => ({ slot, trigger: t, sent_at: iso("2026-10-07T09:00:00") });
  // A quiet day: fact, tip, joke.
  assertEquals(pickTrigger(base, null, at("2026-10-07T09:00:00"), 1).trigger, "fact");
  assertEquals(pickTrigger({ ...base, sent_today: [today("fact", 1)] }, null, at("2026-10-07T15:00:00"), 2).trigger, "tip");
  assertEquals(pickTrigger({ ...base, sent_today: [today("fact", 1), today("tip", 2)] }, null, at("2026-10-07T20:00:00"), 3).trigger, "joke");
  // The evening joke was somehow used already: another fun kind.
  assertEquals(pickTrigger({ ...base, sent_today: [today("joke", 1)] }, null, at("2026-10-07T20:00:00"), 3).trigger, "fact");
  // Friends out twice in a day: only once.
  const fr = { ...base, friends_out: { count: 1, names: ["Keith"] } };
  assertEquals(pickTrigger({ ...fr, sent_today: [today("friends", 2)] }, null, at("2026-10-07T16:00:00"), 2).trigger, "tip");
});

Deno.test("fun picks skip what they had in the last 30 days", () => {
  const nudges = CAR_FACTS.slice(0, CAR_FACTS.length - 1).map((_, i) => sentAt("fact", `fact:${i}`, `2026-10-0${1 + (i % 6)}T09:00:00`));
  const p = pickTrigger({ ...base, nudges }, null, at("2026-10-07T09:00:00"), 1);
  assertEquals(p.ref, `fact:${CAR_FACTS.length - 1}`, "the one fact they haven't had");
  for (const l of [CAR_FACTS, CAR_TIPS, CAR_JOKES]) assert(l.length >= 20 && l.every((x) => Array.from(x).length <= 130));
});

// --------------------------------------------------------------- lines ---

Deno.test("forecast terms", () => {
  assertEquals(forecastEn("Ribut petir di beberapa tempat"), "thunderstorms in some places");
  assertEquals(forecastEn("Hujan di kebanyakan tempat di kawasan pantai"), "rain in most places along the coast");
  assertEquals(forecastEn("Ribut petir menyeluruh"), "widespread thunderstorms");
  assertEquals(forecastEn("Tiada Hujan"), "no rain");
  assertEquals(forecastEn("Jerebu"), "haze");
  assert(rainy("Hujan"));
  assert(!rainy("Tiada hujan"));
  assert(!rainy("Mendung"));
  assert(notable("Jerebu") && !notable("Tiada hujan") && !notable("Cerah"));
});

Deno.test("warnings: whole state, or only the districts named", () => {
  const t = "1) Thunderstorms, heavy rain and strong winds are expected over the states of Perak (Muallim, Batang Padang and Manjung) • Selangor (Hulu Selangor and Sabak Bernam) until 12:00 AM; Wednesday. 2) Thunderstorms are expected over W.P. Kuala Lumpur • Johor until 1:00 AM.";
  assert(warningCovers(t, "Kuala Lumpur", ["Bangsar", "Kuala Lumpur"]));
  assert(warningCovers(t, "Johor", []));
  assert(warningCovers(t, "Selangor", ["Kuala Kubu Bharu", "Hulu Selangor"]));
  assert(!warningCovers(t, "Selangor", ["Petaling Jaya", "Petaling"]));
  assert(!warningCovers(t, "Penang", ["Georgetown"]));
});

Deno.test("cleanLine: length, links, AI talk, invented numbers, extra emoji, their car's name", () => {
  const facts = "road tax runs out in 3 days, 12 Oct";
  const car = ["Perodua", "Myvi"];
  assertEquals(cleanLine(`"Road tax in 3 days 🙌🙌"`, facts, car), "Road tax in 3 days 🙌");
  assertEquals(cleanLine("Renew by 15 Oct!", facts), null);
  assertEquals(cleanLine("As an AI, I care", facts), null);
  assertEquals(cleanLine("see https://jpj.gov.my", facts), null);
  assertEquals(cleanLine("#roadtax soon", facts), null);
  assertEquals(cleanLine("a".repeat(MAX_CHARS + 1), facts), null);
  assertEquals(cleanLine("路税3天后到期哦", facts), "路税3天后到期哦");
  assertEquals(cleanLine("Road tax for the Myvi in 3 days", facts, car), null, "names the car");
  assertEquals(cleanLine("Your Perodua's road tax is due in 3 days", facts, car), null);
  assertEquals(cleanLine("Road tax for your car is due in 3 days", facts, car), "Road tax for your car is due in 3 days");
  assertEquals(cleanLine("Fun fact: the Myvi first launched in 2005", "The Perodua Myvi first launched in 2005.", car), "Fun fact: the Myvi first launched in 2005", "fine when the fact itself is about it");
});

Deno.test("templates: every trigger, every language, fit and never name the car", () => {
  const facts: Record<string, Record<string, unknown>> = {
    weather: { weather: rain },
    meet: { meet: { title: "Night TT", starts: "today 9:30 PM" } },
    doc: { paper: { what: "road tax", when: "in 3 days" } },
    nearby: { near_you_today: { title: "Bangsar TT", starts: "today 9:30 PM", km_away: 4 } },
    friends: { friends_out_now: { count: 2, names: ["Keith", "Lala"] } },
    points: { points: {} },
    box: { blind_box: {} },
    live: { live_now: { title: "Plaza meet", km_away: 2, checked_in: 12 } },
    busy: { busy_spot: { name: "Kopi Garage", km_away: 3 } },
    recap: { this_week: { checkins: 2, points_earned: 30 } },
    fact: { car_fact: CAR_FACTS[2] },
    tip: { car_tip: CAR_TIPS[0] },
    joke: { joke: CAR_JOKES[0] },
  };
  for (const [trigger, f] of Object.entries(facts)) {
    for (const l of ["en", "zh", "ms"] as const) {
      const t = templateLine({ trigger: trigger as Trigger, ref: "x", facts: f }, l);
      assert(t.length > 5 && Array.from(t).length <= MAX_CHARS, `${trigger}/${l}: ${t}`);
      assert(!/Myvi|Perodua|undefined/.test(t), `${trigger}/${l}: ${t}`);
    }
  }
});

Deno.test("language", () => {
  assertEquals(langOf("有什么车聚今晚？"), "zh");
  assertEquals(langOf("ada meet tak malam ni kat Bangsar"), "ms");
  assertEquals(langOf("any meet tonight lah"), "en");
  assertEquals(detectLang(["今晚有车聚吗", "路税多少钱", "ok thanks"]), "zh");
  assertEquals(detectLang(["今晚有车聚吗", "where to eat", "ok thanks"]), "en");
  assertEquals(detectLang([]), "en");
});
