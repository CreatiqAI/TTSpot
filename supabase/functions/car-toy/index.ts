// car-toy
// One die-cast toy render per car, made from its cover photo with Kie.ai
// (GPT Image 2 image-to-image, 1K, transparent background). Free for the
// member and automatic: migration 0106 books a `car_toy_jobs` row when a car
// is saved or its cover changes (or on request_car_toy) and POSTs here
// through pg_net; nothing in the app waits for Kie.
//
// Three entry points in one function:
//   1. Postgres:  POST { jobId }  header x-toy-secret   → answers 202 at once,
//      then (EdgeRuntime.waitUntil) creates the Kie task with the approved
//      die-cast prompt (retrying 429 bursts with backoff) and stores task_id.
//      The same post for a job that already has a task id polls Kie's
//      recordInfo instead (toy_sweep() does this when a callback never came).
//   2. Kie:  POST ?callback=1&job=<id>&secret=<hmac>  → downloads the result,
//      cleans the fringe (clean.ts: alpha cut, crop, 800 px wide), uploads it
//      to car-photos/<uid>/toys/<car>/<ts>.png (immutable, long cache), marks
//      the job ready and the car too, unless a newer cover or job took over
//      (then the job is 'stale' and the file is dropped).
//   3. App (JWT): POST { carId, manual? }  → runs request_car_toy as the
//      member and answers { jobId } (null when nothing to do). The app calls
//      the RPC directly; this is a convenience for tools and tests.
//
// Deploy with --no-verify-jwt (Postgres and Kie send no JWT).
// Secrets: KIE_API_KEY, TOY_HOOK_SECRET (same value as Vault toy_hook_secret;
// also the HMAC key for the callback URL).
import { createClient } from "npm:@supabase/supabase-js@2";
import { cleanToy, EmptyImageError } from "./clean.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const KIE_KEY = Deno.env.get("KIE_API_KEY") ?? "";
const HOOK_SECRET = Deno.env.get("TOY_HOOK_SECRET") ?? "";

const KIE_CREATE = "https://api.kie.ai/api/v1/jobs/createTask";
const KIE_RECORD = "https://api.kie.ai/api/v1/jobs/recordInfo";
const MODEL = "gpt-image-2-image-to-image";
const BUCKET = "car-photos";
/** Kie 429s bursts; wait these many ms before each retry. */
const RETRY_DELAYS_MS = [4000, 12000, 30000];

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

// -------------------------------------------------------------- prompt ---
// Style A "die-cast" from design/toy_car/gen1.py (the owner's pick), result
// design/toy_car/a911_c.png. The photo is the truth for model and colour;
// make/model go in as a hint only.
const TAIL = " Front three-quarter view from slightly above, the nose pointing to the lower left, the whole car visible." +
  " No brand logos, no badges, no letters, no numbers, a blank number plate. No base, no packaging, no ground, no cast shadow." +
  " Soft even studio light. Isolated on a transparent background, centred.";
const DIE_CAST = "Turn the car in the photo into a premium die-cast toy car, like a 1:64 scale collectible miniature: the exact same car model," +
  " the same body shape and wheel design, and exactly the same paint colour as in the photo. Slightly simplified details, a thick glossy" +
  " painted metal body, dark tinted plastic windows, simple moulded lights, rubber-look tyres.";

type CarRow = { id: string; owner_id: string; make: string; model: string; photo_urls: string[] | null; toy_task: string | null; toy_url: string | null };
type JobRow = { id: string; car_id: string; owner_id: string; source: string; status: string; task_id: string | null };

export function buildPrompt(car: Pick<CarRow, "make" | "model">): string {
  const name = [car.make, car.model].map((s) => (s ?? "").trim()).filter(Boolean).join(" ");
  const hint = name ? ` The car in the photo is a ${name}.` : "";
  return DIE_CAST + hint + TAIL;
}

