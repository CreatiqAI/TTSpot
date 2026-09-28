// recognize-car
// The app sends one car photo and gets back what car it is (Malaysian-market
// naming), a body colour bucket, a short spec line and where the number plate
// sits (the app no longer blurs plates, but the field stays in the response).
//
// Model choice (2026-09-29 bench: 8 photos, Myvi 3rd gen, X50 Flagship,
// Axia 2nd gen, Bezza 1.3 AV facelift, City GN RS, Civic FE, Vios NCP150 rear,
// Saga 3rd gen rear; same schema, detail "high", 8 calls in parallel):
//
//   model          prompt  model+gen  trim read  colour  median  max
//   gpt-4o-mini    old     5/8        -          8/8     4.3 s   4.8 s
//   gpt-4o-mini    new     8/8        2/3 (1 made up)  8/8  3.2 s  4.8 s
//   gpt-4.1        old     8/8        -          8/8     3.7 s   5.9 s
//   gpt-4.1        new     8/8 x2     3/3 x2     8/8 x2  3.0-3.3 s  3.7-4.3 s
//   gpt-5.4-mini   old     6/8 (X50->X70, Bezza->Saga)  8/8  2.0 s  2.5 s
//   gpt-5.4-mini   new     7/8 (Myvi->2nd gen)  3/3  7/8  2.3 s  2.6 s
//   gpt-5.4        old     8/8        -          6/8     2.5 s   3.1 s
//   gpt-5.4        new     7-8/8      1-2/3      6/8     2.5-2.7 s  3.2-3.8 s
//   gpt-5.4 low    new     7/8 (Myvi->Iriz)  3/3   7/8     4.8 s   6.1 s
//
// "old" = the previous prompt, "new" = the one below. gpt-5.4 kept calling a
// white Saga silver and a silver Vios grey; the minis confused look-alikes.
// gpt-4.1 was the only one right on every photo, twice, under ~4.5 s.
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
const MODEL = Deno.env.get("OPENAI_VISION_MODEL") ?? "gpt-4.1";

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

const THIS_YEAR = new Date().getFullYear();

const PROMPT =
  "You identify cars for TT Spot, a Malaysian car-community app. The photo was almost certainly taken in Malaysia, so think " +
  "of the Malaysian market first (Perodua, Proton, Honda, Toyota, Nissan, Mazda, Mitsubishi, BMW, Mercedes-Benz, Volkswagen, " +
  "Hyundai, Kia, BYD, Chery, Geely and so on) and name the car the way Malaysians do.\n" +
  "Before answering, look closely at every badge and emblem you can see: the brand emblem, the model script on the boot or " +
  "front (MYVI, AXIA, BEZZA, SAGA, PERSONA, X50, CITY, VIOS, CIVIC...) and any trim or engine badge (AV, H, G, X, SE, RS, V, E, " +
  "S, TGDi, Flagship, Premium, e:HEV, VTEC TURBO, GR Sport...). Readable badges beat guessing from the shape. Then check the " +
  "headlamps, grille, bumpers and tail lamps to pin down the generation and facelift.\n" +
  "Watch the look-alikes: Perodua Bezza (sedan, BEZZA badge) vs Proton Saga (sedan, SAGA badge); Perodua Axia vs Myvi (Myvi " +
  "is bigger with a taller roof); Proton X50 (compact SUV, 1.5 TGDi) vs X70 (bigger SUV, 1.8 TGDi) vs X90 (three rows); a " +
  "Proton emblem on a Geely-shaped body is the Proton model; Perodua models share bodies with Daihatsu and Toyota, so follow " +
  "the emblem.\n" +
  "make: the brand only, e.g. Perodua, Proton, Honda, Toyota, Mercedes-Benz.\n" +
  "model: the model name, then the generation code or nickname Malaysians use when you can tell, then the variant only if a " +
  "badge in the photo shows it. Examples: 'Myvi 3rd gen', 'Myvi 3rd gen 1.5 AV', 'Axia 2nd gen', 'Bezza 1.3 AV', " +
  "'Saga 3rd gen', 'Persona', 'X50 Flagship', 'X70', 'City GN', 'City GN RS e:HEV', 'Civic FE', 'Civic FC 1.5 TC', " +
  "'Civic Type R FL5', 'Vios NCP150', 'Hilux', 'Mazda 3 BP', 'Almera N18', '3 Series G20', 'C-Class W206', 'Golf GTI Mk7'. " +
  "Honda uses chassis codes (City GM6 / GN, Civic FD / FB / FC / FE, Jazz GK), Toyota Vios uses NCP93 / NCP150, Perodua and " +
  "Proton use '2nd gen' / '3rd gen' or 'facelift'. Never invent a trim you cannot read on the car. If it is not a car, or you " +
  "cannot tell, use empty strings and a low confidence.\n" +
  "year_from / year_to: the years that generation or facelift was sold in Malaysia (the same number twice if you are sure of " +
  `one year; if it is still on sale, year_to is ${THIS_YEAR}; 0 for both if unknown).\n` +
  "color: the paint's nearest bucket out of red, black, white, grey, silver, blue, yellow, green, orange, or unknown. Judge " +
  "the body panels in their light, not the shadows or reflections: white and pearl white are white, light metallic is " +
  "silver, dark or gunmetal is grey, maroon and orange-red are red.\n" +
  "body_style: one of hatchback, sedan, SUV, MPV, pickup, coupe, convertible, wagon, van, or empty.\n" +
  "spec_line: a short factory spec line for that exact variant as sold in Malaysia (or, with no variant badge, the most " +
  "common Malaysian variant of that generation) like '1.5 L NA · 102 hp · CVT' or '1.5 L turbo · 177 hp · 7-speed DCT'. " +
  "Only if you are reasonably sure; otherwise an empty string.\n" +
  "confidence: 0 to 1 for the make and model together.\n" +
  "Number plate: if a registration plate is visible (even partly, even blurry), set plate_found true and give its bounding box " +
  "as fractions of the image width and height: plate_x0, plate_y0 for the top-left corner, plate_x1, plate_y1 for the " +
  "bottom-right. If there is no plate, plate_found false and zeros. Never transcribe the plate.";

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
