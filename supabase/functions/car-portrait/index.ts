// car-portrait
// AI portraits of a member's car through Kie.ai (GPT Image 2, image-to-image, 1K).
//
// Two entry points in one function:
//   1. App:  POST { carId, style }  (JWT)            → books a car_portraits row
//            through `request_car_portrait`, creates the Kie task with a
//            callBackUrl pointing back here, stores task_id, answers { portraitId }.
//   2. Kie:  POST ?callback=1&portrait=<id>&secret=<sig>  (no JWT; the secret is
//            an HMAC of the row id)                   → downloads the result,
//            uploads it to car-photos/<uid>/portraits/<carId>/<style>.<ext>,
//            marks the row ready (or failed), fronts the car with it when the
//            car has no portrait yet, and notifies the owner ('portrait').
//
// Deploy with `--no-verify-jwt` (the callback carries no JWT); the app path
// verifies the JWT itself, like verify-spot-photo does.
//
// Secrets: KIE_API_KEY (required), PORTRAIT_HOOK_SECRET (optional; falls back to
// KIE_API_KEY as the HMAC key), KIE_WEBHOOK_HMAC_KEY (optional; when set, Kie's
// X-Webhook-Signature is checked too).
//
// Kie shapes (docs.kie.ai/market/gpt/gpt-image-2-image-to-image):
//   POST https://api.kie.ai/api/v1/jobs/createTask   Authorization: Bearer <key>
//     { model: "gpt-image-2-image-to-image", callBackUrl,
//       input: { prompt, input_urls: string[] (≤16), aspect_ratio, resolution: "1K"|"2K"|"4K", background? } }
//     → { code: 200, msg, data: { taskId } }
//   Callback POST { code: 200|400|500|501, msg,
//     data: { taskId, state: "success"|"fail", resultJson: '{"resultUrls":[...]}', param, costTime, ... } }
//   GET https://api.kie.ai/api/v1/jobs/recordInfo?taskId=…  (same shape + failCode/failMsg; not used, we rely on the callback)
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const KIE_KEY = Deno.env.get("KIE_API_KEY") ?? "";
const HOOK_SECRET = Deno.env.get("PORTRAIT_HOOK_SECRET") || KIE_KEY;
const KIE_WEBHOOK_HMAC_KEY = Deno.env.get("KIE_WEBHOOK_HMAC_KEY") ?? "";

const KIE_CREATE = "https://api.kie.ai/api/v1/jobs/createTask";
const MODEL = "gpt-image-2-image-to-image";
const BUCKET = "car-photos";
const ASPECT = "4:3"; // the car page hero is 4:3; "auto" would also force 1K but crops unpredictably
const RESOLUTION = "1K";
const MAX_INPUTS = 3;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

// ------------------------------------------------------------- styles ---
// Mirror of kPortraitStyles in lib/features/profile/domain/portrait_style.dart.
// `reference` is an optional curated example image sent along with the car
// photos (left empty for now; fill in when we have references we like).
type Style = { name: string; description: string; look: string; reference: string };

const STYLES: Record<string, Style> = {
  showroom: {
    name: "Showroom",
    description: "Studio lights, glossy floor, nothing else in frame.",
    look: "a premium automotive studio shot: seamless dark grey backdrop, soft overhead softbox reflections along the body lines, glossy reflective floor, three-quarter front view, crisp commercial photography, no props",
    reference: "",
  },
  night_city: {
    name: "Night city",
    description: "Neon reflections on wet Kuala Lumpur streets.",
    look: "a cinematic night scene on a wet Kuala Lumpur street after rain: neon signs and city lights reflecting off the wet road and the paint, shallow depth of field, moody blue and magenta tones, low three-quarter angle",
    reference: "",
  },
  golden_hour: {
    name: "Golden hour",
    description: "Warm sunset light on an empty coastal road.",
    look: "a warm golden-hour photograph on an empty coastal road: low sun behind the car creating soft rim light and long shadows, warm orange and amber tones, light haze, calm sea and palm trees far in the background",
    reference: "",
  },
  race_poster: {
    name: "Race poster",
    description: "Bold motorsport poster with motion streaks.",
    look: "a bold motorsport poster illustration: dynamic low angle, strong motion streaks and speed lines behind the car, dramatic high-contrast lighting, punchy saturated colours, graphic halftone shading, poster composition with clean empty space around the car",
    reference: "",
  },
  pastel_dream: {
    name: "Pastel dream",
    description: "Soft pastel colours, dreamy and minimal.",
    look: "a dreamy minimal art-print style: soft pastel colour palette (peach, mint, lavender), flat pastel sky, gentle diffused light, very clean minimal background, slightly stylised but the car stays true to life",
    reference: "",
  },
  film: {
    name: "35mm film",
    description: "Grainy analogue photo, faded colours.",
    look: "an analogue 35mm film photograph from the 1990s: visible fine grain, slightly faded colours with lifted blacks, warm Kodak-like tones, natural daylight, a quiet suburban street, light vignette, nostalgic",
    reference: "",
  },
  track_day: {
    name: "Track day",
    description: "On the circuit, panning shot, tyres working.",
    look: "an action panning photograph on a race circuit like Sepang: the car sharp with motion blur on the tarmac and the background, kerbs and grandstand blurred behind, overcast bright daylight, wheels showing rotation blur, sense of speed",
    reference: "",
  },
  line_art: {
    name: "Line art",
    description: "Clean technical line drawing on white.",
    look: "a clean technical line drawing: fine black ink lines on a plain white background, no colour fill except very light grey shading, blueprint-like precision, side-front three-quarter view, every body line and panel gap drawn accurately",
    reference: "",
  },
};