// -------------------------------------------------------------- crypto ---

async function hmacHex(key: string, message: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const signJob = (id: string) => hmacHex(HOOK_SECRET, `toy:${id}`);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- jobs ---

async function loadJob(jobId: string): Promise<JobRow | null> {
  const { data } = await admin.from("car_toy_jobs").select("id, car_id, owner_id, source, status, task_id").eq("id", jobId).maybeSingle<JobRow>();
  return data ?? null;
}

async function failJob(job: JobRow, why: string): Promise<void> {
  console.error(`car-toy job ${job.id.slice(0, 8)} failed: ${why}`);
  const { data } = await admin
    .from("car_toy_jobs")
    .update({ status: "failed", error: why.slice(0, 300) })
    .eq("id", job.id)
    .eq("status", "pending")
    .select("id");
  if (!data?.length) return; // already decided by someone else
  await admin.from("cars").update({ toy_status: "failed" }).eq("id", job.car_id).eq("toy_task", job.id);
}

/** Creates the Kie task for a job with none yet. */
async function createTask(job: JobRow): Promise<void> {
  if (!KIE_KEY) return await failJob(job, "KIE_API_KEY not set");
  const { data: car } = await admin.from("cars").select("id, owner_id, make, model, photo_urls, toy_task, toy_url").eq("id", job.car_id).maybeSingle<CarRow>();
  if (!car) return await failJob(job, "Car is gone");
  const secret = await signJob(job.id);
  const callBackUrl = `${SUPABASE_URL}/functions/v1/car-toy?callback=1&job=${job.id}&secret=${secret}`;
  const body = JSON.stringify({
    model: MODEL,
    callBackUrl,
    input: { prompt: buildPrompt(car), input_urls: [job.source], aspect_ratio: "1:1", resolution: "1K", background: "transparent" },
  });

  const t0 = Date.now();
  let failure = "";
  for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
    if (attempt > 0) await sleep(RETRY_DELAYS_MS[attempt - 1]);
    let status = 0;
    try {
      const res = await fetch(KIE_CREATE, { method: "POST", headers: { Authorization: `Bearer ${KIE_KEY}`, "content-type": "application/json" }, body });
      status = res.status;
      // deno-lint-ignore no-explicit-any
      const out: any = await res.json().catch(() => ({}));
      const taskId = out?.data?.taskId;
      if (res.ok && out?.code === 200 && taskId) {
        // The job may have been failed by the sweep meanwhile: only a pending job takes the task.
        const { data } = await admin.from("car_toy_jobs").update({ task_id: String(taskId) }).eq("id", job.id).eq("status", "pending").select("id");
        console.log(`car-toy job ${job.id.slice(0, 8)} task ${String(taskId).slice(0, 12)} after ${attempt + 1} tries, ${Date.now() - t0} ms${data?.length ? "" : " (job no longer pending)"}`);
        return;
      }
      failure = `kie ${out?.code ?? status}: ${String(out?.msg ?? "no task id").slice(0, 200)}`;
      const retry = status === 429 || out?.code === 429 || status >= 500;
      if (!retry) break;
    } catch (e) {
      failure = `kie unreachable: ${String(e).slice(0, 200)}`;
    }
  }
  await failJob(job, failure || "Could not start the toy");
}

/** Asks Kie how a task is doing (for jobs whose callback never came). */
async function pollTask(job: JobRow): Promise<void> {
  try {
    const res = await fetch(`${KIE_RECORD}?taskId=${encodeURIComponent(job.task_id!)}`, { headers: { Authorization: `Bearer ${KIE_KEY}` } });
    // deno-lint-ignore no-explicit-any
    const out: any = await res.json().catch(() => ({}));
    const data = out?.data ?? {};
    const state = String(data.state ?? "");
    console.log(`car-toy job ${job.id.slice(0, 8)} poll: ${state || out?.code || res.status}`);
    if (state === "success") return await finishJob(job, resultUrlOf(data), "poll");
    if (state === "fail") return await failJob(job, String(data.failMsg ?? data.failCode ?? "Generation failed"));
  } catch (e) {
    console.error(`car-toy job ${job.id.slice(0, 8)} poll error`, String(e).slice(0, 200));
  }
}

