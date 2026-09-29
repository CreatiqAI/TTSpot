// Address / place search, proxied so the keys never ship in the app.
// Body: { action: 'autocomplete', input, lat?, lng?, sessionToken? }
//     | { action: 'details', placeId, sessionToken? }
//     | { action: 'nearby', lat, lng }   -> the closest named places around a point
// Uses the Places API (New). A sessionToken groups one search's keystrokes with
// the details call that ends it, so Google bills the session once.
// Nearby asks Mapbox Search Box first (secret MAPBOX_TOKEN) and Google only as a fallback.
import { createClient } from "npm:@supabase/supabase-js@2";

const KEY = Deno.env.get("GOOGLE_PLACES_KEY") ?? "";
const MAPBOX = Deno.env.get("MAPBOX_TOKEN") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// Google wants URL-safe base64, at most 36 chars (a UUID fits). Anything else is dropped, never sent.
const sessionOf = (body: any): string | null =>
  typeof body.sessionToken === "string" && /^[A-Za-z0-9_-]{1,36}$/.test(body.sessionToken) ? body.sessionToken : null;

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
    const session = sessionOf(body);
    if (session) payload.sessionToken = session;
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
    // Nearby results from Mapbox already carry their coordinates; never ask Google about them.
    if (id.startsWith("mbx:")) return json({ error: "not a Google place" }, 400);
    const session = sessionOf(body);
    const qs = session ? `?sessionToken=${encodeURIComponent(session)}` : "";
    const r = await fetch(`https://places.googleapis.com/v1/places/${encodeURIComponent(id)}${qs}`, {
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

  if (body.action === "nearby") {
    const lat = Number(body.lat), lng = Number(body.lng);
    if (!isFinite(lat) || !isFinite(lng)) return json({ error: "lat/lng required" }, 400);
    const metres = (aLat: number, aLng: number, bLat: number, bLng: number) => {
      const R = 6371000, toRad = (x: number) => (x * Math.PI) / 180;
      const dLat = toRad(bLat - aLat), dLng = toRad(bLng - aLng);
      const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
      return 2 * R * Math.asin(Math.sqrt(h));
    };
    type Near = { placeId: string; name: string; address: string; lat: number; lng: number; type: string | null; distanceM: number };
    const byDistance = (a: Near, b: Near) => a.distanceM - b.distanceM;
    const search = async (radius: number, max: number, includedTypes?: string[]): Promise<any[]> => {
      const r = await fetch("https://places.googleapis.com/v1/places:searchNearby", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Goog-Api-Key": KEY, "X-Goog-FieldMask": "places.id,places.displayName,places.formattedAddress,places.location,places.primaryType" },
        body: JSON.stringify({
          locationRestriction: { circle: { center: { latitude: lat, longitude: lng }, radius } },
          rankPreference: "DISTANCE",
          maxResultCount: max,
          languageCode: "en",
          ...(includedTypes ? { includedTypes } : {}),
        }),
      });
      const d = await r.json();
      if (!r.ok) {
        // A type Google stopped supporting must never break the lookup: retry untyped.
        if (includedTypes && /Unsupported types/i.test(d?.error?.message ?? "")) return search(radius, max);
        throw new Error(d?.error?.message ?? "nearby failed");
      }
      return (d.places ?? []).filter((p: any) => p.location);
    };
    const fromGoogle = (p: any): Near => ({
      placeId: p.id,
      name: p.displayName?.text ?? "",
      address: p.formattedAddress ?? "",
      lat: p.location.latitude,
      lng: p.location.longitude,
      type: p.primaryType ?? null,
      distanceM: Math.round(metres(lat, lng, p.location.latitude, p.location.longitude)),
    });
    // 1) Whatever is *right here*, any type: a condo, a mall, an office, a workshop.
    //    This is what "Where are you?" should say when you are at home.
    // 2) TT venues around: cafes, restaurants, car parks, petrol stations, shops.
    // Real buildings only: listings, agents and lodging ads are noise here.
    const HERE_TYPES = [
      "apartment_building", "apartment_complex", "condominium_complex", "housing_complex",
      "shopping_mall", "corporate_office", "coworking_space", "government_office", "community_center",
      "university", "school", "hospital", "hotel", "stadium", "sports_complex", "mosque", "church", "hindu_temple",
      "car_repair", "car_wash", "car_dealer", "gas_station", "parking",
      "restaurant", "cafe", "coffee_shop", "bar", "food_court", "convenience_store", "supermarket", "park", "tourist_attraction",
    ];
    const googleHere = () => search(80, 5, HERE_TYPES);
    const googleOnly = async () => {
      const [here, venues] = await Promise.all([
        googleHere(),
        search(300, 8, ["restaurant", "cafe", "coffee_shop", "bar", "parking", "gas_station", "shopping_mall", "car_repair", "car_wash", "car_dealer", "convenience_store", "park", "tourist_attraction", "food_court", "bakery"]),
      ]);
      const seen = new Set<string>();
      return [...here, ...venues].filter((p) => !seen.has(p.id) && seen.add(p.id)).map(fromGoogle).sort(byDistance);
    };

    // Mapbox Search Box, billed per request at a fraction of Google's Nearby Search.
    // Measured across Klang Valley it matches Google on venues (mamaks, cafes, petrol
    // stations, workshops, malls) but not on condos: "The Legacy OUG" exists there only
    // as a showroom and Airbnb listings. So Mapbox answers when the closest thing is a
    // venue, and Google's 80 m call decides whenever a home might be right here.
    const MB_VENUES = ["food_and_drink", "parking_lot", "gas_station", "shopping_mall", "auto_repair", "car_wash", "car_dealership", "convenience_store", "park", "tourist_attraction"];
    // Counts as "here" within 80 m, like HERE_TYPES minus the buildings Mapbox names badly.
    const MB_HERE = new Set([...MB_VENUES, "supermarket", "coworking_space", "community_center", "university", "school", "hospital", "stadium", "sports_center", "place_of_worship"]);
    // Within 80 m these mean a home may be right here (uncategorised POIs are mostly Airbnb units).
    const MB_HOME = new Set(["apartment_or_condo", "home", "lodging", "vacation_rental"]);
    // Mapbox category -> the Google type the old path reported.
    const MB_TYPE: Record<string, string> = {
      gas_station: "gas_station", car_wash: "car_wash", auto_repair: "car_repair", car_dealership: "car_dealer", parking_lot: "parking",
      shopping_mall: "shopping_mall", food_court: "food_court", cafe: "cafe", coffee_shop: "coffee_shop", bar: "bar", bakery: "bakery",
      restaurant: "restaurant", convenience_store: "convenience_store", supermarket: "supermarket", park: "park", tourist_attraction: "tourist_attraction",
    };
    const mapbox = async (path: string, params: Record<string, string>): Promise<any[]> => {
      const q = new URLSearchParams({ ...params, language: "en", access_token: MAPBOX });
      const r = await fetch(`https://api.mapbox.com/search/searchbox/v1/${path}?${q}`, { signal: AbortSignal.timeout(5000) });
      const d = await r.json();
      if (!r.ok) throw new Error(d?.message ?? "mapbox failed");
      return (d.features ?? []).filter((f: any) => f.properties?.mapbox_id && f.geometry?.coordinates);
    };
    const cats = (f: any): string[] => f.properties.poi_category_ids ?? [];
    const fromMapbox = (f: any): Near => {
      const [fLng, fLat] = f.geometry.coordinates as [number, number];
      const c = cats(f), t = c.find((x) => MB_TYPE[x]);
      return {
        placeId: `mbx:${f.properties.mapbox_id}`,
        name: f.properties.name ?? "",
        address: f.properties.full_address ?? f.properties.place_formatted ?? "",
        lat: fLat,
        lng: fLng,
        type: t ? MB_TYPE[t] : c.at(-1) ?? null,
        distanceM: Math.round(metres(lat, lng, fLat, fLng)),
      };
    };
    // One place listed twice (by both sources, or twice by Mapbox): same name start, close together.
    const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");
    const sameSpot = (a: Near, b: Near) => {
      const x = norm(a.name), y = norm(b.name);
      return x.length >= 3 && y.length >= 3 && (x.startsWith(y) || y.startsWith(x)) && metres(a.lat, a.lng, b.lat, b.lng) < 100;
    };
    const dedupe = (list: Near[]) =>
      list.sort(byDistance).reduce<Near[]>((kept, p) => (kept.some((k) => sameSpot(k, p)) ? kept : [...kept, p]), []);

    try {
      if (MAPBOX) {
        const mb = await Promise.all([
          mapbox("reverse", { longitude: String(lng), latitude: String(lat), types: "poi", limit: "10" }),
          mapbox(`category/${MB_VENUES.join(",")}`, { proximity: `${lng},${lat}`, limit: "10" }),
        ]).catch(() => null);
        if (mb) {
          const [around, venues] = mb;
          const seen = new Set<string>();
          const places = dedupe(
            [...around, ...venues]
              .filter((f) => !seen.has(f.properties.mapbox_id) && seen.add(f.properties.mapbox_id))
              .map((f) => ({ f, p: fromMapbox(f) }))
              .filter(({ f, p }) => p.distanceM <= (cats(f).some((c) => MB_VENUES.includes(c)) ? 300 : 80) && cats(f).some((c) => MB_HERE.has(c)))
              .map(({ p }) => p),
          );
          const homeNear = around.some((f) => fromMapbox(f).distanceM <= 80 && (cats(f).length === 0 || cats(f).some((c) => MB_HOME.has(c))));
          if (!homeNear && places.some((p) => p.distanceM <= 80)) return json({ places });
          // Maybe home, or nothing named here: one Google call owns the 80 m ring, Mapbox fills in around it.
          // If Google fails, claim nothing: the app pins "My spot" and offers the list.
          const here = (await googleHere().catch(() => [])).map(fromGoogle);
          return json({ places: dedupe([...here, ...places.filter((p) => p.distanceM > 80)]) });
        }
      }
      // No MAPBOX_TOKEN yet, or Mapbox is down: the Google-only lookup.
      return json({ places: await googleOnly() });
    } catch (e) {
      return json({ error: (e as Error).message }, 502);
    }
  }
  return json({ error: "unknown action" }, 400);
});
