// moderate-content
// Automatic check of every new post and moment (Apple 1.2: apps with user
// content must filter objectionable material, not only offer report/block).
// Called by Postgres (migration 0103: AFTER INSERT triggers → pg_net, plus a
// one-minute sweep for anything that never got an answer) with
// { table: 'posts' | 'stories', id } and the shared secret header.
//
// Looks at the photos (grid thumbnails where they exist), the video still,
// and the title / caption / poll text with OpenAI's free moderation model,
// then writes the verdict through moderation_apply(): 'ok', or 'flagged'
// (hidden from everyone but the author and admins until an admin decides).
// Thresholds and why: decide.ts.
//
// Fails OPEN: when OpenAI is down or times out the item becomes 'ok' and the
// reason says "Not checked: …" (also logged here). A broken checker must not
// make every new post vanish; reports + block stay as the second line, and
// admins can find unchecked items by that reason.
//
// Secrets: OPENAI_API_KEY, MODERATION_HOOK_SECRET (same value as the Vault
// secret moderation_hook_secret). Deploy with --no-verify-jwt: Postgres sends
// no JWT, this function checks the secret itself.
import { createClient } from "npm:@supabase/supabase-js@2";
import { decide, inputsOf } from "./decide.ts";
import { checkAll, MODEL } from "./check.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const HOOK_SECRET = Deno.env.get("MODERATION_HOOK_SECRET") ?? "";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const COLUMNS: Record<string, string> = {
  posts: "id, moderation, photo_urls, video_poster_url, title, caption, poll_options, guide_stops",
  stories: "id, moderation, photo_url, caption",
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!HOOK_SECRET || req.headers.get("x-moderation-secret") !== HOOK_SECRET) return json({ error: "forbidden" }, 403);

  let table = "";
  let id = "";
  try {
    ({ table, id } = await req.json());
  } catch {
    /* fallthrough */
  }
  if (!COLUMNS[table] || !id) return json({ error: "table and id required" }, 400);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data, error } = await admin.from(table).select(COLUMNS[table]).eq("id", id).maybeSingle();
  if (error) return json({ error: error.message }, 500);
  const row = data as Record<string, unknown> | null;
  if (!row) return json({ skipped: "gone" });
  if (row.moderation !== "pending") return json({ skipped: row.moderation });

  const started = Date.now();
  const { images, text } = inputsOf(table, row);
  const v = OPENAI_KEY
    ? decide(await checkAll(images, text, { key: OPENAI_KEY, supabaseUrl: SUPABASE_URL, fetch }))
    : { verdict: "ok" as const, reason: "Not checked: OPENAI_API_KEY is not set", categories: { scores: {}, hits: [], checked: 0, failed: images.length + (text ? 1 : 0) } };
  const ms = Date.now() - started;

  const { error: applyErr } = await admin.rpc("moderation_apply", {
    p_table: table,
    p_id: id,
    p_verdict: v.verdict,
    p_reason: v.reason,
    p_categories: { ...v.categories, model: MODEL, ms },
  });
  if (applyErr) {
    console.error(`moderate-content ${table} ${id}: apply failed: ${applyErr.message}`);
    return json({ error: applyErr.message }, 500);
  }
  const line = `moderate-content ${table} ${id}: ${v.verdict} in ${ms} ms (${images.length} photos${text ? " + text" : ""})${v.reason ? ` · ${v.reason}` : ""}`;
  if (v.categories.failed > 0) console.error(line);
  else console.log(line);
  return json({ verdict: v.verdict, reason: v.reason, ms });
});