// deno-lint-ignore no-explicit-any
function resultUrlOf(data: any): string | undefined {
  try {
    const rj = typeof data.resultJson === "string" ? JSON.parse(data.resultJson) : data.resultJson ?? {};
    const u = rj?.resultUrls?.[0];
    return typeof u === "string" ? u : undefined;
  } catch {
    return undefined;
  }
}

function pathInBucket(publicUrl: string | null): string | null {
  if (!publicUrl) return null;
  const prefix = `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/`;
  if (!publicUrl.startsWith(prefix)) return null;
  return decodeURIComponent(publicUrl.slice(prefix.length).split("?")[0]);
}

/** Downloads, cleans, stores; marks the job and (when still current) the car. */
async function finishJob(job: JobRow, resultUrl: string | undefined, via: string): Promise<void> {
  if (!resultUrl) return await failJob(job, "No image in the result");
  const t0 = Date.now();
  let raw: Uint8Array;
  try {
    const r = await fetch(resultUrl);
    if (!r.ok) throw new Error(`download ${r.status}`);
    raw = new Uint8Array(await r.arrayBuffer());
  } catch (e) {
    return await failJob(job, `Could not fetch the image: ${String(e).slice(0, 120)}`);
  }
  const t1 = Date.now();

  let png: Uint8Array;
  let reportText = "";
  try {
    const { png: cleaned, report } = await cleanToy(raw);
    if (report.coverage < 0.05) throw new Error("Almost nothing in the image");
    png = cleaned;
    reportText = JSON.stringify(report);
  } catch (e) {
    return await failJob(job, e instanceof EmptyImageError ? "Empty render" : `Clean-up failed: ${String(e).slice(0, 120)}`);
  }
  const t2 = Date.now();

  const path = `${job.owner_id}/toys/${job.car_id}/${Date.now()}.png`;
  const { error: upErr } = await admin.storage.from(BUCKET).upload(path, png, { contentType: "image/png", cacheControl: "31536000", upsert: false });
  if (upErr) return await failJob(job, `Could not save the image: ${upErr.message.slice(0, 120)}`);
  const url = admin.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
  const t3 = Date.now();

  // Only a pending job finishes; a second finisher (callback + poll) drops its copy.
  const { data: won } = await admin
    .from("car_toy_jobs")
    .update({ status: "ready", url, error: null, ready_at: new Date().toISOString() })
    .eq("id", job.id)
    .eq("status", "pending")
    .select("id");
  if (!won?.length) {
    await admin.storage.from(BUCKET).remove([path]);
    console.log(`car-toy job ${job.id.slice(0, 8)} finished twice (${via}); dropped the copy`);
    return;
  }

  // The car takes the toy only while this job is its current one and the
  // cover it was made from is still the cover (a stale callback for an older
  // photo must not overwrite a newer toy).
  const { data: car } = await admin.from("cars").select("id, owner_id, make, model, photo_urls, toy_task, toy_url").eq("id", job.car_id).maybeSingle<CarRow>();
  const current = !!car && car.toy_task === job.id && (car.photo_urls?.[0] ?? "") === job.source;
  if (!current) {
    await admin.from("car_toy_jobs").update({ status: "stale", url: null }).eq("id", job.id);
    await admin.storage.from(BUCKET).remove([path]);
    console.log(`car-toy job ${job.id.slice(0, 8)} stale (${via}): car moved on`);
    return;
  }
  await admin
    .from("cars")
    .update({ toy_url: url, toy_status: "ready", toy_source: job.source, toy_ready_at: new Date().toISOString() })
    .eq("id", job.car_id)
    .eq("toy_task", job.id);
  const old = pathInBucket(car!.toy_url);
  if (old && old !== path && old.includes("/toys/")) await admin.storage.from(BUCKET).remove([old]).catch(() => {});
  console.log(`car-toy job ${job.id.slice(0, 8)} ready (${via}): download ${t1 - t0} ms, clean ${t2 - t1} ms, upload ${t3 - t2} ms, raw ${raw.byteLength} B, ${reportText}`);
}

