// recognize-car
// The app sends one car photo and gets back what car it is (Malaysian-market
// naming), a body colour bucket, a short spec line and where the number plate
// sits, so the phone can blur the plate before the photo is stored.
//
// Input (one of):
//   { photoUrl }  a public URL in our own storage bucket
//   { image }     a data:image/...;base64 URL of the bytes — the app uses this
//                 so the unblurred original never has to be uploaded first
//
// Output:
//   { make, model, yearFrom, yearTo, color, bodyStyle, confidence, specLine,
//     plate: { found, box: [x0, y0, x1, y1] | null } }   (box is 0-1 fractions)
//
// Secrets: OPENAI_API_KEY (required), OPENAI_VISION_MODEL (optional).
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY");
const MODEL = Deno.env.get("OPENAI_VISION_MODEL") ?? "gpt-4o-mini";

const COLORS = ["red", "black", "white", "grey", "silver", "blue", "yellow", "green", "orange"];
const MAX_IMAGE_CHARS = 8 * 1024 * 1024; // ~6 MB of image as base64

type Raw = {
  make: string;
  model: string;
  year_from: number;
  year_to: number;
  color: string;
  body_style: string;
  confidence: number;
  spec_line: string;
  plate_found: boolean;
  plate_x0: number;
  plate_y0: number;
  plate_x1: number;
  plate_y1: number;
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const PROMPT =
  "You identify cars for TT Spot, a Malaysian car-community app. Name the car the way Malaysians do: " +
  "Perodua Myvi, Perodua Axia, Perodua Ativa, Proton Saga, Proton X50, Proton Persona, Honda Civic FC, " +
  "Honda City GN, Toyota Vios, Toyota Hilux, Mazda 3 BP, Nissan Almera, BMW 3 Series G20, Mercedes-Benz C-Class W205, " +
  "Hyundai Elantra, Volkswagen Golf MK7 and so on.\n" +
  "make: the brand only. model: the model name plus the generation code or nickname Malaysians use when you can tell " +
  "(e.g. 'Civic FC', 'Myvi 3rd gen', 'Saga FLX'). If it is not a car, or you cannot tell, use empty strings and a low confidence.\n" +
  "year_from / year_to: the production years of that generation or facelift as sold in Malaysia (the same number twice " +
  "if you are sure of one year, 0 for both if unknown).\n" +
  "color: the paint's nearest bucket out of red, black, white, grey, silver, blue, yellow, green, orange " +
  "(silver = light metallic, grey = dark or gunmetal), or unknown.\n" +
  "body_style: one of hatchback, sedan, SUV, MPV, pickup, coupe, convertible, wagon, van, or empty.\n" +
  "spec_line: a short factory spec line for the common variant like '1.5 L NA · 102 hp · CVT' or '2.0 L turbo · 261 hp · 7-speed DCT', " +
  "only if you are reasonably sure; otherwise an empty string.\n" +
  "confidence: 0 to 1 for the make and model together.\n" +
  "Number plate: if a registration plate is visible (even partly, even blurry), set plate_found true and give its bounding box " +
  "as fractions of the image width and height: plate_x0, plate_y0 for the top-left corner, plate_x1, plate_y1 for the bottom-right. " +
  "Be a little generous so the whole plate including its frame is inside the box. If there is no plate, plate_found false and zeros. " +
  "Never transcribe the plate.";

async function askOpenAI(imageUrl: string): Promise<Raw> {
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      input: [{
        role: "user",
        content: [
          { type: "input_text", text: PROMPT },
          { type: "input_image", image_url: imageUrl, detail: "high" },
        ],
      }],
      text: {
        format: {
          type: "json_schema",
          name: "car_recognition",
          strict: true,
          schema: {
            type: "object",
            properties: {
              make: { type: "string" },
              model: { type: "string" },
              year_from: { type: "integer" },
              year_to: { type: "integer" },
              color: { type: "string", enum: [...COLORS, "unknown"] },
              body_style: { type: "string" },
              confidence: { type: "number" },
              spec_line: { type: "string" },
              plate_found: { type: "boolean" },
              plate_x0: { type: "number" },
              plate_y0: { type: "number" },
              plate_x1: { type: "number" },
              plate_y1: { type: "number" },
            },
            required: [
              "make", "model", "year_from", "year_to", "color", "body_style", "confidence", "spec_line",
              "plate_found", "plate_x0", "plate_y0", "plate_x1", "plate_y1",
            ],
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
  return JSON.parse(text) as Raw;
}

const clamp01 = (n: unknown) => Math.min(1, Math.max(0, Number(n) || 0));
const str = (s: unknown, max: number) => (typeof s === "string" ? s.trim().slice(0, max) : "");
const year = (n: unknown) => {
  const y = Math.round(Number(n) || 0);
  return y >= 1950 && y <= new Date().getFullYear() + 1 ? y : null;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // Who is calling? (JWT is verified by the gateway; we still want a real user.)
  const auth = req.headers.get("Authorization") ?? "";
  const asUser = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } } });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData.user) return json({ error: "Not signed in" }, 401);

  let photoUrl: string | undefined;
  let image: string | undefined;
  try {
    ({ photoUrl, image } = await req.json());
  } catch {
    /* fallthrough */
  }

  let imageUrl: string;
  if (typeof image === "string" && image.length > 0) {
    if (!/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/.test(image)) return json({ error: "image must be a base64 data URL" }, 400);
    if (image.length > MAX_IMAGE_CHARS) return json({ error: "image too large" }, 413);
    imageUrl = image;
  } else if (typeof photoUrl === "string" && photoUrl.length > 0) {
    // Only look at our own public bucket; never fetch arbitrary URLs for the caller.
    if (!photoUrl.startsWith(`${SUPABASE_URL}/storage/v1/object/public/`)) return json({ error: "photoUrl must be in our storage" }, 400);
    imageUrl = photoUrl;
  } else {
    return json({ error: "photoUrl or image required" }, 400);
  }

  if (!OPENAI_KEY) return json({ error: "Car recognition is not configured" }, 503);

  let raw: Raw;
  try {
    raw = await askOpenAI(imageUrl);
  } catch (e) {
    console.error("recognize-car", String(e).slice(0, 300));
    return json({ error: "Could not look at the photo right now" }, 502);
  }

  const make = str(raw.make, 40);
  const model = str(raw.model, 60);
  const confidence = make && model ? clamp01(raw.confidence) : 0;
  const color = COLORS.includes(raw.color) ? raw.color : null;

  let box: number[] | null = null;
  if (raw.plate_found) {
    const x0 = clamp01(raw.plate_x0), y0 = clamp01(raw.plate_y0), x1 = clamp01(raw.plate_x1), y1 = clamp01(raw.plate_y1);
    const b = [Math.min(x0, x1), Math.min(y0, y1), Math.max(x0, x1), Math.max(y0, y1)];
    if (b[2] - b[0] > 0.005 && b[3] - b[1] > 0.005) box = b;
  }

  return json({
    make,
    model,
    yearFrom: year(raw.year_from),
    yearTo: year(raw.year_to),
    color,
    bodyStyle: str(raw.body_style, 30),
    confidence,
    specLine: str(raw.spec_line, 80),
    plate: { found: box !== null, box },
    model_used: MODEL,
  });
});
