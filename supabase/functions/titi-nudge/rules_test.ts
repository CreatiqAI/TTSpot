// deno test supabase/functions/titi-nudge/rules_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { detectLang, langOf } from "../_shared/lang.ts";
import { cleanLine, clock, type Ctx, forecastEn, MAX_CHARS, pickTrigger, rainy, templateLine, warningCovers, type WeatherFacts } from "./rules.ts";

// 2026-10-07 is a Wednesday; 2026-10-09 a Friday. Times below are MYT.
const at = (s: string) => clock(Date.parse(`${s}+08:00`));

const base: Ctx = {
  name: "Aiman", home_state: "Kuala Lumpur", titi_tips: true, titi_lang: null, has_token: true, pushes_24h: 0, nudged_today: false,
  car: { make: "Perodua", model: "Myvi", color: "white", year: null }, location: null, recent: [],
  meets_today: [], docs: [], doc_pinged_today: false, boxes: [], week_key: "2026-10-02", post_done: true, nudges: [],
};
const rain: WeatherFacts = { area: "Petaling Jaya", morning: null, afternoon: "thunderstorms in some places", warning: null, temp: "25-34°C" };

Deno.test("weather: rainy forecast in the morning, not after 11", () => {
  assertEquals(pickTrigger(base, rain, at("2026-10-07T08:30:00"))?.trigger, "weather");
  assertEquals(pickTrigger(base, rain, at("2026-10-07T11:30:00")), null);
});

Deno.test("weather: forecast rain at most twice a week; a warning still goes", () => {
  const c = { ...base, nudges: [
    { trigger: "weather" as const, ref: "rain:2026-10-05", sent_at: "2026-10-05T01:00:00Z" },
    { trigger: "weather" as const, ref: "rain:2026-10-06", sent_at: "2026-10-06T01:00:00Z" },
  ] };
  assertEquals(pickTrigger(c, rain, at("2026-10-07T08:30:00")), null);
  assertEquals(pickTrigger(c, { ...rain, warning: "storm" }, at("2026-10-07T15:00:00"))?.trigger, "weather");
});

Deno.test("meet: today, an hour away, not reminded", () => {
  const m = { id: "e1", title: "Friday Night TT", venue: "Bangsar", starts_at: "2026-10-07T13:00:00Z", going: true, reminded_today: false };
  assertEquals(pickTrigger({ ...base, meets_today: [m] }, null, at("2026-10-07T10:00:00"))?.trigger, "meet");
  assertEquals(pickTrigger({ ...base, meets_today: [{ ...m, reminded_today: true }] }, null, at("2026-10-07T10:00:00")), null);
  assertEquals(pickTrigger({ ...base, meets_today: [m] }, null, at("2026-10-07T20:30:00"))?.trigger, "fun", "starts within the hour: not the meet");
});

Deno.test("doc: after 09:30, never on a reminder day, once per paper", () => {
  const d = { car_id: "c1", model: "Myvi", kind: "road_tax" as const, due: "2026-10-10", days: 3 };
  const c = { ...base, docs: [d] };
  assertEquals(pickTrigger(c, null, at("2026-10-07T09:00:00")), null);
  const p = pickTrigger(c, null, at("2026-10-07T10:00:00"));
  assertEquals(p?.trigger, "doc");
  assertEquals((p?.facts as any).paper.when, "in 3 days");
  assertEquals(pickTrigger({ ...c, doc_pinged_today: true }, null, at("2026-10-07T10:00:00")), null);
  assertEquals(pickTrigger({ ...c, nudges: [{ trigger: "doc", ref: p!.ref, sent_at: "2026-10-05T03:00:00Z" }] }, null, at("2026-10-07T10:00:00")), null);
});