// ---------------------------------------------------------------- hook ---

async function handleHook(req: Request): Promise<Response> {
  const secret = req.headers.get("x-toy-secret") ?? "";
  if (!HOOK_SECRET || !safeEqual(secret, HOOK_SECRET)) return json({ error: "forbidden" }, 403);
  // deno-lint-ignore no-explicit-any
  const body: any = await req.json().catch(() => ({}));
  const jobId = String(body?.jobId ?? "");
  if (!jobId) return json({ error: "jobId required" }, 400);

  const work = (async () => {
    try {
      const job = await loadJob(jobId);
      if (!job) return console.warn(`car-toy unknown job ${jobId}`);
      if (job.status !== "pending") return;
      if (job.task_id) await pollTask(job);
      else await createTask(job);
    } catch (e) {
      console.error("car-toy hook", String(e).slice(0, 300));
    }
  })();
  // Answer Postgres at once; Kie's createTask alone can take 40 s.
  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime;
  if (rt?.waitUntil) rt.waitUntil(work);
  else await work;
  return json({ accepted: true, jobId }, 202);
}

// ------------------------------------------------------------- callback ---

async function handleCallback(req: Request, url: URL): Promise<Response> {
  const jobId = url.searchParams.get("job") ?? "";
  const secret = url.searchParams.get("secret") ?? "";
  if (!jobId || !secret || !HOOK_SECRET || !safeEqual(secret, await signJob(jobId))) return json({ error: "forbidden" }, 403);

  // deno-lint-ignore no-explicit-any
  const body: any = await req.json().catch(() => ({}));
  const data = body?.data ?? {};
  const taskId = String(data.taskId ?? data.task_id ?? "");

  const job = await loadJob(jobId);
  if (!job) return json({ error: "unknown job" }, 404);
  if (job.status !== "pending") return json({ ok: true, already: job.status }); // Kie may retry
  if (job.task_id && taskId && job.task_id !== taskId) return json({ error: "task mismatch" }, 409);

  const state = String(data.state ?? "");
  if (body?.code !== 200 || state !== "success") {
    await failJob(job, String(data.failMsg ?? body?.msg ?? `Kie ${body?.code ?? "?"} ${state}`) || "Generation failed");
    return json({ ok: true, failed: true });
  }
  await finishJob(job, resultUrlOf(data), "callback");
  return json({ ok: true });
}

// ------------------------------------------------------------------ app ---

async function handleApp(req: Request): Promise<Response> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Not signed in" }, 401);
  const asUser = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData.user) return json({ error: "Not signed in" }, 401);
  // deno-lint-ignore no-explicit-any
  const body: any = await req.json().catch(() => ({}));
  const carId = String(body?.carId ?? "");
  if (!carId) return json({ error: "carId required" }, 400);
  const { data, error } = await asUser.rpc("request_car_toy", { p_car: carId, p_manual: body?.manual === true });
  if (error) return json({ error: error.message }, 400);
  return json({ jobId: data ?? null });
}

// ---------------------------------------------------------------- serve ---

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const url = new URL(req.url);
  try {
    if (url.searchParams.get("callback") === "1") return await handleCallback(req, url);
    if (req.headers.has("x-toy-secret")) return await handleHook(req);
    return await handleApp(req);
  } catch (e) {
    console.error("car-toy", e);
    return json({ error: "Something went wrong" }, 500);
  }
});
