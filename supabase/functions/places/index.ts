// Address / place search for the meet form, proxied so the Google key never
// ships in the app. Body: { action: 'autocomplete', input, lat?, lng? } or
// { action: 'details', placeId }. Uses the Places API (New).
import { createClient } from "npm:@supabase/supabase-js@2";

const KEY = Deno.env.get("GOOGLE_PLACES_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (!KEY) return json({ error: "GOOGLE_PLACES_KEY not set" }, 500);
  // Signed-in members only: this costs money per call.
  const auth = req.headers.get("Authorization") ?? "";
  const anon = createClient(SUPABASE_URL, ANON, { global: { headers: { Authorization: auth } } });
  const { data: { user } } = await anon.auth.getUser();
  if (!user) return json({ error: "Not signed in" }, 401);

  const body = await req.json().catch(() => ({}));
  if (body.action === "autocomplete") {
    const input = String(body.input ?? "").trim();
    if (input.length < 2) return json({ suggestions: [] });
    const payload: Record<string, unknown> = { input, regionCode: "MY", languageCode: "en" };
    if (typeof body.lat === "number" && typeof body.lng === "number") {
      payload.locationBias = { circle: { center: { latitude: body.lat, longitude: body.lng }, radius: 50000 } };
    }
    const r = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Goog-Api-Key": KEY },
      body: JSON.stringify(payload),
    });
    const d = await r.json();
    if (!r.ok) return json({ error: d?.error?.message ?? "autocomplete failed" }, 502);
    const suggestions = (d.suggestions ?? [])
      .map((s: any) => s.placePrediction)
      .filter(Boolean)
      .slice(0, 6)
      .map((p: any) => ({
        placeId: p.placeId,
        main: p.structuredFormat?.mainText?.text ?? p.text?.text ?? "",
        secondary: p.structuredFormat?.secondaryText?.text ?? "",
      }));
    return json({ suggestions });
  }

  if (body.action === "details") {
    const id = String(body.placeId ?? "");
    if (!id) return json({ error: "placeId required" }, 400);
    const r = await fetch(`https://places.googleapis.com/v1/places/${encodeURIComponent(id)}`, {
      headers: { "X-Goog-Api-Key": KEY, "X-Goog-FieldMask": "id,displayName,formattedAddress,location" },
    });
    const d = await r.json();
    if (!r.ok) return json({ error: d?.error?.message ?? "details failed" }, 502);
    return json({
      placeId: d.id,
      name: d.displayName?.text ?? "",
      address: d.formattedAddress ?? "",
      lat: d.location?.latitude,
      lng: d.location?.longitude,
    });
  }
  return json({ error: "unknown action" }, 400);
});
