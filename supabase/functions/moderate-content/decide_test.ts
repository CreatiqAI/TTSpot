// deno test supabase/functions/moderate-content/
// The flag rules against made-up moderation API answers: no real
// objectionable content is used or needed.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { type Checked, decide, inputsOf, THRESHOLDS, thumbOf } from "./decide.ts";
import { checkAll, type Deps } from "./check.ts";

const CATS = [
  "harassment", "harassment/threatening", "hate", "hate/threatening", "illicit", "illicit/violent",
  "self-harm", "self-harm/intent", "self-harm/instructions", "sexual", "sexual/minors", "violence", "violence/graphic",
];

/** A moderation result: every category tiny, except [over]. */
function result(over: Record<string, number> = {}) {
  const category_scores: Record<string, number> = {};
  for (const c of CATS) category_scores[c] = 0.0003;
  Object.assign(category_scores, over);
  return { flagged: false, categories: {}, category_scores };
}

const ok = (source: string, over: Record<string, number> = {}): Checked => ({ source, result: result(over) });

Deno.test("a normal car photo and caption are ok", () => {
  const v = decide([ok("photo"), ok("text")]);
  assertEquals(v.verdict, "ok");
  assertEquals(v.reason, null);
  assertEquals(v.categories.hits, []);
  assertEquals(v.categories.checked, 2);
  assertEquals(v.categories.failed, 0);
});

Deno.test("sexual on the second photo flags and names it", () => {
  const v = decide([ok("photo 1"), ok("photo 2", { sexual: 0.93 }), ok("text")]);
  assertEquals(v.verdict, "flagged");
  assertEquals(v.categories.hits, ["sexual"]);
  assertStringIncludes(v.reason!, "sexual 0.93 (photo 2)");
});

Deno.test("each watched category flags at its threshold and not just under it", () => {
  for (const [cat, t] of Object.entries(THRESHOLDS)) {
    assertEquals(decide([ok("photo", { [cat]: t })]).verdict, "flagged", `${cat} at ${t}`);
    assertEquals(decide([ok("photo", { [cat]: t - 0.01 })]).verdict, "ok", `${cat} just under ${t}`);
  }
});

Deno.test("plain violence, harassment and illicit never flag (car banter, crash photos)", () => {
  const v = decide([ok("photo", { violence: 0.97 }), ok("text", { harassment: 0.9, illicit: 0.8, "illicit/violent": 0.7 })]);
  assertEquals(v.verdict, "ok");
  assertEquals(v.reason, null);
});

Deno.test("sexual/minors is the strictest", () => {
  assertEquals(decide([ok("text", { "sexual/minors": 0.12 })]).verdict, "flagged");
  assertEquals(decide([ok("text", { "sexual/minors": 0.05 })]).verdict, "ok");
});

Deno.test("several hits are listed worst first", () => {
  const v = decide([ok("photo", { "violence/graphic": 0.7 }), ok("text", { hate: 0.95 })]);
  assertEquals(v.categories.hits, ["hate", "violence/graphic"]);
  assertStringIncludes(v.reason!, "hate 0.95 (text), violence/graphic 0.70 (photo)");
});

Deno.test("the API failing for everything fails open with a reason", () => {
  const v = decide([{ source: "photo", error: "openai 503: down" }, { source: "text", error: "timeout" }]);
  assertEquals(v.verdict, "ok");
  assertStringIncludes(v.reason!, "Not checked");
  assertStringIncludes(v.reason!, "openai 503");
  assertEquals(v.categories.failed, 2);
});

Deno.test("a partial failure stays ok without a hit, but a hit elsewhere still flags", () => {
  const clean = decide([ok("photo 1"), { source: "photo 2", error: "openai 500" }]);
  assertEquals(clean.verdict, "ok");
  assertStringIncludes(clean.reason!, "Partly checked (1 of 2 failed)");
  const bad = decide([ok("photo 1", { sexual: 0.8 }), { source: "photo 2", error: "openai 500" }]);
  assertEquals(bad.verdict, "flagged");
});

Deno.test("nothing to check is ok", () => {
  assertEquals(decide([]).verdict, "ok");
});

Deno.test("scores are stored rounded, highest per category", () => {
  const v = decide([ok("photo 1", { sexual: 0.123456 }), ok("photo 2", { sexual: 0.2 })]);
  assertEquals(v.categories.scores.sexual, 0.2);
  assertEquals(decide([ok("p", { sexual: 0.123456 })]).categories.scores.sexual, 0.1235);
});

// ------------------------------------------------------------- inputs ---

const SB = "https://ref.supabase.co";
const PUB = `${SB}/storage/v1/object/public`;

Deno.test("thumbOf mirrors the app's thumbnail names", () => {
  assertEquals(thumbOf(`${PUB}/post-photos/u/posts/1.jpg`, SB), `${PUB}/post-photos/u/posts/1_t.jpg`);
  assertEquals(thumbOf(`${PUB}/car-photos/u/1_0.png`, SB), `${PUB}/car-photos/u/1_0_t.jpg`);
  assertEquals(thumbOf(`${PUB}/post-photos/u/posts/1_t.jpg`, SB), null);
  assertEquals(thumbOf(`${PUB}/chat-media/u/1.jpg`, SB), null);
  assertEquals(thumbOf(`${PUB}/post-photos/u/1.jpg?v=2`, SB), null);
  assertEquals(thumbOf("https://upload.wikimedia.org/x.jpg", SB), null);
});