Deno.test("box after noon; Friday points before 17:30", () => {
  assertEquals(pickTrigger({ ...base, boxes: ["b1"] }, null, at("2026-10-07T11:00:00")), null);
  assertEquals(pickTrigger({ ...base, boxes: ["b1"] }, null, at("2026-10-07T13:00:00"))?.trigger, "box");
  const fri = { ...base, post_done: false };
  assertEquals(pickTrigger(fri, null, at("2026-10-09T14:00:00"))?.trigger, "points");
  assertEquals(pickTrigger(fri, null, at("2026-10-09T17:45:00"))?.trigger, "fun");
  assertEquals(pickTrigger(fri, null, at("2026-10-08T14:00:00")), null, "not Thursday");
});

Deno.test("fun: evenings, never two days running, at most 3 a week", () => {
  assertEquals(pickTrigger(base, null, at("2026-10-07T16:00:00")), null);
  assertEquals(pickTrigger(base, null, at("2026-10-07T18:00:00"))?.trigger, "fun");
  const yesterday = { ...base, nudges: [{ trigger: "fun" as const, ref: "checkin", sent_at: "2026-10-06T10:00:00Z" }] };
  assertEquals(pickTrigger(yesterday, null, at("2026-10-07T18:00:00")), null);
  const three = { ...base, nudges: ["2026-10-01", "2026-10-03", "2026-10-05"].map((d) => ({ trigger: "fun" as const, ref: "checkin", sent_at: `${d}T10:00:00Z` })) };
  assertEquals(pickTrigger(three, null, at("2026-10-07T18:00:00")), null);
});

Deno.test("priority: weather beats the box", () => {
  assertEquals(pickTrigger({ ...base, boxes: ["b1"] }, { ...rain, warning: "x" }, at("2026-10-07T13:00:00"))?.trigger, "weather");
});

Deno.test("forecast terms", () => {
  assertEquals(forecastEn("Ribut petir di beberapa tempat"), "thunderstorms in some places");
  assertEquals(forecastEn("Hujan di kebanyakan tempat di kawasan pantai"), "rain in most places along the coast");
  assertEquals(forecastEn("Ribut petir menyeluruh"), "widespread thunderstorms");
  assertEquals(forecastEn("Tiada Hujan"), "no rain");
  assert(rainy("Hujan"));
  assert(!rainy("Tiada hujan"));
  assert(!rainy("Mendung"));
});

Deno.test("warnings: whole state, or only the districts named", () => {
  const t = "1) Thunderstorms, heavy rain and strong winds are expected over the states of Perak (Muallim, Batang Padang and Manjung) • Selangor (Hulu Selangor and Sabak Bernam) until 12:00 AM; Wednesday. 2) Thunderstorms are expected over W.P. Kuala Lumpur • Johor until 1:00 AM.";
  assert(warningCovers(t, "Kuala Lumpur", ["Bangsar", "Kuala Lumpur"]));
  assert(warningCovers(t, "Johor", []));
  assert(warningCovers(t, "Selangor", ["Kuala Kubu Bharu", "Hulu Selangor"]));
  assert(!warningCovers(t, "Selangor", ["Petaling Jaya", "Petaling"]));
  assert(!warningCovers(t, "Penang", ["Georgetown"]));
});

Deno.test("cleanLine: length, links, AI talk, invented numbers, extra emoji", () => {
  const facts = "road tax runs out in 3 days, 12 Oct";
  assertEquals(cleanLine(`"Road tax in 3 days 🙌🙌"`, facts), "Road tax in 3 days 🙌");
  assertEquals(cleanLine("Renew by 15 Oct!", facts), null);
  assertEquals(cleanLine("As an AI, I care", facts), null);
  assertEquals(cleanLine("see https://jpj.gov.my", facts), null);
  assertEquals(cleanLine("#roadtax soon", facts), null);
  assertEquals(cleanLine("a".repeat(MAX_CHARS + 1), facts), null);
  assertEquals(cleanLine("路税3天后到期哦", facts), "路税3天后到期哦");
});

Deno.test("templates fit and speak each language", () => {
  const p = { trigger: "weather" as const, ref: "x", facts: { weather: rain } };
  for (const l of ["en", "zh", "ms"] as const) {
    const t = templateLine(p, base, l);
    assert(Array.from(t).length <= MAX_CHARS);
    assert(t.includes("Petaling Jaya"));
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
