// Talking to OpenAI's moderation endpoint (omni-moderation-latest: free,
// takes image URLs and text). One request per photo plus one for the text,
// all at once, so one bad photo among ten is found and named. `fetch` is
// passed in so decide_test.ts can answer for the API.
import { type Checked, type ModerationResult, thumbOf } from "./decide.ts";

export const MODEL = "omni-moderation-latest";
const ENDPOINT = "https://api.openai.com/v1/moderations";

export type Deps = {
  key: string;
  supabaseUrl: string;
  fetch: typeof fetch;
  /** Per API request. */
  timeoutMs?: number;
  /** Pause before the one retry on 429 / 5xx / timeout. */
  retryDelayMs?: number;
};

class ApiError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

async function call(input: unknown, d: Deps): Promise<ModerationResult> {
  const res = await d.fetch(ENDPOINT, {
    method: "POST",
    headers: { Authorization: `Bearer ${d.key}`, "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, input }),
    signal: AbortSignal.timeout(d.timeoutMs ?? 12000),
  });
  if (!res.ok) throw new ApiError(res.status, `openai ${res.status}: ${(await res.text()).slice(0, 160)}`);
  const data = await res.json();
  const r = data?.results?.[0];
  if (!r?.category_scores) throw new ApiError(0, "openai: no results");
  return r as ModerationResult;
}

const retryable = (e: unknown) => !(e instanceof ApiError) || e.status === 0 || e.status === 429 || e.status >= 500;

/** One retry for rate limits, server errors and timeouts. */
async function callWithRetry(input: unknown, d: Deps): Promise<ModerationResult> {
  try {
    return await call(input, d);
  } catch (e) {
    if (!retryable(e)) throw e;
    await new Promise((r) => setTimeout(r, d.retryDelayMs ?? 800));
    return await call(input, d);
  }
}

/** The grid thumbnail when it exists (a fraction of the bytes), else the photo. */
export async function pickImageUrl(url: string, d: Deps): Promise<string> {
  const thumb = thumbOf(url, d.supabaseUrl);
  if (!thumb) return url;
  try {
    const res = await d.fetch(thumb, { method: "HEAD", signal: AbortSignal.timeout(3000) });
    await res.body?.cancel();
    return res.ok ? thumb : url;
  } catch {
    return url;
  }
}

/** For a photo OpenAI couldn't download itself: send the bytes (up to 4 MB). */
async function asDataUrl(url: string, d: Deps): Promise<string> {
  const res = await d.fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`download ${res.status}`);
  const bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes.length > 4 * 1024 * 1024) throw new Error("photo too large to send");
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  const type = res.headers.get("content-type")?.split(";")[0] || "image/jpeg";
  return `data:${type};base64,${btoa(bin)}`;
}

async function checkImage(url: string, source: string, d: Deps): Promise<Checked> {
  const use = await pickImageUrl(url, d);
  try {
    return { source, result: await callWithRetry([{ type: "image_url", image_url: { url: use } }], d) };
  } catch (e) {
    // 400 is usually "couldn't fetch the image": try once with the bytes.
    if (e instanceof ApiError && e.status === 400) {
      try {
        return { source, result: await call([{ type: "image_url", image_url: { url: await asDataUrl(use, d) } }], d) };
      } catch (e2) {
        return { source, error: String((e2 as Error).message ?? e2).slice(0, 160) };
      }
    }
    return { source, error: String((e as Error).message ?? e).slice(0, 160) };
  }
}

async function checkText(text: string, d: Deps): Promise<Checked> {
  try {
    return { source: "text", result: await callWithRetry(text, d) };
  } catch (e) {
    return { source: "text", error: String((e as Error).message ?? e).slice(0, 160) };
  }
}

/** Every photo and the text, in parallel. Never throws: failures come back as `error`. */
export function checkAll(images: string[], text: string, d: Deps): Promise<Checked[]> {
  return Promise.all([
    ...images.map((u, i) => checkImage(u, images.length === 1 ? "photo" : `photo ${i + 1}`, d)),
    ...(text.trim() ? [checkText(text, d)] : []),
  ]);
}
