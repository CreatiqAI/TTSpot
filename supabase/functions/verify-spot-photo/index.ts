// verify-spot-photo
// Called by the app right after `submit_spot_verification`. Looks at the photo
// with OpenAI, then approves / rejects / holds the check-in for a human.
//
// Decision (lenient by design, the user asked for that):
//   car present + looks like a real photo + distance within 300 m  → approved
//   clearly no car, or clearly a screenshot / screen / print       → rejected
//   anything else (no GPS, far away, low confidence, API trouble)  → review
//
// Secrets: OPENAI_API_KEY (required), OPENAI_VISION_MODEL (optional).
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY");
const MODEL = Deno.env.get("OPENAI_VISION_MODEL") ?? "gpt-4o-mini";

const MAX_DISTANCE_M = 300;

type Check = { car_present: boolean; looks_real_photo: boolean; confidence: number; note: string };

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

async function askOpenAI(photoUrl: string): Promise<Check> {
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      input: [{
        role: "user",
        content: [
          {
            type: "input_text",
            text:
              "You verify check-in photos for a Malaysian car-meet app. Say whether the photo shows a real car " +
              "(any car, any angle, partial is fine) photographed in the real world, and whether it instead looks " +
              "like a screenshot, a photo of a screen, a printed picture, or a drawing. Be lenient about quality, " +
              "lighting and framing. confidence is 0 to 1.",
          },
          { type: "input_image", image_url: photoUrl, detail: "low" },
        ],
      }],
      text: {
        format: {
          type: "json_schema",
          name: "car_check",
          strict: true,
          schema: {
            type: "object",
            properties: {
              car_present: { type: "boolean" },
              looks_real_photo: { type: "boolean" },
              confidence: { type: "number" },
              note: { type: "string" },
            },
            required: ["car_present", "looks_real_photo", "confidence", "note"],
            additionalProperties: false,
          },
        },
      },
    }),
  });
  if (!res.ok) throw new Error(`openai ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const data = await res.json();
  const text: string | undefined = data.output_text ??
    data.output?.flatMap((o: any) => o.content ?? []).find((c: any) => c.type === "output_text")?.text;
  if (!text) throw new Error("openai: empty output");
  return JSON.parse(text) as Check;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // Who is calling? (JWT is verified by the gateway; we still need the user id.)
  const auth = req.headers.get("Authorization") ?? "";
  const asUser = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } } });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData.user) return json({ error: "Not signed in" }, 401);

  let id: string | undefined;
  try {
    ({ id } = await req.json());
  } catch {
    /* fallthrough */
  }
  if (!id) return json({ error: "id required" }, 400);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data: v, error: vErr } = await admin.from("spot_verifications").select("*").eq("id", id).maybeSingle();
  if (vErr || !v) return json({ error: "Not found" }, 404);
  if (v.user_id !== userData.user.id) return json({ error: "Not yours" }, 403);
  if (v.status !== "pending") return json({ status: v.status, reason: v.reason });

  // No key configured → straight to the human queue rather than failing the user.
  if (!OPENAI_KEY) {
    await admin.rpc("hold_spot_verification", { p_id: id, p_reason: "Photo check not configured", p_ai: null });
    return json({ status: "review", reason: "We'll check your photo within 24 hours." });
  }

  let check: Check;
  try {
    check = await askOpenAI(v.photo_url);
  } catch (e) {
    await admin.rpc("hold_spot_verification", { p_id: id, p_reason: "Photo check unavailable", p_ai: { error: String(e).slice(0, 300) } });
    return json({ status: "review", reason: "We'll check your photo within 24 hours." });
  }

  const ai = { ...check, model: MODEL, distance_m: v.distance_m };
  const near = typeof v.distance_m === "number" && v.distance_m <= MAX_DISTANCE_M;
  const confident = check.confidence >= 0.6;

  if (check.car_present && check.looks_real_photo && confident && near) {
    await admin.rpc("decide_spot_verification", { p_id: id, p_approve: true, p_reason: "Auto-approved: car in photo, at the spot", p_by: null, p_ai: ai });
    const { data: rule } = await admin.from("point_rules").select("points").eq("reason", "spot_verified").maybeSingle();
    return json({ status: "approved", points: rule?.points ?? 0, reason: check.note });
  }
  if (confident && (!check.car_present || !check.looks_real_photo)) {
    const reason = !check.car_present ? "No car in the photo" : "Photo looks like a screenshot or a picture of a picture";
    await admin.rpc("decide_spot_verification", { p_id: id, p_approve: false, p_reason: reason, p_by: null, p_ai: ai });
    return json({ status: "rejected", reason });
  }
  const why = !near
    ? (typeof v.distance_m === "number" ? `You were ${v.distance_m} m from the spot` : "No location with the photo")
    : "Couldn't tell for sure from the photo";
  await admin.rpc("hold_spot_verification", { p_id: id, p_reason: why, p_ai: ai });
  return json({ status: "review", reason: `${why}. A human will check within 24 hours.` });
});
