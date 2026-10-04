// The part of moderate-content that decides: which OpenAI moderation scores
// hide a post or moment for a human to look at. Pure, so decide_test.ts can
// run it against made-up API answers (no real objectionable content needed).
//
// Scores are omni-moderation-latest category_scores (0 to 1, roughly "how
// likely this is"). We don't use the API's own `flagged`: it also fires on
// plain "violence", "harassment" and "illicit", which a car app trips all the
// time ("killer exhaust", crash photos, "this Myvi murdered the GTR").
//
// A flag is not a deletion: the post is hidden from everyone but its author
// and admins until an admin approves or removes it. So a false alarm costs a
// member a short wait, while a miss puts the material in front of everyone.
// That is why the thresholds sit a little below 0.5 where a miss is serious.
//
//   sexual                  0.50  nudity / porn in photos or text
//   sexual/minors           0.10  text only; strictest, any real signal goes to a human
//   violence/graphic        0.50  gore (plain "violence" is ignored: crashes, burnouts)
//   self-harm (+intent, +instructions)  0.40
//   hate                    0.60  text only; car banter scores low, slurs score high
//   hate/threatening        0.40  text only

export const THRESHOLDS: Readonly<Record<string, number>> = {
  "sexual": 0.5,
  "sexual/minors": 0.1,
  "violence/graphic": 0.5,
  "self-harm": 0.4,
  "self-harm/intent": 0.4,
  "self-harm/instructions": 0.4,
  "hate": 0.6,
  "hate/threatening": 0.4,
};

/** One entry of the moderation API's `results`. */
export type ModerationResult = {
  flagged?: boolean;
  categories?: Record<string, boolean>;
  category_scores: Record<string, number>;
  category_applied_input_types?: Record<string, string[]>;
};

/** What was checked ("photo 1", "text") and what the API said, or why it failed. */
export type Checked = { source: string; result?: ModerationResult; error?: string };

export type Verdict = {
  verdict: "ok" | "flagged";
  /** Short, for the admin queue; null when everything was checked and clean. */
  reason: string | null;
  /** Stored in moderation_categories. */
  categories: {
    scores: Record<string, number>;
    hits: string[];
    checked: number;
    failed: number;
  };
};

const round = (n: number) => Math.round(n * 10000) / 10000;

/**
 * Highest score per category over every photo and the text; flagged when any
 * watched category reaches its threshold. Inputs that failed are counted:
 * with no hit among the rest the result is 'ok' (fail open) and the reason
 * says what could not be checked.
 */
export function decide(checked: Checked[]): Verdict {
  const scores: Record<string, number> = {};
  const from: Record<string, string> = {};
  let failed = 0;
  const errors: string[] = [];
  for (const c of checked) {
    if (!c.result) {
      failed++;
      if (c.error) errors.push(`${c.source}: ${c.error}`);
      continue;
    }
    for (const [cat, raw] of Object.entries(c.result.category_scores ?? {})) {
      const s = typeof raw === "number" && Number.isFinite(raw) ? raw : 0;
      if (scores[cat] === undefined || s > scores[cat]) {
        scores[cat] = s;
        from[cat] = c.source;
      }
    }
  }
  const hits = Object.keys(THRESHOLDS)
    .filter((cat) => (scores[cat] ?? 0) >= THRESHOLDS[cat])
    .sort((a, b) => (scores[b] ?? 0) - (scores[a] ?? 0));
  const rounded: Record<string, number> = {};
  for (const [cat, s] of Object.entries(scores)) rounded[cat] = round(s);
  const categories = { scores: rounded, hits, checked: checked.length - failed, failed };

  if (hits.length > 0) {
    const what = hits.map((h) => `${h} ${rounded[h].toFixed(2)} (${from[h]})`).join(", ");
    return { verdict: "flagged", reason: `Flagged: ${what}`, categories };
  }
  if (failed > 0) {
    const all = failed === checked.length;
    const head = all ? "Not checked" : `Partly checked (${failed} of ${checked.length} failed)`;
    return { verdict: "ok", reason: `${head}: ${errors.join("; ").slice(0, 300) || "no answer"}`, categories };
  }
  return { verdict: "ok", reason: null, categories };
}

// ------------------------------------------------------------- inputs ---

/** Buckets whose photos have a `_t.jpg` grid thumbnail (lib/core/utils/thumbnails.dart). */
const THUMB_BUCKETS = new Set(["post-photos", "car-photos", "event-covers"]);

/**
 * `…/public/post-photos/uid/posts/1.png` → `…/public/post-photos/uid/posts/1_t.jpg`,
 * or null when the photo can't have one (another host or bucket, a `?v=` URL,
 * a thumbnail already). Mirrors thumbUrl() in the app.
 */
export function thumbOf(url: string, supabaseUrl: string): string | null {
  const prefix = `${supabaseUrl}/storage/v1/object/public/`;
  if (!supabaseUrl || !url.startsWith(prefix) || url.includes("?")) return null;
  const rest = url.substring(prefix.length);
  const slash = rest.indexOf("/");
  if (slash < 0 || !THUMB_BUCKETS.has(rest.substring(0, slash)) || rest.endsWith("_t.jpg")) return null;
  const dot = rest.lastIndexOf(".");
  const stem = dot > rest.lastIndexOf("/") ? rest.substring(0, dot) : rest;
  return `${prefix}${stem}_t.jpg`;
}

/** Most photos we send per item (a post holds up to 10 plus a video still and poll photos). */
export const MAX_IMAGES = 12;

/** A post's or moment's photos (deduped, capped) and its text. */
export function inputsOf(table: string, row: Record<string, unknown>): { images: string[]; text: string } {
  const images: string[] = [];
  const add = (u: unknown) => {
    if (typeof u === "string" && u.startsWith("http") && !images.includes(u) && images.length < MAX_IMAGES) images.push(u);
  };
  const texts: string[] = [];
  const say = (t: unknown) => {
    if (typeof t === "string" && t.trim()) texts.push(t.trim());
  };
  if (table === "posts") {
    for (const u of (row.photo_urls as unknown[] | null) ?? []) add(u);
    add(row.video_poster_url);
    say(row.title);
    say(row.caption);
    for (const o of (row.poll_options as Record<string, unknown>[] | null) ?? []) {
      say(o?.text);
      add(o?.photo_url);
    }
    for (const s of (row.guide_stops as Record<string, unknown>[] | null) ?? []) say(s?.name);
  } else {
    add(row.photo_url);
    say(row.caption);
  }
  return { images, text: texts.join("\n").slice(0, 4000) };
}