Deno.test("inputsOf: post photos, video still, poll photos and all the text", () => {
  const { images, text } = inputsOf("posts", {
    photo_urls: ["https://a/1.jpg", "https://a/1.jpg", "https://a/2.jpg"],
    video_poster_url: "https://a/v.jpg",
    title: "Which wheels?",
    caption: "My Myvi",
    poll_options: [{ text: "TE37", photo_url: "https://a/p.jpg" }, { text: "RPF1", photo_url: null }],
    guide_stops: [{ name: "Genting" }],
  });
  assertEquals(images, ["https://a/1.jpg", "https://a/2.jpg", "https://a/v.jpg", "https://a/p.jpg"]);
  assertEquals(text, "Which wheels?\nMy Myvi\nTE37\nRPF1\nGenting");
});

Deno.test("inputsOf: a moment is its photo (or video still) and caption", () => {
  assertEquals(inputsOf("stories", { photo_url: "https://a/m.jpg", caption: " at Togeya " }), { images: ["https://a/m.jpg"], text: "at Togeya" });
});

// ------------------------------------------------------- API (mocked) ---

type Call = { url: string; method: string; body?: any };

/** A fake fetch: [answer] decides each moderation reply; thumbnails exist when [thumbs]. */
function fakeFetch(answer: (body: any, n: number) => Response, thumbs = true) {
  const calls: Call[] = [];
  let n = 0;
  const f = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    calls.push({ url, method, body });
    if (method === "HEAD") return new Response(null, { status: thumbs ? 200 : 404 });
    if (url.includes("api.openai.com")) return answer(body, n++);
    return new Response(new Uint8Array([0xff, 0xd8, 0xff]), { status: 200, headers: { "content-type": "image/jpeg" } });
  }) as typeof fetch;
  return { f, calls };
}

const reply = (over: Record<string, number> = {}) => new Response(JSON.stringify({ results: [result(over)] }), { status: 200 });
const deps = (f: typeof fetch): Deps => ({ key: "k", supabaseUrl: SB, fetch: f, retryDelayMs: 1 });

Deno.test("checkAll sends the thumbnail when there is one, and the text on its own", async () => {
  const { f, calls } = fakeFetch(() => reply());
  const out = await checkAll([`${PUB}/post-photos/u/posts/1.jpg`], "My Myvi", deps(f));
  assertEquals(out.map((c) => c.source).sort(), ["photo", "text"]);
  const sent = calls.filter((c) => c.url.includes("openai")).map((c) => c.body);
  assertEquals(sent.every((b) => b.model === "omni-moderation-latest"), true);
  assert(sent.some((b) => Array.isArray(b.input) && b.input[0].image_url.url.endsWith("1_t.jpg")));
  assert(sent.some((b) => b.input === "My Myvi"));
  assertEquals(decide(out).verdict, "ok");
});

Deno.test("checkAll falls back to the full photo without a thumbnail", async () => {
  const { f, calls } = fakeFetch(() => reply(), false);
  await checkAll([`${PUB}/post-photos/u/posts/1.jpg`], "", deps(f));
  const img = calls.find((c) => c.url.includes("openai"))!.body.input[0].image_url.url;
  assertEquals(img, `${PUB}/post-photos/u/posts/1.jpg`);
});

Deno.test("a 503 is retried once, then the answer counts", async () => {
  const { f } = fakeFetch((_, n) => (n === 0 ? new Response("down", { status: 503 }) : reply({ sexual: 0.91 })));
  const out = await checkAll(["https://elsewhere/x.jpg"], "", deps(f));
  assertEquals(decide(out).verdict, "flagged");
});

Deno.test("two failures in a row fail open", async () => {
  const { f } = fakeFetch(() => new Response("down", { status: 500 }));
  const v = decide(await checkAll(["https://elsewhere/x.jpg"], "caption", deps(f)));
  assertEquals(v.verdict, "ok");
  assertStringIncludes(v.reason!, "Not checked");
});

Deno.test("a 400 (image not downloadable) is retried with the bytes", async () => {
  const { f, calls } = fakeFetch((body) =>
    String(body.input[0].image_url.url).startsWith("data:image/jpeg;base64,") ? reply() : new Response("bad image", { status: 400 })
  );
  const out = await checkAll(["https://elsewhere/x.jpg"], "", deps(f));
  assertEquals(out[0].error, undefined);
  assertEquals(calls.filter((c) => c.url.includes("openai")).length, 2);
});

Deno.test("a timeout is caught, not thrown", async () => {
  const f = (async (_: string | URL | Request, init?: RequestInit) => {
    if (init?.method === "HEAD") return new Response(null, { status: 404 });
    throw new DOMException("The signal has been aborted", "TimeoutError");
  }) as typeof fetch;
  const v = decide(await checkAll(["https://elsewhere/x.jpg"], "", deps(f)));
  assertEquals(v.verdict, "ok");
  assertStringIncludes(v.reason!, "aborted");
});