type CarRow = { id: string; owner_id: string; make: string; model: string; year: number | null; color: string | null; photo_urls: string[] | null; portrait_url: string | null };

function buildPrompt(car: CarRow, style: Style): string {
  const bits = [car.year ? String(car.year) : "", car.make, car.model].filter(Boolean).join(" ");
  // The colour field is typed by hand and often wrong; the photo is the truth.
  return [
    `Recreate this exact car, a ${bits}, as ${style.look}.`,
    "Keep the exact paint colour and finish of the car in the reference photo (do not recolour it), and the same body shape, proportions, wheels, trim, badges and every visible detail; do not change the model or restyle the car.",
    "Remove the number plate or leave it blank. No people, no text, no logos or watermarks added.",
    "Single car, centred, whole car in frame, 1K output.",
  ].join(" ");
}

// -------------------------------------------------------------- crypto ---

async function hmacHex(key: string, message: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmacBase64(key: string, message: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const signPortrait = (id: string) => hmacHex(HOOK_SECRET, `portrait:${id}`);

// --------------------------------------------------------------- create ---

async function handleCreate(req: Request): Promise<Response> {
  const auth = req.headers.get("Authorization") ?? "";
  const asUser = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData.user) return json({ error: "Not signed in" }, 401);
  const me = userData.user.id;

  let carId: string | undefined;
  let style: string | undefined;
  try {
    ({ carId, style } = await req.json());
  } catch {
    /* fallthrough */
  }
  if (!carId || !style) return json({ error: "carId and style required" }, 400);
  const st = STYLES[style];
  if (!st) return json({ error: "Unknown style" }, 400);
  if (!KIE_KEY) return json({ error: "Portraits are not set up yet. Try again later." }, 503);

  const { data: car, error: carErr } = await admin
    .from("cars")
    .select("id, owner_id, make, model, year, color, photo_urls, portrait_url")
    .eq("id", carId)
    .maybeSingle<CarRow>();
  if (carErr || !car) return json({ error: "Car not found" }, 404);
  if (car.owner_id !== me) return json({ error: "That car is not in your garage" }, 403);
  const photos = (car.photo_urls ?? []).filter((u) => typeof u === "string" && u.startsWith("http"));
  if (!photos.length) return json({ error: "Add a photo of the car first" }, 400);

  // Limits (one pending per car, N per day) live in the RPC; it runs as the member.
  const { data: portraitId, error: rpcErr } = await asUser.rpc("request_car_portrait", { p_car: carId, p_style: style });
  if (rpcErr || !portraitId) return json({ error: rpcErr?.message ?? "Could not start the portrait" }, 400);

  const secret = await signPortrait(portraitId);
  const callBackUrl = `${SUPABASE_URL}/functions/v1/car-portrait?callback=1&portrait=${portraitId}&secret=${secret}`;
  const inputUrls = [...photos.slice(0, MAX_INPUTS), ...(st.reference ? [st.reference] : [])];

  let taskId: string | undefined;
  let failure: string | undefined;
  try {
    const res = await fetch(KIE_CREATE, {
      method: "POST",
      headers: { Authorization: `Bearer ${KIE_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        callBackUrl,
        input: { prompt: buildPrompt(car, st), input_urls: inputUrls, aspect_ratio: ASPECT, resolution: RESOLUTION },
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok || body?.code !== 200 || !body?.data?.taskId) {
      failure = `kie ${body?.code ?? res.status}: ${String(body?.msg ?? "no task id").slice(0, 200)}`;
    } else {
      taskId = String(body.data.taskId);
    }
  } catch (e) {
    failure = `kie unreachable: ${String(e).slice(0, 200)}`;
  }

  if (!taskId) {
    await admin.from("car_portraits").update({ status: "failed", error: failure ?? "Could not start the portrait" }).eq("id", portraitId);
    return json({ error: "The studio is busy right now. Try again in a bit.", detail: failure }, 502);
  }
  await admin.from("car_portraits").update({ task_id: taskId }).eq("id", portraitId);
  return json({ portraitId, taskId });
}

// ------------------------------------------------------------- callback ---

type PortraitRow = { id: string; car_id: string; owner_id: string; style: string; status: string; task_id: string | null };

async function handleCallback(req: Request, url: URL): Promise<Response> {
  const portraitId = url.searchParams.get("portrait") ?? "";
  const secret = url.searchParams.get("secret") ?? "";
  if (!portraitId || !secret || !safeEqual(secret, await signPortrait(portraitId))) return json({ error: "forbidden" }, 403);

  // deno-lint-ignore no-explicit-any
  const body: any = await req.json().catch(() => ({}));
  const data = body?.data ?? {};
  const taskId: string = String(data.taskId ?? data.task_id ?? "");

  // Optional second lock: Kie's own HMAC (enable webhookHmacKey on kie.ai/settings and set KIE_WEBHOOK_HMAC_KEY).
  if (KIE_WEBHOOK_HMAC_KEY) {
    const ts = req.headers.get("x-webhook-timestamp") ?? "";
    const sig = req.headers.get("x-webhook-signature") ?? "";
    const expect = await hmacBase64(KIE_WEBHOOK_HMAC_KEY, `${taskId}.${ts}`);
    if (!ts || !sig || !safeEqual(sig, expect)) return json({ error: "bad signature" }, 401);
  }

  const { data: row } = await admin
    .from("car_portraits")
    .select("id, car_id, owner_id, style, status, task_id")
    .eq("id", portraitId)
    .maybeSingle<PortraitRow>();
  if (!row) return json({ error: "unknown portrait" }, 404);
  if (row.status !== "pending") return json({ ok: true, already: row.status }); // Kie may retry; be idempotent
  if (row.task_id && taskId && row.task_id !== taskId) return json({ error: "task mismatch" }, 409);

  const fail = async (why: string) => {
    await admin.from("car_portraits").update({ status: "failed", error: why.slice(0, 300) }).eq("id", row.id);
    return json({ ok: true, failed: why });
  };

  const state = String(data.state ?? "");
  if (body?.code !== 200 || state !== "success") {
    const why = String(data.failMsg ?? body?.msg ?? `Kie ${body?.code ?? "?"} ${state}`);
    return await fail(why || "Generation failed");
  }

  let resultUrl: string | undefined;
  try {
    const rj = typeof data.resultJson === "string" ? JSON.parse(data.resultJson) : data.resultJson ?? {};
    resultUrl = rj?.resultUrls?.[0];
  } catch {
    /* fallthrough */
  }
  if (!resultUrl) return await fail("No image in the result");

  // Result URLs expire after ~24 h, so copy the image into our bucket now.
  let bytes: Uint8Array;
  let contentType: string;
  try {
    const r = await fetch(resultUrl);
    if (!r.ok) throw new Error(`download ${r.status}`);
    contentType = (r.headers.get("content-type") ?? "image/png").split(";")[0].trim();
    bytes = new Uint8Array(await r.arrayBuffer());
  } catch (e) {
    return await fail(`Could not fetch the image: ${String(e).slice(0, 120)}`);
  }
  if (!["image/jpeg", "image/png", "image/webp"].includes(contentType)) contentType = "image/png";
  const ext = contentType === "image/jpeg" ? "jpg" : contentType === "image/webp" ? "webp" : "png";
  const path = `${row.owner_id}/portraits/${row.car_id}/${row.style}.${ext}`;

  const { error: upErr } = await admin.storage.from(BUCKET).upload(path, bytes, { contentType, upsert: true });
  if (upErr) return await fail(`Could not save the image: ${upErr.message.slice(0, 120)}`);
  // Same path per style → cache-bust so a re-run of the same style shows the new image.
  const publicUrl = `${admin.storage.from(BUCKET).getPublicUrl(path).data.publicUrl}?v=${Date.now()}`;

  await admin.from("car_portraits").update({ status: "ready", url: publicUrl, error: null, ready_at: new Date().toISOString() }).eq("id", row.id);

  // First portrait of a car fronts it straight away; later ones wait for "Use as car picture".
  const { data: car } = await admin.from("cars").select("portrait_url").eq("id", row.car_id).maybeSingle();
  if (car && !car.portrait_url) await admin.from("cars").update({ portrait_url: publicUrl }).eq("id", row.car_id);

  await admin.rpc("notify", { p_user: row.owner_id, p_actor: null, p_type: "portrait", p_body: row.car_id });
  return json({ ok: true });
}

// ---------------------------------------------------------------- serve ---

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const url = new URL(req.url);
  try {
    if (url.searchParams.get("callback") === "1") return await handleCallback(req, url);
    return await handleCreate(req);
  } catch (e) {
    console.error("car-portrait", e);
    return json({ error: "Something went wrong" }, 500);
  }
});
