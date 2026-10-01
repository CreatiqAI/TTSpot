// titi
// TiTi, the traffic-cone mascot, as an in-app assistant: the member's "pit
// crew". Finds meets, spots and clubs, reads the member's own points,
// vouchers, cards, meets, cars, car papers and mods (tools that query Supabase
// as the member, so RLS applies), looks at photos, offers one-tap actions,
// explains the app, and talks cars.
//
// Input:  POST with the member's JWT:
//   { message, v: 2, session_id?, new_session?, images?: ["<uid>/<file>"], lat?, lng? }
//   The server loads the chat's recent history itself (last HISTORY rows).
//   session_id: the chat to continue. new_session: start a new chat (the
//   server makes it and says its id). Neither (the 0.3.42 app): the latest chat.
//   images: 1-4 photos the app uploaded to titi-uploads/<uid>/ (private).
//   Without v: 2 the old app gets the four v1 tools and nothing it can't draw.
// Output: text/event-stream, one small JSON object per `data:` line:
//   {"t":"session","id":"…"}                  a new chat was started
//   {"t":"status","text":"Checking meets near you…","tool":"search_meets"}
//   {"t":"delta","text":"…"}                  streamed answer text
//   {"t":"break"}                              start a new bubble
//   {"t":"card","kind":"meet"|"spot"|"club"|"car"|"voucher"|"offer","id","title","subtitle","image","route"}
//   {"t":"action","kind","id","label","title","detail","image?","target?","route?","lat?","lng?","after?"}
//                                              a button the member taps to act
//   {"t":"chips","options":["…"]}              2-3 follow-ups, after the text
//   {"t":"error","text":"…"}                   friendly; the app offers Retry
//   {"t":"done","id?":"<answer row>","title?":"<new chat title>"}
//
// The model marks bubbles with a line "---", cards with [[meet:<id>]] refs it
// got from a tool, follow-ups with a last line [[chips: a | b | c]] and, in a
// new chat, its title with [[title: …]]. The Shaper below turns those into
// events while the text streams, and cards are only ever built from real rows,
// so every link and photo is real.
//
// Actions: TiTi never acts for the member. An action tool (join_meet,
// save_spot, claim_voucher…) checks the target as the member, then puts an
// action card on screen; the APP does the action with its own code when the
// member taps it, and stamps the card done (titi_action_status). The answer
// stores the card as [[act:<id>]] + parts.actions[<id>].
//
// Model: OpenAI Responses API, streamed, reasoning effort "none" (speed), no
// sampling params. Up to MAX_ROUNDS tool rounds, then a forced final answer.
// Photos go in as input_image with a 15-minute signed URL, "low" detail unless
// the question needs fine print.
//
// Cost guards: DAILY_LIMIT questions per member per Malaysian day across all
// chats (titi_take_turn), HISTORY rows of context, at most 4 older photos
// re-sent, MAX_OUTPUT tokens per call, and every answer's token counts in
// titi_messages.usage + titi_daily.
//
// Service role, and only for bookkeeping: counting the daily limit, writing
// TiTi's answer and its usage. Members can't write those rows themselves, so
// nobody can plant a fake reply into the model's history or fake the cost log.
//
// Secrets: OPENAI_API_KEY (required), TITI_MODEL (default gpt-5.4-mini),
// TITI_DAILY_LIMIT (default 60), MAPBOX_TOKEN (optional, to place "near
// Bangsar"; without it TiTi uses the member's own location only).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY");
const MAPBOX = Deno.env.get("MAPBOX_TOKEN") ?? "";
const MODEL = Deno.env.get("TITI_MODEL") ?? "gpt-5.4-mini";
const DAILY_LIMIT = Number(Deno.env.get("TITI_DAILY_LIMIT") ?? 60) || 60;

const HISTORY = 16;
const MAX_ROUNDS = 4;
const MAX_OUTPUT = 900;
const MAX_MESSAGE = 1000;
const MAX_CARDS = 6;
const MAX_ACTIONS = 3;
const MAX_IMAGES = 4;
const BUCKET = "titi-uploads";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** An id the model passed: a bare uuid or a ref like [[meet:<uuid>]]. */
const idFrom = (v: unknown) => (typeof v === "string" ? /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.exec(v)?.[0]?.toLowerCase() ?? null : null);

// ============================================================ the prompt ===

/**
 * The instructions. [v2]: the current app, with the member's own data, action
 * cards and photos; without it the 0.3.42 app's prompt (searches only).
 */
function buildSystem(v2: boolean): string {
  const what = [
    `Find things in TT Spot: meets and TT sessions coming up, spots and car cafés, car clubs${v2 ? ", partner deals" : ""}. ALWAYS use the tools for these. Never invent meets, spots, clubs, people, dates, prices or places. If a tool finds nothing, say so plainly and offer a next step (a wider area, other dates, or starting a TT session themselves).`,
    v2 && `The member's own stuff: you can see THEIR points and history, vouchers, blind-box cards, boxes and trades, meets they're going to or host, clubs, saved spots, cars, car papers (road tax, insurance, PUSPAKOM, service), mods and notifications, through the my_* tools. Use them whenever a question touches these ("how many points", "my vouchers", "when is my road tax"). Never say you can't see their account; check with a tool.`,
    v2 && `Do things for them with action cards (see Actions).`,
    `Explain how the app works, using the app facts below. If something isn't covered, say you're not sure instead of guessing.`,
    `Car talk: maintenance, mods, driving, Malaysian road tax, insurance, PUSPAKOM and JPJ basics${v2 ? ", this week's fuel prices (fuel_prices) and road tax estimates (road_tax_estimate: always call it an estimate and say JPJ or MyEG has the exact figure)" : ""}. This is general advice: when money or the law is involved, say so briefly, never promise prices, fines, approvals or outcomes, and point to the official source (JPJ, PUSPAKOM, the insurer, a trusted workshop). Give prices only as rough, well-known ranges and call them estimates. Mods: mention legality (JPJ, PUSPAKOM inspection, insurance declaration) when it matters. Safety first; never encourage street racing or breaking traffic laws.`,
    v2 && `Photos: the member may send photos ("what car is this", "is this tyre worn", "what does this warning light mean", "how much for this mod"). Say what you see and what it likely means, with the uncertainty a photo carries. A red warning light, or anything about brakes, steering, tyres or overheating: tell them to stop safely and get it checked. Never guess who a person is from a photo, and don't read out other people's number plates.`,
  ].filter(Boolean).map((s, i) => `${i + 1}. ${s}`).join("\n");

  const v2Sections = v2
    ? `

# Being proactive
- If the heads-up below or a tool result shows something due soon (road tax or insurance running out, a voucher ending, an unopened box, a meet today), mention it briefly when it fits, once per chat. Example: "By the way, your road tax runs out in 9 days."
- Offer the obvious next step as an action card when it helps (directions to the meet they joined, Open box when they have one).

# Privacy
- Only the member's own private data. Never reveal other members' private details (phone, email, location, car papers, prices, vouchers, points). Public things (a club's name, a meet's host, a spot) are fine.

# Actions
- You never do anything yourself. To join or leave a meet, save a spot, open directions, start TT here, open a page, open or get a blind box, or claim a partner voucher, call the matching action tool. It puts a card with a button on screen; the member taps it to confirm and the app does it.
- Only offer an action the member asked for or clearly wants, one or two at a time, with ids from tool results.
- The action card shows the item's photo, name and time, so don't also put that item's [[ref]] card in the same reply.
- After offering one, write one short line such as "Tap Join to confirm." Never say it's done: it happens only when they tap. If the history shows an action as done, it's done.
- Pass "after" with a short follow-up the app shows once it's done (e.g. "You're in. Want directions?").`
    : "";

  return `You are TiTi, the orange traffic-cone mascot of TT Spot, a Malaysian car-community app. You are the member's pit crew: a friendly, knowledgeable Malaysian car buddy who lives inside the app${v2 ? " and knows their account" : ""}.

# What you do
${what}${v2Sections}

# How you write
- Reply in the member's language: English, Malay or Chinese (Simplified unless they write Traditional). Match light Manglish if they use it.
- Short, upbeat and plain. Most replies are 1-3 short bubbles. No walls of text. Use at most one exclamation mark in the whole reply (often none).
- Split a longer reply into bubbles with a line that holds only ---. One idea per bubble.
- You may use **bold** for a key word, bullet lines starting with "- " (5 at most), numbered steps "1. ", and links written as [label](url).
- App links open the app itself; use only these paths: ${APP_LINKS}
- Web links only to official sites you are sure of: https://www.jpj.gov.my, https://www.puspakom.com.my, https://www.myeg.com.my, https://www.bnm.gov.my. Never make up a URL.
- No headings, tables, code blocks or images. Cards show the photos.

# Cards
- Tool results give items a ref such as [[meet:<id>]]${v2 ? ", [[voucher:<id>]] or [[offer:<id>]]" : ""}. To show an item as a tappable card with its photo, put its ref on a line of its own.
- The card already shows the name, time, place and photo, so don't repeat those. Add at most one short line on why it's worth a look.
- Only use refs that came from a tool result. Never write an id yourself. At most 4 cards in a reply.

# Follow-ups
- End every reply with one last line: [[chips: option | option | option]] with 2-3 short follow-ups the member may tap next (5 words at most each, in their language, written as the member would ask them). Example: [[chips: TT sessions tonight | Car cafés near me | How do points work?]]

# Using the tools
- "Near me", "nearby", "around here": pass near "me". If the member's location is unknown, ask which area, or search without one.
- A named area (Bangsar, PJ, Johor Bahru, Ipoh): pass it as near.
- Times are Malaysia time (UTC+8); send ISO times with +08:00. "This weekend" is Saturday 00:00 to Sunday 23:59 (from now if it's already the weekend). "Tonight" is now to 03:00. "Upcoming" or no date: the next 14 days.
- ${v2 ? "Several tools at once is fine. " : ""}Call tools at most a few times, then answer with what you have. Don't ask permission to look; just look.
- Meets: "official" means hosted by an official club or a partner business, or an official-type event.

# App facts
${APP_FACTS}`;
}

// Paths the app can open inside itself (the client allows these too).
const APP_LINKS = [
  "[Points](/me/points)",
  "[Cards](/cards)",
  "[Rewards](/rewards)",
  "[My vouchers](/rewards?tab=vouchers)",
  "[Scan a QR](/scan)",
  "[My QR](/me/qr)",
  "[Friends](/friends)",
  "[My meets](/meets)",
  "[Clubs](/clubs)",
  "[Map](/map)",
  "[Chats](/chats)",
  "[Suggest a spot](/suggest-spot)",
  "[Add a car](/car/new)",
  "[My garage](/garage)",
  "[Plan a TT session](/create-event?session=1)",
  "[Become an organizer](/organizer/apply)",
  "[Start a club](/club/apply)",
  "[Partner with TT Spot](/partner/apply)",
  "[Settings](/settings)",
].join(", ");

// Read from the app's code and migrations on 2026-09-30 (point_rules, blind_box,
// vendors, meet_checkin_flow, event_car, organizer, lucky_draw, club_tiers...).
// Keep in step when those rules change.
const APP_FACTS = `The app's tabs: Posts, Map, Chats, Me, and the centre + button (Create).

Points (balance, history and how to earn: Me → Points, /me/points)
- Check in at a meet: +30 (once per meet). Check in at a spot: +20 (within 300 m, once per spot per day). Verified spot check-in (scan the spot's sticker and snap your car, then it's approved): +50.
- A spot you suggested goes live: +30. Each badge unlocked: +25. Invite a friend: you get +100 and they get +50 when they do their first check-in.
- Spend points on blind boxes (100 each) and partner vouchers (the partner sets the price; some are free).
- No daily login bonus and no levels. 12 badges (Me → Badges).

Blind box cards (/cards)
- One free box when you finish sign-up; after that a box costs 100 points.
- Open it by shaking the phone (or tapping the box 3 times).
- 7 TiTi cards: 4 common, 2 rare, 1 Secret (odds 89.5% / 10% / 0.5%; each common about 22.4%, each rare 5%). Rare or better is guaranteed within every 10 boxes. Only 100 Secret cards will ever exist, each numbered (No. X of 100); once they are gone the Secret can no longer be pulled. Cards never expire. The top tier is called "Secret", never "legendary".
- Trade with friends: up to 9 cards a side; they accept or decline.
- Prizes (Cards → Prizes): trade in cards (doubles go first) for a prize and get a QR that the partner or TT Spot staff scans. A claim lasts 30 days; if it lapses, the cards come back.

Vouchers (/rewards)
- Partner shops offer vouchers: % off, RM off or a freebie, sometimes with a minimum spend. Claim one with points; it waits in My vouchers (/rewards?tab=vouchers) until the voucher ends, else 30 days.
- At the shop, open the voucher and show its QR. The staff scan it in TT Spot and take it off your bill.

Check-ins
- Meets: check-in opens 1 hour before the start and closes when the meet ends (or 6 hours after the start). Tap "I'm here · check in" within 500 m, or scan the host's QR within 300 m. If you're going, the app can check you in by itself when you arrive. Hosts of small meets confirm who was really there.
- Spots: tap Check in on the spot's page within 300 m, once a day per spot. A moment posted at the spot counts too.

TT now, TT sessions and meets
- TT now: the red TT NOW button at the top of Create. Tell friends where you are right now: pick the place, how long (1 hour by default, 15 minutes to 8 hours) and who to ping (all friends by default). Friends and clubmates see it on the map, and you're checked in.
- TT session: a TT planned for later (Create → TT session, /create-event?session=1). Anyone can plan one; friends-only unless you pick Everyone.
- Meets, convoys and track days are hosted by car clubs (their officers) and partner shops. Official meets are hosted by official clubs (gold badge) or partners.
- On a meet's page: tap Going, chat in its group chat, get reminders, check in when you arrive.

Organizers (/organizer/apply)
- People who run meets can apply to be a verified organizer (name, Instagram or website, usual turnout, a short description). An admin approves.
- Verified hosts get organizer tools on their meets: crew and co-hosts (up to 30), the check-in QR and door list, announcements, lucky draws (free, one entry per person, for people checked in; provably fair), floor plans, an invite QR and link, and a turnout report.

Clubs (/clubs)
- Find clubs in the map's list (Clubs tab). Tap Request to join (officers approve) or accept an invite.
- Start one: Create → Start a car club (/club/apply). An admin approves, then you set it up. Underground clubs hold up to 100 members; official clubs get a gold badge and more perks.

Partners
- Car businesses (cafés, workshops, detailing, tyres, accessories, audio, car wash) apply at /partner/apply with an SSM number and a shop photo; for now shops in Johor, Penang and Kuala Lumpur. They get a page, vouchers, products and events.

Spots
- Spots are where car people hang out: car cafés, mamaks, carparks, circuits, driving roads and partner shops. Map → Spots shows them.
- Suggest one: Create → Suggest a spot (/suggest-spot); +30 points if it goes live. Bookmark spots to save them.

Your car pages
- Each car in the garage has Documents (road tax, insurance, PUSPAKOM, next service; only you see them, and the app reminds you 30, 7 and 1 day before road tax or insurance runs out) and Mods (a log with prices only you see).
- AI car portraits cost 300 points (refunded if one fails).

Friends, moments, privacy
- Add friends by username, or scan their My QR (/me/qr) to be friends instantly. Friends see each other on the map and get TT now pings.
- Moments: a photo or a video up to 30 s, gone after 24 hours (Create → Moment). Albums keep them on your profile.
- Who sees your car on the map: Friends (the default), Friends + nearby, Everyone, or Nobody (ghost). Change it on the map.
- Invite code: your 6-character code is on My QR and Me → Invite friends; new members enter it when they sign up.
- Help or a problem: email ttspotmy@gmail.com.

Car-talk anchors (Malaysia; general info, check the official source)
- Road tax (LKM): renew the insurance first, then renew online (MyJPJ app, MyEG) or at JPJ or Pos Malaysia. The price depends on engine size, body type, owner type and region (Peninsular vs Sabah, Sarawak, Labuan, Langkawi); JPJ's website has the calculator.
- Insurance: comprehensive, third-party fire and theft, or third-party only. NCD (no-claim discount) grows with claim-free years. Declare mods to the insurer, or a claim can be rejected.
- PUSPAKOM: inspections for used-car ownership transfers, JPJ-approved modifications, re-registration and commercial vehicles. Book online.`;

// Built once per instance (APP_LINKS and APP_FACTS are defined above them).
const INSTRUCTIONS = buildSystem(true);
const INSTRUCTIONS_V1 = buildSystem(false);

// ============================================================== the tools ===

const NEAR = { type: "string", description: "\"me\" for the member's own location, or a Malaysian area or place name." };
const NOARGS = { type: "object", properties: {}, additionalProperties: false };
const AFTER = { type: "string", description: "Optional. One short line the app shows once the member has done it, e.g. \"You're in. Want directions?\"" };
const fn = (name: string, description: string, parameters: Record<string, unknown> = NOARGS) => ({ type: "function", name, description, parameters });

const V1_TOOLS = [
  fn("search_meets", "Find meets, TT sessions, convoys and track days in TT Spot, soonest first. Returns up to 8 with a ref each for cards.", {
    type: "object",
    properties: {
      from: { type: "string", description: "Window start, ISO with +08:00. Default: now (meets under way included)." },
      to: { type: "string", description: "Window end, ISO with +08:00. Default: 14 days after from." },
      near: NEAR,
      near_lat: { type: "number", description: "Only with exact coordinates the member gave. Otherwise leave out and use near." },
      near_lng: { type: "number", description: "Only with near_lat." },
      radius_km: { type: "number", description: "Default 30 when near is set." },
      official_only: { type: "boolean", description: "Only official meets (official clubs, partners, official events)." },
      type: { type: "string", enum: ["any", "meet", "tt", "convoy", "trackday"], description: "Default \"any\" (all kinds, also for \"any meets?\"). Pick one only when the member names it: meet = a regular car meet, tt = TT sessions." },
    },
    additionalProperties: false,
  }),
  fn("search_spots", "Find spots on the TT Spot map (car cafés, mamaks, carparks, circuits, roads, shops), nearest first when a place is given, else the most popular.", {
    type: "object",
    properties: {
      near: NEAR,
      near_lat: { type: "number", description: "Only with exact coordinates the member gave. Otherwise leave out and use near." },
      near_lng: { type: "number", description: "Only with near_lat." },
      kind: { type: "string", enum: ["cafe", "mamak", "carpark", "circuit", "route", "accessories", "other"], description: "cafe = car café." },
      limit: { type: "integer", description: "1-8, default 5." },
    },
    additionalProperties: false,
  }),
  fn("search_clubs", "Find car clubs in TT Spot by name, or by state / area.", {
    type: "object",
    properties: {
      query: { type: "string", description: "Part of the club's name or handle, or a make (e.g. Civic, Myvi)." },
      near: { type: "string", description: "A state or area, or \"me\"." },
    },
    additionalProperties: false,
  }),
  fn("my_cars", "The member's own cars in their TT Spot garage (make, model, year, colour, specs)."),
];

const V2_TOOLS = [
  ...V1_TOOLS,
  // ------------------------------------------------ the member's own data
  fn("my_summary", "The member's own overview: name, points, friends, cars, clubs, unread notifications, unopened boxes, active vouchers, meets they're going to, TT streak, and heads-ups (papers due, vouchers ending)."),
  fn("my_points", "The member's points: balance, recent earning and spending with reasons, and every way to earn with the real amounts."),
  fn("my_vouchers", "Vouchers the member claimed: active ones (partner, value, expiry), then used and expired ones. Refs for cards."),
  fn("partner_offers", "Partner vouchers and deals the member can claim now (points cost, value, partner), nearest partners first when near is given.", {
    type: "object",
    properties: { near: NEAR, limit: { type: "integer", description: "1-8, default 5." } },
    additionalProperties: false,
  }),
  fn("my_cards", "The member's blind-box cards: collection progress, doubles, unopened boxes, pending trades, prize claims and prizes they could get."),
  fn("my_meets", "Meets the member is going to, hosting or bookmarked (upcoming), how many meets and spots they've checked in at, and their weekly TT streak."),
  fn("meet_details", "One meet in full: about, time, place, host, going count, check-in window, and whether the member is going or checked in.", {
    type: "object",
    properties: { meet_id: { type: "string", description: "The meet's id from a tool result (its ref)." } },
    required: ["meet_id"],
    additionalProperties: false,
  }),
  fn("my_clubs", "Clubs the member belongs to, with their role."),
  fn("my_saved_spots", "Spots the member saved (bookmarked), nearest first when their location is known."),
  fn("my_car_documents", "Road tax, insurance, PUSPAKOM and next-service dates for each of the member's cars, with days left."),
  fn("my_car_mods", "The mods logged on one of the member's cars (category, part, shop, date, cost) and the total spent.", {
    type: "object",
    properties: { car: { type: "string", description: "Make or model to pick the car (e.g. \"Civic\"). Default: their main car." } },
    additionalProperties: false,
  }),
  fn("my_notifications", "The member's recent notifications (activity), newest first, and how many are unread.", {
    type: "object",
    properties: { unread_only: { type: "boolean" } },
    additionalProperties: false,
  }),
  fn("fuel_prices", "This week's official Malaysian pump prices (RON95 subsidised and unsubsidised, RON97, diesel) from data.gov.my, with the change from last week."),
  fn("road_tax_estimate", "Estimate a private car's yearly road tax (LKM) with JPJ's progressive formula. An estimate: JPJ or MyEG has the exact figure.", {
    type: "object",
    properties: {
      engine_cc: { type: "integer", description: "Engine capacity in cc (1.5L = 1497 or 1500)." },
      region: { type: "string", enum: ["peninsular", "sabah_sarawak", "labuan", "langkawi_pangkor"], description: "Where the car is registered. KL, Selangor, Johor, Penang etc. = peninsular." },
      body: { type: "string", enum: ["saloon", "non_saloon"], description: "As on the grant: saloon for most passenger cars; non_saloon for pickups, 4x4 jeeps and vans. Default saloon." },
      owner: { type: "string", enum: ["individual", "company"], description: "Default individual." },
      electric: { type: "boolean", description: "A fully electric car (EV road tax goes by motor power instead)." },
    },
    required: ["engine_cc"],
    additionalProperties: false,
  }),
  // ------------------------------------------------ actions (a card; the member taps)
  fn("join_meet", "Offer a Join button for a meet (RSVP). The member taps to confirm; nothing happens until then.", {
    type: "object", properties: { meet_id: { type: "string" }, after: AFTER }, required: ["meet_id"], additionalProperties: false,
  }),
  fn("leave_meet", "Offer a Leave button for a meet the member is going to.", {
    type: "object", properties: { meet_id: { type: "string" }, after: AFTER }, required: ["meet_id"], additionalProperties: false,
  }),
  fn("save_spot", "Offer a Save button for a spot (bookmarks it; saved spots always show on their map).", {
    type: "object", properties: { spot_id: { type: "string" }, after: AFTER }, required: ["spot_id"], additionalProperties: false,
  }),
  fn("open_directions", "Offer a Directions button to a meet or a spot (opens Waze, Google Maps or Apple Maps).", {
    type: "object", properties: { meet_id: { type: "string" }, spot_id: { type: "string" } }, additionalProperties: false,
  }),
  fn("tt_here", "Offer a TT here button for a spot: tells friends the member is there now (TT now) when they're within 1 km, else plans a TT session there.", {
    type: "object", properties: { spot_id: { type: "string" } }, required: ["spot_id"], additionalProperties: false,
  }),
  fn("open_page", "Offer a button that opens a page of the app: one of the app link paths, or /event/<id>, /place/<id>, /club/<id>, /partner/<id>, /car/<id>, /car/<id>/documents, /voucher/<claim id>, /cards/box/<box id> with ids from tool results.", {
    type: "object",
    properties: { path: { type: "string" }, label: { type: "string", description: "2-3 words on the button, e.g. \"Open Points\"." } },
    required: ["path"],
    additionalProperties: false,
  }),
  fn("open_box_shop", "Offer to open the member's unopened blind box, or to get one with points when they have none."),
  fn("claim_voucher", "Offer a Claim button for a partner voucher from partner_offers (spends its points when they tap).", {
    type: "object", properties: { offer_id: { type: "string" }, after: AFTER }, required: ["offer_id"], additionalProperties: false,
  }),
];

const ACTION_TOOLS = new Set(["join_meet", "leave_meet", "save_spot", "open_directions", "tt_here", "open_page", "open_box_shop", "claim_voucher"]);

const STATUS: Record<string, (a: any) => string> = {
  search_meets: (a) => (a?.near ? (a.near === "me" ? "Checking meets near you…" : `Checking meets near ${String(a.near).slice(0, 30)}…`) : "Checking upcoming meets…"),
  search_spots: (a) => (a?.near ? (a.near === "me" ? "Finding spots near you…" : `Finding spots near ${String(a.near).slice(0, 30)}…`) : "Finding spots…"),
  search_clubs: () => "Looking up clubs…",
  my_cars: () => "Opening your garage…",
  my_summary: () => "Checking your account…",
  my_points: () => "Counting your points…",
  my_vouchers: () => "Opening your vouchers…",
  partner_offers: () => "Looking at partner deals…",
  my_cards: () => "Checking your cards…",
  my_meets: () => "Checking your meets…",
  meet_details: () => "Opening the meet…",
  my_clubs: () => "Checking your clubs…",
  my_saved_spots: () => "Opening your saved spots…",
  my_car_documents: () => "Checking your car papers…",
  my_car_mods: () => "Opening your mod list…",
  my_notifications: () => "Checking your notifications…",
  fuel_prices: () => "Checking pump prices…",
  road_tax_estimate: () => "Working out road tax…",
};

type Card = { kind: "meet" | "spot" | "club" | "car" | "voucher" | "offer"; id: string; title: string; subtitle: string; image: string | null; route: string };
type Action = {
  kind: string;
  id: string;
  label: string;
  title: string;
  detail: string;
  image?: string | null;
  target?: string;
  route?: string;
  lat?: number;
  lng?: number;
  after?: string;
  status?: string;
};
type Point = { lat: number; lng: number; label: string };

// ---------------------------------------------------------------- helpers ---

const MYT = "Asia/Kuala_Lumpur";
/** "Sat, 14 Sep · 8:00 PM" in Malaysia time, like the app's formatEventDate. */
const WHEN = new Intl.DateTimeFormat("en-GB", { timeZone: MYT, weekday: "short", day: "numeric", month: "short", hour: "numeric", minute: "2-digit", hour12: true });
const fmtWhen = (iso: string) => {
  const p = Object.fromEntries(WHEN.formatToParts(new Date(iso)).map((x) => [x.type, x.value]));
  return `${p.weekday}, ${p.day} ${p.month} · ${p.hour}:${p.minute} ${String(p.dayPeriod ?? "").toUpperCase()}`.trim();
};
/** Today's date in Malaysia, "2026-09-30". */
const todayMyt = () => new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10);
/** Whole days from today (Malaysia) to a "YYYY-MM-DD" date; negative when past. */
const daysUntil = (d: string) => Math.round((Date.parse(d.slice(0, 10)) - Date.parse(todayMyt())) / 86400e3);
/** "12 Oct 2026" */
const fmtDay = (d: string) => new Intl.DateTimeFormat("en-GB", { timeZone: "UTC", day: "numeric", month: "short", year: "numeric" }).format(new Date(d.slice(0, 10)));
const inDays = (n: number) => (n === 0 ? "today" : n === 1 ? "tomorrow" : n > 0 ? `in ${n} days` : n === -1 ? "yesterday" : `${-n} days ago`);

function km(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}
const round1 = (n: number) => Math.round(n * 10) / 10;
const short = (s: unknown, n: number) => (typeof s === "string" ? (s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s) : "");
const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : null);
const rm = (n: number) => `RM${Number.isInteger(n) ? n : n.toFixed(2)}`;
const rows = (r: { data: unknown }) => (Array.isArray(r.data) ? (r.data as any[]) : []);

const KIND_LABEL: Record<string, string> = {
  cafe: "Car café", mamak: "Mamak", carpark: "Carpark", circuit: "Circuit", route: "Driving road",
  accessories: "Parts & accessories", workshop: "Workshop", detailing: "Detailing", tyres: "Tyres & rims",
  bodyshop: "Body & paint", audio: "Audio", carwash: "Car wash", mall: "Mall", other: "Spot",
};
const KIND_ICONS = new Set(["accessories", "audio", "bodyshop", "cafe", "carpark", "carwash", "circuit", "detailing", "mall", "mamak", "other", "route", "tyres", "workshop"]);
const TYPE_LABEL: Record<string, string> = { meet: "Meet", tt: "TT session", convoy: "Convoy", trackday: "Track day", charity: "Charity", official: "Official" };

// A club's home_state is one of lib/core/constants/malaysian_states.dart. Aliases → that name.
const STATES: [RegExp, string][] = [
  [/\bjohor\b|\bjb\b/i, "Johor"], [/\bkedah\b/i, "Kedah"], [/\bkelantan\b/i, "Kelantan"], [/\bkuala lumpur\b|\bkl\b/i, "Kuala Lumpur"],
  [/\blabuan\b/i, "Labuan"], [/\bmelaka\b|\bmalacca\b/i, "Melaka"], [/\bnegeri sembilan\b|\bn\.? ?9\b/i, "Negeri Sembilan"],
  [/\bpahang\b/i, "Pahang"], [/\bpenang\b|\bpulau pinang\b/i, "Penang"], [/\bperak\b/i, "Perak"], [/\bperlis\b/i, "Perlis"],
  [/\bputrajaya\b/i, "Putrajaya"], [/\bsabah\b/i, "Sabah"], [/\bsarawak\b/i, "Sarawak"], [/\bselangor\b/i, "Selangor"],
  [/\bterengganu\b/i, "Terengganu"],
];
const spotCheckins = (r: any) => (r.spot_checkins ?? 0) + (r.checkins_total ?? 0);

// Selects, the same views the app reads.
const MEET_COLS = "id,title,event_type,cover_url,starts_at,ends_at,venue_name,address,lat,lng,max_attendees,attendee_count,checkin_count,club_name,club_tier,vendor_id,vendor_name,is_instant,visibility,status,organizer_id";
const SPOT_COLS = "id,name,kind,lat,lng,cover_url,description,tags,vendor_name,vendor_logo,spot_checkins,checkins_total,upcoming_meets,is_top,recommended";
const CLUB_COLS = "id,name,handle,description,avatar_url,home_state,tier,official_until,garage_name,garage_lat,garage_lng,members:club_members(count)";
const CAR_COLS = "id,make,model,year,color,body_style,specs,is_default,photo_urls,portrait_url";

const isOfficialMeet = (r: any) => r.event_type === "official" || r.club_tier === "official" || r.vendor_id != null;
const meetClosesAt = (r: any) => (r.ends_at ? Date.parse(r.ends_at) : Date.parse(r.starts_at) + 6 * 3600e3);
const clubOfficial = (r: any) => r.tier === "official" && (!r.official_until || Date.parse(r.official_until) > Date.now());
const memberCount = (r: any) => (Array.isArray(r.members) ? r.members[0]?.count ?? 0 : 0);
const carName = (r: any) => short(`${r.make ?? ""} ${r.model ?? ""}`.trim(), 60) || "Car";
const discount = (r: any) => {
  const v = Number(r.discount_value ?? 0);
  const what = r.discount_kind === "amount" ? `${rm(v)} off` : r.discount_kind === "freebie" ? "Freebie" : `${v}% off`;
  return r.min_spend ? `${what} (min spend ${rm(Number(r.min_spend))})` : what;
};

function meetCard(r: any): Card {
  const cover = r.club_tier === "official" ? "official" : r.is_instant ? "tt" : (TYPE_LABEL[r.event_type] ? r.event_type : "meet");
  return {
    kind: "meet",
    id: r.id,
    title: short(r.title, 80) || "Meet",
    subtitle: [fmtWhen(r.starts_at), short(r.venue_name, 40)].filter(Boolean).join(" · "),
    image: r.cover_url ?? `assets/covers/${cover}.jpg`,
    route: `/event/${r.id}`,
  };
}
function spotCard(r: any, dist?: number | null): Card {
  const bits = [KIND_LABEL[r.kind] ?? "Spot"];
  if (dist != null) bits.push(`${dist < 10 ? round1(dist) : Math.round(dist)} km`);
  const n = spotCheckins(r);
  if (n) bits.push(`${n} check-in${n === 1 ? "" : "s"}`);
  return {
    kind: "spot",
    id: r.id,
    title: short(r.name, 80) || "Spot",
    subtitle: bits.join(" · "),
    image: r.cover_url ?? r.vendor_logo ?? `assets/kinds/${KIND_ICONS.has(r.kind) ? r.kind : "other"}.png`,
    route: `/place/${r.id}`,
  };
}
function clubCard(r: any): Card {
  const n = memberCount(r);
  return {
    kind: "club",
    id: r.id,
    title: short(r.name, 80) || "Club",
    subtitle: [`${n} member${n === 1 ? "" : "s"}`, r.home_state, clubOfficial(r) ? "Official" : null].filter(Boolean).join(" · "),
    image: r.avatar_url ?? null,
    route: `/club/${r.id}`,
  };
}
function carCard(r: any): Card {
  return {
    kind: "car",
    id: r.id,
    title: carName(r),
    subtitle: [r.year, r.color, short(r.specs, 40)].filter(Boolean).join(" · "),
    image: (Array.isArray(r.photo_urls) && r.photo_urls[0]) || r.portrait_url || null,
    route: `/car/${r.id}`,
  };
}
/** A voucher I claimed (a my_vouchers row): opens its QR. */
function voucherCard(r: any): Card {
  const ends = r.expires_at ? `ends ${fmtDay(r.expires_at)}` : null;
  return {
    kind: "voucher",
    id: r.id,
    title: short(r.title, 80) || "Voucher",
    subtitle: [r.vendor_name, discount(r), r.status === "active" ? ends : r.status].filter(Boolean).join(" · "),
    image: r.vendor_logo ?? "assets/vouchers/voucher.png",
    route: `/voucher/${r.id}`,
  };
}
/** A voucher on offer (a shop_vouchers row): opens the partner's page. */
function offerCard(r: any): Card {
  return {
    kind: "offer",
    id: r.id,
    title: short(r.title, 80) || "Voucher",
    subtitle: [r.vendor_name, discount(r), r.points_cost ? `${r.points_cost} pts` : "Free"].filter(Boolean).join(" · "),
    image: r.vendor_logo ?? "assets/vouchers/voucher.png",
    route: r.vendor_id ? `/partner/${r.vendor_id}` : "/rewards",
  };
}

const inMalaysia = (lat: number, lng: number) => lat > 0.5 && lat < 7.6 && lng > 99.4 && lng < 119.6;

/**
 * A Malaysian area or place name → a point. Mapbox knows towns and districts
 * (Ipoh, Johor Bahru, Sepang) but not KL neighbourhoods, so Bangsar, Mont
 * Kiara or SS2 fall back to the best-matching place of interest there. Both are
 * biased towards [bias] (the member, else central KL); left alone, Mapbox
 * biases towards the server, which sits in Singapore, and Bangsar lands in Johor.
 */
async function geocode(name: string, bias: Point | null): Promise<Point | null> {
  if (!MAPBOX) return null;
  const get = async (url: string) => {
    const r = await fetch(url, { signal: AbortSignal.timeout(4000) });
    const f = r.ok ? (await r.json())?.features?.[0] : null;
    const c = f?.geometry?.coordinates;
    return Array.isArray(c) && inMalaysia(c[1], c[0]) ? { lat: c[1] as number, lng: c[0] as number, label: name } : null;
  };
  const proximity = bias ? `${bias.lng},${bias.lat}` : "101.6869,3.1390";
  const q = (extra: Record<string, string>) => new URLSearchParams({ q: name, country: "my", limit: "1", language: "en", proximity, access_token: MAPBOX, ...extra });
  // Both at once (the member is waiting); the area answer wins when there is one.
  const safe = (url: string) => get(url).catch((e) => {
    console.error("titi geocode", String(e).slice(0, 200));
    return null;
  });
  const [area, poi] = await Promise.all([
    safe(`https://api.mapbox.com/search/geocode/v6/forward?${q({ types: "region,district,place,locality,neighborhood" })}`),
    safe(`https://api.mapbox.com/search/searchbox/v1/forward?${q({})}`),
  ]);
  return area ?? poi;
}

// ---------------------------------------------------------- fuel prices ---

// data.gov.my's weekly pump prices (KPDN). One row per week and series; the
// "level" rows are the prices. Cached for 30 minutes per function instance.
let fuelCache: { at: number; rows: any[] } | null = null;
async function fuelRows(): Promise<any[]> {
  if (fuelCache && Date.now() - fuelCache.at < 30 * 60e3) return fuelCache.rows;
  const r = await fetch("https://api.data.gov.my/data-catalogue/?id=fuelprice&sort=-date&limit=2&filter=level@series_type", { signal: AbortSignal.timeout(6000) });
  if (!r.ok) throw new Error(`fuel ${r.status}`);
  const data = await r.json();
  if (!Array.isArray(data) || !data.length) throw new Error("fuel: no rows");
  fuelCache = { at: Date.now(), rows: data };
  return data;
}

// ------------------------------------------------------------- road tax ---

// JPJ's yearly road tax (LKM) for private cars: [top of the cc band, base RM,
// RM per cc above the band's floor]. The floor is the band before's top.
// Each table's bands join up (e.g. 1,800 cc: 200 + 200 × 0.40 = 280, the next
// base), a check that the numbers were copied right. Sources: JPJ's published
// rates via stashaway.my/r/calculate-road-tax-malaysia (2026), cross-checked.
type Band = [number, number, number];
const RT: Record<string, Band[]> = {
  peninsular_saloon_individual: [[1000, 20, 0], [1200, 55, 0], [1400, 70, 0], [1600, 90, 0], [1800, 200, 0.4], [2000, 280, 0.5], [2500, 380, 1], [3000, 880, 2.5], [Infinity, 2130, 4.5]],
  peninsular_saloon_company: [[1000, 20, 0], [1200, 110, 0], [1400, 140, 0], [1600, 180, 0], [1800, 400, 0.8], [2000, 560, 1], [2500, 760, 3], [3000, 2260, 7.5], [Infinity, 6010, 13.5]],
  peninsular_non_saloon: [[1000, 20, 0], [1200, 85, 0], [1400, 100, 0], [1600, 120, 0], [1800, 300, 0.3], [2000, 360, 0.4], [2500, 440, 0.8], [3000, 840, 1.6], [Infinity, 1640, 1.6]],
  east_saloon: [[1000, 20, 0], [1200, 44, 0], [1400, 56, 0], [1600, 72, 0], [1800, 160, 0.32], [2000, 224, 0.25], [2500, 274, 0.5], [3000, 524, 1], [Infinity, 1024, 1.35]],
  east_non_saloon: [[1000, 20, 0], [1200, 42.5, 0], [1400, 50, 0], [1600, 60, 0], [1800, 165, 0.17], [2000, 199, 0.22], [2500, 243, 0.44], [3000, 463, 0.88], [Infinity, 903, 1.2]],
};

function roadTax(a: any) {
  const cc = Math.round(num(a.engine_cc) ?? 0);
  const region = ["peninsular", "sabah_sarawak", "labuan", "langkawi_pangkor"].includes(a.region) ? a.region : "peninsular";
  const body = a.body === "non_saloon" ? "non_saloon" : "saloon";
  const owner = a.owner === "company" ? "company" : "individual";
  const exact = "An estimate from JPJ's published rates. JPJ (MyJPJ app, jpj.gov.my) or MyEG shows the exact amount when renewing.";
  if (a.electric === true) {
    return { estimate_rm: null, note: "Electric cars pay road tax by motor power (kW) since 2026, not engine cc. Check JPJ's calculator or MyEG for the figure.", source: exact };
  }
  if (cc < 50 || cc > 10000) return { error: "Give the engine size in cc (e.g. 1497 for a 1.5 L)." };
  const east = region === "sabah_sarawak" || region === "labuan";
  if (owner === "company" && (east || region === "langkawi_pangkor")) {
    return { estimate_rm: null, note: "Company-owned rates outside the Peninsular aren't in TiTi's table. JPJ's calculator has them.", source: exact };
  }
  const table = east
    ? (body === "saloon" ? RT.east_saloon : RT.east_non_saloon)
    : body === "non_saloon" ? RT.peninsular_non_saloon
    : owner === "company" ? RT.peninsular_saloon_company : RT.peninsular_saloon_individual;
  let floor = 0;
  let fee = 0;
  let how = "";
  for (const [top, base, per] of table) {
    if (cc <= top) {
      fee = base + per * (cc - (per ? floor : 0));
      how = per ? `${rm(base)} + ${rm(per)} × ${cc - floor} cc above ${floor} cc` : `flat ${rm(base)} for ${floor + 1}-${top} cc`;
      break;
    }
    floor = top;
  }
  // Langkawi and Pangkor pay half the Peninsular rate, Labuan half the Sabah
  // rate, above 1,000 cc.
  const half = (region === "langkawi_pangkor" || region === "labuan") && cc > 1000;
  if (half) fee = fee / 2;
  fee = Math.round(fee * 100) / 100;
  return {
    estimate_rm: fee,
    per: "year",
    car: `${cc} cc, ${body === "saloon" ? "saloon" : "non-saloon"}, ${owner}-owned, ${region.replace("_", " / ")}`,
    how: half ? `half of (${how})` : how,
    note: body === "saloon" ? "If the grant says non-saloon (pickups, 4x4s, vans), the rate differs." : undefined,
    source: exact,
  };
}

// ============================================================ one request ===

class Turn {
  cards = new Map<string, Card>();
  private geo = new Map<string, Point | null>();
  /** Action cards made this round, in call order; the handler shows them. */
  private pending: Action[] = [];
  constructor(
    readonly db: SupabaseClient,
    readonly userId: string,
    readonly here: Point | null,
  ) {}

  takeActions(): Action[] {
    const out = this.pending;
    this.pending = [];
    return out;
  }

  /**
   * Where to search around. `near` wins: "me" is the phone's location, a name
   * is geocoded. Raw coordinates only count inside Malaysia (the model likes
   * to fill in 0, 0).
   */
  async place(args: any): Promise<Point | null> {
    const near = typeof args?.near === "string" ? args.near.trim() : "";
    if (/^(me|here|my location|near me|nearby|around me)$/i.test(near)) return this.here;
    if (near) {
      if (!this.geo.has(near)) this.geo.set(near, await geocode(near, this.here));
      return this.geo.get(near)!;
    }
    const lat = num(args?.near_lat), lng = num(args?.near_lng);
    return lat != null && lng != null && inMalaysia(lat, lng) ? { lat, lng, label: "that point" } : null;
  }

  async run(name: string, args: any): Promise<unknown> {
    const a = args ?? {};
    switch (name) {
      case "search_meets": return await this.searchMeets(a);
      case "search_spots": return await this.searchSpots(a);
      case "search_clubs": return await this.searchClubs(a);
      case "my_cars": return await this.myCars();
      case "my_summary": return await this.mySummary();
      case "my_points": return await this.myPoints();
      case "my_vouchers": return await this.myVouchers();
      case "partner_offers": return await this.partnerOffers(a);
      case "my_cards": return await this.myCards();
      case "my_meets": return await this.myMeets();
      case "meet_details": return await this.meetDetails(a);
      case "my_clubs": return await this.myClubs();
      case "my_saved_spots": return await this.mySavedSpots();
      case "my_car_documents": return await this.myCarDocuments();
      case "my_car_mods": return await this.myCarMods(a);
      case "my_notifications": return await this.myNotifications(a);
      case "fuel_prices": return await this.fuelPrices();
      case "road_tax_estimate": return roadTax(a);
      case "join_meet": return await this.proposeMeet(a, false);
      case "leave_meet": return await this.proposeMeet(a, true);
      case "save_spot": return await this.proposeSave(a);
      case "open_directions": return await this.proposeDirections(a);
      case "tt_here": return await this.proposeTtHere(a);
      case "open_page": return this.proposePage(a);
      case "open_box_shop": return await this.proposeBox();
      case "claim_voucher": return await this.proposeClaim(a);
      default: return { error: `unknown tool ${name}` };
    }
  }

  // ------------------------------------------------------------- search

  private async searchMeets(a: any) {
    const now = Date.now();
    const from = Date.parse(a.from) || now;
    // Include meets that started before the window but are still on.
    const fromQ = from - 8 * 3600e3;
    let to = Date.parse(a.to) || from + 14 * 86400e3;
    to = Math.min(Math.max(to, from + 3600e3), now + 90 * 86400e3);
    const point = await this.place(a);
    if (a.near && !point) {
      return { meets: [], note: a.near === "me" ? "The member's location is unknown. Ask which area, or search without a place." : `Couldn't place "${a.near}" on the map. Ask for a nearby town, or search without a place.` };
    }
    const radius = Math.min(Math.max(num(a.radius_km) ?? 30, 1), 400);

    const query = (withPoint: boolean, start = fromQ, end = to, anyKind = false) => {
      let q = this.db.from("events_with_counts").select(MEET_COLS).eq("status", "active")
        .gte("starts_at", new Date(start).toISOString()).lte("starts_at", new Date(end).toISOString());
      if (!anyKind && typeof a.type === "string" && a.type !== "any" && TYPE_LABEL[a.type]) q = q.eq("event_type", a.type);
      if (a.official_only === true) q = q.or("event_type.eq.official,club_tier.eq.official,vendor_id.not.is.null");
      if (withPoint && point) {
        const dLat = radius / 111, dLng = radius / (111 * Math.cos(point.lat * Math.PI / 180));
        q = q.gte("lat", point.lat - dLat).lte("lat", point.lat + dLat).gte("lng", point.lng - dLng).lte("lng", point.lng + dLng);
      }
      return q.order("starts_at", { ascending: true }).limit(60);
    };

    const shape = (list: any[], limit: number, inRadius: boolean, after = from) =>
      list
        .filter((r) => meetClosesAt(r) > Math.max(now, after))
        .map((r) => ({ r, d: point ? km(point, r) : null }))
        .filter((x) => !inRadius || x.d == null || x.d <= radius * 1.05)
        .slice(0, limit)
        .map(({ r, d }) => ({ ...this.meetFacts(r), distance_km: d == null ? undefined : round1(d) }));

    const { data, error } = await query(true);
    if (error) throw new Error(`meets: ${error.message}`);
    const meets = shape(data ?? [], 8, true);
    const out: Record<string, unknown> = {
      window: `${fmtWhen(new Date(from).toISOString())} to ${fmtWhen(new Date(to).toISOString())}`,
      near: point ? { place: point.label, radius_km: radius } : undefined,
      meets,
    };
    // Nothing matched: offer any kind, anywhere, on the same dates; else whatever is next.
    if (!meets.length) {
      const { data: all } = await query(false, fromQ, to, true);
      const other = shape(all ?? [], 3, false);
      if (other.length) out.other_kinds_or_places_same_dates = other;
    }
    if (!meets.length && !out.other_kinds_or_places_same_dates) {
      const { data: next } = await query(false, now - 8 * 3600e3, now + 45 * 86400e3, true);
      const upcoming = shape((next ?? []).filter((r: any) => Date.parse(r.starts_at) < from || Date.parse(r.starts_at) > to), 3, false, now);
      if (upcoming.length) out.next_up_other_dates = upcoming;
    }
    return out;
  }

  /** What the model sees of one meet (and its card, remembered for the answer). */
  private meetFacts(r: any) {
    this.cards.set(`meet:${r.id}`, meetCard(r));
    const live = Date.parse(r.starts_at) - 3600e3 <= Date.now();
    return {
      ref: `[[meet:${r.id}]]`,
      title: r.title,
      type: r.is_instant ? "TT now (instant)" : TYPE_LABEL[r.event_type] ?? r.event_type,
      when: fmtWhen(r.starts_at),
      status: live ? "on now" : "upcoming",
      venue: r.venue_name,
      going: r.attendee_count ?? 0,
      full: r.max_attendees != null && (r.attendee_count ?? 0) >= r.max_attendees,
      host: r.vendor_name ?? r.club_name ?? undefined,
      official: isOfficialMeet(r),
      friends_only: r.visibility === "friends" || undefined,
      you_host: r.organizer_id === this.userId || undefined,
    };
  }

  private async searchSpots(a: any) {
    const point = await this.place(a);
    if (a.near && !point) {
      return { spots: [], note: a.near === "me" ? "The member's location is unknown. Ask which area, or search without a place." : `Couldn't place "${a.near}" on the map.` };
    }
    const limit = Math.min(Math.max(Math.round(num(a.limit) ?? 5), 1), 8);
    const kind = typeof a.kind === "string" && KIND_LABEL[a.kind] ? a.kind : null;
    let list: any[];
    if (point) {
      // The app's own nearest-first RPC (spots only), then filter by kind.
      const { data, error } = await this.db.rpc("nearest_spots", { p_lat: point.lat, p_lng: point.lng, p_limit: 50 });
      if (error) throw new Error(`spots: ${error.message}`);
      list = (data ?? []) as any[];
    } else {
      let q = this.db.from("places_with_counts").select(SPOT_COLS).eq("is_spot", true);
      if (kind) q = q.eq("kind", kind);
      const { data, error } = await q.order("score", { ascending: false }).limit(limit);
      if (error) throw new Error(`spots: ${error.message}`);
      list = data ?? [];
    }
    if (kind) list = list.filter((r) => r.kind === kind);
    const spots = list.slice(0, limit).map((r) => this.spotFacts(r, point ? km(point, r) : null));
    return { near: point ? point.label : undefined, spots, note: spots.length ? undefined : "No spots matched. The map is new; members can suggest spots (30 points when one goes live)." };
  }

  private spotFacts(r: any, d: number | null) {
    this.cards.set(`spot:${r.id}`, spotCard(r, d));
    return {
      ref: `[[spot:${r.id}]]`,
      name: r.name,
      kind: KIND_LABEL[r.kind] ?? r.kind,
      distance_km: d == null ? undefined : round1(d),
      checkins: spotCheckins(r),
      upcoming_meets: r.upcoming_meets || undefined,
      partner: r.vendor_name ?? undefined,
      top_spot: r.is_top || undefined,
      about: short(r.description, 160) || undefined,
      tags: Array.isArray(r.tags) && r.tags.length ? r.tags.slice(0, 5) : undefined,
    };
  }

  private async searchClubs(a: any) {
    let q = this.db.from("clubs").select(CLUB_COLS);
    const s = typeof a.query === "string" ? a.query.trim().replace(/[%,()*]/g, "").slice(0, 40) : "";
    if (s) q = q.or(`name.ilike.%${s}%,handle.ilike.%${s}%,description.ilike.%${s}%`);
    const near = typeof a.near === "string" ? a.near.trim() : "";
    const state = STATES.find(([re]) => re.test(near))?.[1];
    if (state) q = q.eq("home_state", state);
    const { data, error } = await q.order("created_at", { ascending: false }).limit(30);
    if (error) throw new Error(`clubs: ${error.message}`);
    let list = (data ?? []) as any[];
    const point = near && !state ? await this.place({ near }) : null;
    const dist = (r: any) => (point && r.garage_lat != null && r.garage_lng != null ? km(point, { lat: r.garage_lat, lng: r.garage_lng }) : null);
    if (point) list = list.sort((x, y) => (dist(x) ?? 1e9) - (dist(y) ?? 1e9));
    else list = list.sort((x, y) => Number(clubOfficial(y)) - Number(clubOfficial(x)) || memberCount(y) - memberCount(x));
    const clubs = list.slice(0, 8).map((r) => {
      this.cards.set(`club:${r.id}`, clubCard(r));
      const d = dist(r);
      return {
        ref: `[[club:${r.id}]]`,
        name: r.name,
        handle: r.handle ? `@${r.handle}` : undefined,
        state: r.home_state ?? undefined,
        members: memberCount(r),
        official: clubOfficial(r),
        garage: r.garage_name ?? undefined,
        distance_km: d == null ? undefined : round1(d),
        about: short(r.description, 140) || undefined,
      };
    });
    return { clubs, note: clubs.length ? undefined : "No clubs matched. Anyone can apply to start one (Create, Start a car club)." };
  }

  private async myCars() {
    const { data, error } = await this.db.from("cars").select(CAR_COLS).eq("owner_id", this.userId).order("is_default", { ascending: false }).limit(10);
    if (error) throw new Error(`cars: ${error.message}`);
    const cars = (data ?? []).map((r: any) => {
      this.cards.set(`car:${r.id}`, carCard(r));
      return { ref: `[[car:${r.id}]]`, id: r.id, make: r.make, model: r.model, year: r.year ?? undefined, color: r.color ?? undefined, body: r.body_style ?? undefined, specs: r.specs ?? undefined, main_car: r.is_default || undefined };
    });
    return { cars, note: cars.length ? undefined : "No cars in their garage yet. They can add one: [Add a car](/car/new)." };
  }

  // ------------------------------------------------------------ my stuff

  private async points(): Promise<number> {
    const { data } = await this.db.from("profiles").select("points").eq("id", this.userId).maybeSingle();
    return (data as any)?.points ?? 0;
  }

  /** Short heads-ups: papers due, a box to open, a voucher ending. Also the "Heads-up" in the prompt. */
  async headsUp(): Promise<string[]> {
    const [docs, boxes, vouchers] = await Promise.all([
      this.carDocs().catch(() => []),
      this.db.rpc("my_boxes").then(rows, () => []),
      this.db.rpc("my_vouchers", { p_limit: 30 }).then(rows, () => []),
    ]);
    const out: string[] = [];
    for (const c of docs) {
      for (const d of c.due) {
        const soon = d.what === "road tax" || d.what === "insurance" ? 30 : 14;
        if (d.days_left <= soon) out.push(`${d.what} for their ${c.car} ${d.days_left < 0 ? "ran out" : "runs out"} ${inDays(d.days_left)} (${d.date})`);
      }
    }
    const sealed = boxes.filter((b: any) => b.status === "sealed").length;
    if (sealed) out.push(`${sealed} unopened blind box${sealed === 1 ? "" : "es"}`);
    for (const v of vouchers) {
      if (v.status !== "active" || !v.expires_at) continue;
      const n = daysUntil(new Date(Date.parse(v.expires_at) + 8 * 3600e3).toISOString());
      if (n >= 0 && n <= 7) out.push(`voucher "${short(v.title, 40)}" at ${v.vendor_name} ends ${inDays(n)}`);
    }
    return out.slice(0, 5);
  }

  private async mySummary() {
    const uid = this.userId;
    const since = new Date(Date.now() - 8 * 3600e3).toISOString();
    const [prof, friends, cars, clubs, unread, going, streak, alerts, boxes, vouchers] = await Promise.all([
      this.db.from("profiles").select("display_name, username, points, home_state, is_organizer, club_owner, created_at").eq("id", uid).maybeSingle(),
      this.db.rpc("friend_count", { p_user: uid }),
      this.db.from("cars").select("id", { count: "exact", head: true }).eq("owner_id", uid),
      this.db.from("club_members").select("role, clubs(name)").eq("user_id", uid),
      this.db.from("notifications").select("id", { count: "exact", head: true }).eq("user_id", uid).is("read_at", null),
      this.db.from("event_attendees").select("event_id, events!inner(starts_at, status)").eq("user_id", uid).gte("events.starts_at", since).eq("events.status", "active"),
      this.db.rpc("tt_streak_weeks", { p_user: uid }),
      this.headsUp().catch(() => []),
      this.db.rpc("my_boxes").then(rows, () => []),
      this.db.rpc("my_vouchers", { p_limit: 50 }).then(rows, () => []),
    ]);
    const p = prof.data as any;
    return {
      name: p?.display_name ?? undefined,
      username: p?.username ? `@${p.username}` : undefined,
      member_since: p?.created_at ? fmtDay(p.created_at) : undefined,
      home_state: p?.home_state ?? undefined,
      points: p?.points ?? 0,
      friends: typeof friends.data === "number" ? friends.data : undefined,
      cars: cars.count ?? 0,
      clubs: rows(clubs).map((r: any) => `${r.clubs?.name ?? "a club"} (${r.role})`),
      unread_notifications: unread.count ?? 0,
      unopened_boxes: boxes.filter((b: any) => b.status === "sealed").length,
      active_vouchers: vouchers.filter((v: any) => v.status === "active").length,
      upcoming_meets_going: rows(going).length,
      tt_streak_weeks: typeof streak.data === "number" ? streak.data : undefined,
      organizer: p?.is_organizer || undefined,
      heads_up: alerts.length ? alerts : undefined,
    };
  }

  private async myPoints() {
    const [bal, hist, rules, settings] = await Promise.all([
      this.points(),
      this.db.rpc("my_point_history", { p_limit: 10 }),
      this.db.from("point_rules").select("reason, points, label, description").gt("points", 0).order("sort"),
      this.db.from("platform_settings").select("key, value").in("key", ["box_points_cost", "portrait_cost_points"]),
    ]);
    const set = Object.fromEntries(rows(settings).map((r: any) => [r.key, r.value]));
    return {
      balance: bal,
      recent: rows(hist).map((r: any) => ({ change: r.delta > 0 ? `+${r.delta}` : String(r.delta), what: r.label ?? r.reason, note: short(r.note, 60) || undefined, when: fmtWhen(r.created_at) })),
      ways_to_earn: rows(rules).map((r: any) => ({ how: r.label, points: r.points, detail: r.description })),
      spend_on: { blind_box: Number(set.box_points_cost ?? 100), ai_car_portrait: Number(set.portrait_cost_points ?? 300), partner_vouchers: "price set by each partner, some free" },
      page: "/me/points",
    };
  }

  private async myVouchers() {
    const { data, error } = await this.db.rpc("my_vouchers", { p_limit: 30 });
    if (error) throw new Error(`vouchers: ${error.message}`);
    const list = (data ?? []) as any[];
    const facts = (r: any) => {
      this.cards.set(`voucher:${r.id}`, voucherCard(r));
      const n = r.expires_at ? daysUntil(new Date(Date.parse(r.expires_at) + 8 * 3600e3).toISOString()) : null;
      return {
        ref: `[[voucher:${r.id}]]`,
        title: r.title,
        partner: r.vendor_name,
        value: discount(r),
        points_spent: r.points_spent || undefined,
        claimed: fmtDay(r.claimed_at),
        expires: r.expires_at ? `${fmtDay(r.expires_at)} (${n != null && n >= 0 ? inDays(n) : "ended"})` : undefined,
        used: r.redeemed_at ? fmtDay(r.redeemed_at) : undefined,
      };
    };
    const active = list.filter((r) => r.status === "active").map(facts);
    const used = list.filter((r) => r.status === "redeemed").slice(0, 5).map(facts);
    const expired = list.filter((r) => r.status !== "active" && r.status !== "redeemed").slice(0, 3).map((r) => ({ title: r.title, partner: r.vendor_name, status: r.status }));
    return {
      active,
      used: used.length ? used : undefined,
      expired_or_cancelled: expired.length ? expired : undefined,
      how_to_use: "Open the voucher (its card) and show the QR at the shop; the staff scan it.",
      note: list.length ? undefined : "No vouchers yet. Partner deals: partner_offers, or the Rewards page.",
    };
  }

  private async partnerOffers(a: any) {
    const point = await this.place(a);
    const limit = Math.min(Math.max(Math.round(num(a.limit) ?? 5), 1), 8);
    const [{ data, error }, bal] = await Promise.all([this.db.rpc("shop_vouchers", { p_limit: 60 }), this.points()]);
    if (error) throw new Error(`offers: ${error.message}`);
    let list = (data ?? []) as any[];
    const dist = new Map<string, number>();
    if (point && list.length) {
      const ids = [...new Set(list.map((r) => r.place_id).filter(Boolean))];
      if (ids.length) {
        const { data: places } = await this.db.from("places").select("id, lat, lng").in("id", ids);
        for (const p of (places ?? []) as any[]) if (p.lat != null && p.lng != null) dist.set(p.id, km(point, p));
      }
      list = list.sort((x, y) => (dist.get(x.place_id) ?? 1e9) - (dist.get(y.place_id) ?? 1e9));
    }
    const offers = list.slice(0, limit).map((r) => {
      this.cards.set(`offer:${r.id}`, offerCard(r));
      const d = dist.get(r.place_id);
      return {
        ref: `[[offer:${r.id}]]`,
        offer_id: r.id,
        title: r.title,
        partner: r.vendor_name,
        partner_type: r.vendor_type ?? undefined,
        value: discount(r),
        points_cost: r.points_cost ?? 0,
        product: r.product_name ?? undefined,
        ends: r.ends_at ? fmtDay(r.ends_at) : undefined,
        distance_km: d == null ? undefined : round1(d),
        already_have_it: r.my_active_claim ? true : undefined,
        limit_reached: r.per_user_limit != null && r.my_claims >= r.per_user_limit ? true : undefined,
        can_afford: (r.points_cost ?? 0) <= bal,
      };
    });
    return { your_points: bal, offers, note: offers.length ? undefined : "No partner deals open right now." };
  }

  private async myCards() {
    const [cards, types, boxes, trades, claims, shop] = await Promise.all([
      this.db.rpc("my_cards").then(rows),
      this.db.from("card_types").select("id, name, rarity").eq("active", true).order("sort").then(rows),
      this.db.rpc("my_boxes").then(rows),
      this.db.rpc("my_trades", { p_limit: 20 }).then(rows),
      this.db.rpc("my_card_reward_claims", { p_limit: 20 }).then(rows),
      this.db.rpc("card_reward_shop").then(rows),
    ]);
    const held = cards.filter((c: any) => c.status === "held");
    const count = new Map<string, number>();
    for (const c of held) count.set(c.card_id, (count.get(c.card_id) ?? 0) + 1);
    const byRarity = { common: 0, rare: 0, legendary: 0 } as Record<string, number>;
    for (const t of types) byRarity[t.rarity] = (byRarity[t.rarity] ?? 0) + (count.get(t.id) ?? 0);
    const owned = types.filter((t: any) => count.has(t.id));
    const sealed = boxes.filter((b: any) => b.status === "sealed");
    const pending = trades.filter((t: any) => t.status === "pending");
    return {
      collection: `${owned.length} of ${types.length} cards`,
      // the database says "legendary"; members know the tier as "secret"
      cards: types.map((t: any) => ({ name: t.name, rarity: t.rarity === "legendary" ? "secret" : t.rarity, have: count.get(t.id) ?? 0 })),
      doubles: [...count.values()].reduce((s, n) => s + Math.max(0, n - 1), 0),
      unopened_boxes: sealed.length,
      open_box_page: sealed.length ? `/cards/box/${sealed[0].id}` : undefined,
      trades_waiting_for_you: pending.filter((t: any) => t.to_user === this.userId).map((t: any) => `from @${t.from_username}`),
      trades_you_sent: pending.filter((t: any) => t.from_user === this.userId).map((t: any) => `to @${t.to_username}`),
      prize_claims: claims.filter((c: any) => c.status === "active").map((c: any) => ({ prize: c.title, partner: c.vendor_name ?? undefined, expires: c.expires_at ? fmtDay(c.expires_at) : undefined })),
      prizes: shop.filter((r: any) => r.active !== false).slice(0, 6).map((r: any) => {
        const need = r.need_full_set ? "a full set" : [r.need_common && `${r.need_common} common`, r.need_rare && `${r.need_rare} rare`, r.need_legendary && `${r.need_legendary} secret`].filter(Boolean).join(" + ");
        const enough = r.need_full_set ? owned.length === types.length && types.length > 0
          : byRarity.common >= (r.need_common ?? 0) && byRarity.rare >= (r.need_rare ?? 0) && byRarity.legendary >= (r.need_legendary ?? 0);
        return { prize: r.title, partner: r.vendor_name ?? undefined, needs: need || "no cards", you_have_enough: enough };
      }),
      page: "/cards",
    };
  }

  private async myMeets() {
    const uid = this.userId;
    const since = new Date(Date.now() - 8 * 3600e3).toISOString();
    const [att, marks, meetCheckins, spotCheckins, streak] = await Promise.all([
      this.db.from("event_attendees").select("event_id").eq("user_id", uid).order("created_at", { ascending: false }).limit(200).then(rows),
      this.db.from("event_bookmarks").select("event_id").eq("user_id", uid).limit(100).then(rows),
      this.db.from("checkins").select("event_id", { count: "exact", head: true }).eq("user_id", uid),
      this.db.from("place_checkins").select("id", { count: "exact", head: true }).eq("user_id", uid),
      this.db.rpc("tt_streak_weeks", { p_user: uid }),
    ]);
    const going = new Set(att.map((r: any) => r.event_id));
    const marked = new Set(marks.map((r: any) => r.event_id));
    const ids = [...new Set([...going, ...marked])].filter((id) => UUID.test(id));
    let q = this.db.from("events_with_counts").select(MEET_COLS).eq("status", "active").gte("starts_at", since);
    q = ids.length ? q.or(`organizer_id.eq.${uid},id.in.(${ids.join(",")})`) : q.eq("organizer_id", uid);
    const { data, error } = await q.order("starts_at", { ascending: true }).limit(30);
    if (error) throw new Error(`my meets: ${error.message}`);
    const upcoming = ((data ?? []) as any[]).filter((r) => meetClosesAt(r) > Date.now());
    const pick = (f: (r: any) => boolean) => upcoming.filter(f).slice(0, 6).map((r) => this.meetFacts(r));
    return {
      going: pick((r) => going.has(r.id)),
      hosting: pick((r) => r.organizer_id === uid),
      bookmarked: pick((r) => marked.has(r.id) && !going.has(r.id)),
      meets_checked_in_total: meetCheckins.count ?? 0,
      spot_checkins_total: spotCheckins.count ?? 0,
      tt_streak_weeks: typeof streak.data === "number" ? streak.data : undefined,
      page: "/meets",
    };
  }

  private async meetDetails(a: any) {
    const id = idFrom(a.meet_id);
    if (!id) return { error: "No meet id. Find the meet first and pass the id from its ref." };
    const [ev, mine, checked, marked] = await Promise.all([
      this.db.from("events_with_counts").select(MEET_COLS + ",description").eq("id", id).maybeSingle(),
      this.db.from("event_attendees").select("event_id").eq("event_id", id).eq("user_id", this.userId).maybeSingle(),
      this.db.from("checkins").select("event_id").eq("event_id", id).eq("user_id", this.userId).maybeSingle(),
      this.db.from("event_bookmarks").select("event_id").eq("event_id", id).eq("user_id", this.userId).maybeSingle(),
    ]);
    const r = ev.data as any;
    if (!r) return { error: "That meet isn't visible to the member (gone, friends-only or a wrong id)." };
    const start = Date.parse(r.starts_at);
    return {
      ...this.meetFacts(r),
      about: short(r.description, 400) || undefined,
      address: r.address ?? undefined,
      ends: r.ends_at ? fmtWhen(r.ends_at) : undefined,
      checked_in_count: r.checkin_count ?? 0,
      max_people: r.max_attendees ?? undefined,
      cancelled: r.status !== "active" || undefined,
      check_in_window: `${fmtWhen(new Date(start - 3600e3).toISOString())} to ${fmtWhen(new Date(meetClosesAt(r)).toISOString())}`,
      you_are_going: !!mine.data,
      you_checked_in: !!checked.data,
      you_bookmarked: !!marked.data,
      over: meetClosesAt(r) < Date.now() || undefined,
    };
  }

  private async myClubs() {
    const { data, error } = await this.db.from("club_members").select(`role, created_at, clubs(${CLUB_COLS})`).eq("user_id", this.userId);
    if (error) throw new Error(`my clubs: ${error.message}`);
    const clubs = ((data ?? []) as any[]).filter((r) => r.clubs).map((r) => {
      const c = r.clubs;
      this.cards.set(`club:${c.id}`, clubCard(c));
      return { ref: `[[club:${c.id}]]`, name: c.name, role: r.role, members: memberCount(c), official: clubOfficial(c), state: c.home_state ?? undefined, joined: fmtDay(r.created_at) };
    });
    return { clubs, note: clubs.length ? undefined : "Not in a club yet. Find one in Clubs (/clubs) or start one (/club/apply)." };
  }

  private async mySavedSpots() {
    const { data, error } = await this.db.rpc("my_saved_places");
    if (error) throw new Error(`saved: ${error.message}`);
    let list = (data ?? []) as any[];
    if (this.here) list = list.sort((x, y) => km(this.here!, x) - km(this.here!, y));
    const spots = list.slice(0, 8).map((r) => this.spotFacts(r, this.here ? km(this.here, r) : null));
    return { spots, total: list.length, note: list.length ? undefined : "No saved spots yet. The bookmark on a spot's page saves it; saved spots always show on their map." };
  }

  /** The member's cars with their papers: one row per car, due items sorted soonest first. */
  private async carDocs() {
    const { data, error } = await this.db.from("cars").select("id, make, model, year, is_default, car_documents(*)").eq("owner_id", this.userId).order("is_default", { ascending: false }).limit(10);
    if (error) throw new Error(`docs: ${error.message}`);
    return ((data ?? []) as any[]).map((c) => {
      const d = Array.isArray(c.car_documents) ? c.car_documents[0] : c.car_documents;
      const due: { what: string; date: string; days_left: number }[] = [];
      const add = (what: string, v: unknown) => {
        if (typeof v === "string" && v) due.push({ what, date: fmtDay(v), days_left: daysUntil(v) });
      };
      add("road tax", d?.road_tax_expiry);
      add("insurance", d?.insurance_expiry);
      add("PUSPAKOM inspection", d?.puspakom_due);
      add("service", d?.service_due_on);
      due.sort((x, y) => x.days_left - y.days_left);
      return { id: c.id as string, car: carName(c), year: c.year ?? undefined, main: c.is_default || undefined, doc: d ?? null, due };
    });
  }

  private async myCarDocuments() {
    const cars = await this.carDocs();
    if (!cars.length) return { cars: [], note: "No cars in their garage yet: [Add a car](/car/new)." };
    return {
      today: fmtDay(todayMyt()),
      cars: cars.map((c) => ({
        car: c.car,
        year: c.year,
        main_car: c.main,
        due: c.due.map((x) => ({ what: x.what, date: x.date, days_left: x.days_left, status: x.days_left < 0 ? "OVERDUE" : x.days_left <= 30 ? "due soon" : "ok" })),
        insurer: c.doc?.insurer ?? undefined,
        ncd: c.doc?.ncd_pct != null ? `${c.doc.ncd_pct}%` : undefined,
        sum_insured: c.doc?.sum_insured != null ? rm(Number(c.doc.sum_insured)) : undefined,
        service_due_km: c.doc?.service_due_km ?? undefined,
        nothing_saved: !c.doc || undefined,
        page: `/car/${c.id}/documents`,
      })),
      note: "Only the member sees these. The app reminds them 30, 7 and 1 day before road tax or insurance runs out.",
    };
  }

  private async myCarMods(a: any) {
    const { data: cars, error } = await this.db.from("cars").select("id, make, model, year, is_default").eq("owner_id", this.userId).order("is_default", { ascending: false }).limit(10);
    if (error) throw new Error(`mods: ${error.message}`);
    const list = (cars ?? []) as any[];
    if (!list.length) return { mods: [], note: "No cars in their garage yet: [Add a car](/car/new)." };
    const want = typeof a.car === "string" ? a.car.trim().toLowerCase() : "";
    const car = (want && list.find((c) => `${c.make} ${c.model} ${c.year ?? ""}`.toLowerCase().includes(want))) || list[0];
    const { data: mods, error: e2 } = await this.db.rpc("car_mod_list", { p_car: car.id });
    if (e2) throw new Error(`mods: ${e2.message}`);
    const m = (mods ?? []) as any[];
    const total = m.reduce((s, r) => s + (Number(r.cost) || 0), 0);
    return {
      car: carName(car),
      other_cars: list.filter((c) => c.id !== car.id).map(carName),
      mods: m.slice(0, 20).map((r) => ({
        what: r.title,
        category: r.category ?? undefined,
        shop: r.vendor_name ?? r.shop ?? undefined,
        done: r.done_on ? fmtDay(r.done_on) : undefined,
        cost: r.cost != null ? rm(Number(r.cost)) : undefined,
        only_me: r.is_private || undefined,
      })),
      total_spent: total ? rm(Math.round(total * 100) / 100) : undefined,
      page: `/car/${car.id}`,
      note: m.length ? "Prices are private: only the member sees them." : "No mods logged yet. Add them on the car's page (Mods).",
    };
  }

  private async myNotifications(a: any) {
    let q = this.db.from("notifications")
      .select("type, body, read_at, created_at, actor:profiles!notifications_actor_id_fkey(username), events(title), clubs(name)")
      .eq("user_id", this.userId);
    if (a.unread_only === true) q = q.is("read_at", null);
    const [{ data, error }, unread] = await Promise.all([
      q.order("created_at", { ascending: false }).limit(12),
      this.db.from("notifications").select("id", { count: "exact", head: true }).eq("user_id", this.userId).is("read_at", null),
    ]);
    if (error) throw new Error(`notifications: ${error.message}`);
    return {
      unread: unread.count ?? 0,
      recent: ((data ?? []) as any[]).map((r) => ({
        kind: String(r.type).replace(/_/g, " "),
        from: r.actor?.username ? `@${r.actor.username}` : undefined,
        about: r.events?.title ?? r.clubs?.name ?? undefined,
        text: short(r.body, 120) || undefined,
        unread: !r.read_at || undefined,
        when: fmtWhen(r.created_at),
      })),
      page: "/activity",
    };
  }

  private async fuelPrices() {
    const list = await fuelRows();
    const [now, prev] = list;
    const p = (r: any) => ({
      ron95_budi95_subsidised: r.ron95_budi95,
      ron95_unsubsidised: r.ron95,
      ron95_skps: r.ron95_skps,
      ron97: r.ron97,
      diesel_peninsular: r.diesel,
      diesel_east_malaysia: r.diesel_eastmsia,
      diesel_budi_subsidised: r.diesel_budi,
      diesel_skds: r.diesel_skds,
    });
    const cur = p(now);
    const change: Record<string, string> = {};
    if (prev) {
      const old = p(prev) as Record<string, number>;
      for (const [k, v] of Object.entries(cur)) {
        const d = Math.round(((v as number) - (old[k] ?? v)) * 100) / 100;
        if (d) change[k] = `${d > 0 ? "+" : ""}${d.toFixed(2)}`;
      }
    }
    return {
      week_from: fmtDay(now.date),
      rm_per_litre: cur,
      change_from_last_week: prev ? (Object.keys(change).length ? change : "no change") : undefined,
      notes: "BUDI95 is the subsidised RON95 price for eligible Malaysians (MyKad at the pump, with a monthly quota); everyone else pays the unsubsidised price. SKPS and SKDS are subsidy schemes for approved fleets. Prices are set weekly.",
      source: "data.gov.my (KPDN weekly fuel prices)",
    };
  }

  // ------------------------------------------------------------- actions

  private offer(a: Omit<Action, "id">): { shown: true; note: string } {
    this.pending.push({ ...a, id: crypto.randomUUID() });
    return {
      shown: true,
      note: `A card with a "${a.label}" button is on screen now. Nothing has happened yet: the member taps it to confirm. Say so in one short line, don't claim it's done.`,
    };
  }

  private async proposeMeet(a: any, leave: boolean) {
    const id = idFrom(a.meet_id);
    if (!id) return { error: "No meet id. Find the meet first (search_meets or my_meets) and pass the id from its ref." };
    const [ev, mine] = await Promise.all([
      this.db.from("events_with_counts").select(MEET_COLS).eq("id", id).maybeSingle(),
      this.db.from("event_attendees").select("event_id").eq("event_id", id).eq("user_id", this.userId).maybeSingle(),
    ]);
    const r = ev.data as any;
    if (!r) return { error: "That meet isn't visible to the member (gone, friends-only or a wrong id). No card shown." };
    if (r.status !== "active") return { error: "That meet was cancelled. No card shown." };
    if (meetClosesAt(r) < Date.now()) return { error: "That meet is over. No card shown." };
    const card = meetCard(r);
    this.cards.set(`meet:${r.id}`, card);
    if (!leave) {
      if (mine.data) return { already_going: true, note: "They're already going. No card shown." };
      if (r.organizer_id === this.userId) return { note: "They host this meet, so they're in already. No card shown." };
      if (r.max_attendees != null && (r.attendee_count ?? 0) >= r.max_attendees) return { error: "That meet is full. No card shown." };
    } else if (!mine.data) {
      return { note: "They aren't on that meet's list. No card shown." };
    }
    return this.offer({
      kind: leave ? "leave_meet" : "join_meet",
      label: leave ? "Leave" : "Join",
      title: card.title,
      detail: card.subtitle,
      image: card.image,
      target: r.id,
      route: card.route,
      lat: num(r.lat) ?? undefined,
      lng: num(r.lng) ?? undefined,
      after: cleanAfter(a.after) ?? (leave ? "Done, you're off the list." : "You're in. Want directions?"),
    });
  }

  private async spotRow(v: unknown) {
    const id = idFrom(v);
    if (!id) return null;
    const { data } = await this.db.from("places_with_counts").select(SPOT_COLS).eq("id", id).maybeSingle();
    return data as any;
  }

  private async proposeSave(a: any) {
    const r = await this.spotRow(a.spot_id);
    if (!r) return { error: "No such spot. Find it first (search_spots) and pass the id from its ref. No card shown." };
    const { data: saved } = await this.db.from("place_saves").select("place_id").eq("place_id", r.id).eq("user_id", this.userId).maybeSingle();
    if (saved) return { already_saved: true, note: "It's already in their saved spots. No card shown." };
    const card = spotCard(r, this.here ? km(this.here, r) : null);
    return this.offer({ kind: "save_spot", label: "Save", title: card.title, detail: card.subtitle, image: card.image, target: r.id, route: card.route, after: cleanAfter(a.after) ?? "Saved. It stays on your map." });
  }

  private async proposeDirections(a: any) {
    const meetId = idFrom(a.meet_id);
    if (meetId) {
      const { data } = await this.db.from("events_with_counts").select(MEET_COLS).eq("id", meetId).maybeSingle();
      const r = data as any;
      if (!r || r.lat == null || r.lng == null) return { error: "That meet has no location I can see. No card shown." };
      const card = meetCard(r);
      return this.offer({ kind: "directions", label: "Directions", title: card.title, detail: r.venue_name ?? card.subtitle, image: card.image, target: r.id, route: card.route, lat: r.lat, lng: r.lng });
    }
    const r = await this.spotRow(a.spot_id);
    if (!r) return { error: "Pass a meet_id or spot_id from a tool result. No card shown." };
    const card = spotCard(r, this.here ? km(this.here, r) : null);
    return this.offer({ kind: "directions", label: "Directions", title: card.title, detail: card.subtitle, image: card.image, target: r.id, route: card.route, lat: r.lat, lng: r.lng });
  }

  private async proposeTtHere(a: any) {
    const r = await this.spotRow(a.spot_id);
    if (!r) return { error: "No such spot. Find it first (search_spots) and pass the id from its ref. No card shown." };
    const d = this.here ? km(this.here, r) : null;
    const card = spotCard(r, d);
    const far = d == null || d > 1;
    return this.offer({
      kind: "tt_here",
      label: far ? "Plan a TT here" : "TT here",
      title: card.title,
      detail: far ? "TT now works within 1 km; this plans a session there" : "Tell friends you're here now",
      image: card.image,
      target: r.id,
      route: card.route,
      lat: r.lat,
      lng: r.lng,
    });
  }

  private proposePage(a: any) {
    const path = typeof a.path === "string" ? a.path.trim() : "";
    if (!pageAllowed(path)) return { error: `The app can't open "${short(path, 60)}". Use an app link path or an id page from a tool result. No card shown.` };
    const label = short(typeof a.label === "string" && a.label.trim() ? a.label.trim() : "Open", 24);
    const known = PAGE_TITLES[path.split("?")[0]] ?? PAGE_TITLES[path];
    const card = [...this.cards.values()].find((c) => c.route === path);
    return this.offer({ kind: "open_page", label, title: card?.title ?? known ?? label, detail: card?.subtitle ?? "", image: card?.image ?? null, route: path });
  }

  private async proposeBox() {
    const [boxes, bal, settings] = await Promise.all([
      this.db.rpc("my_boxes").then(rows),
      this.points(),
      this.db.from("platform_settings").select("value").eq("key", "box_points_cost").maybeSingle(),
    ]);
    const cost = Number((settings.data as any)?.value ?? 100);
    const sealed = boxes.filter((b: any) => b.status === "sealed");
    if (sealed.length) {
      return this.offer({ kind: "open_box", label: "Open box", title: sealed.length === 1 ? "Your unopened blind box" : `${sealed.length} unopened blind boxes`, detail: "Shake to open", image: "assets/titi/box_closed.png", route: `/cards/box/${sealed[0].id}` });
    }
    return this.offer({
      kind: "open_page",
      label: bal >= cost ? "Get a box" : "Open Cards",
      title: `Blind box · ${cost} points`,
      detail: bal >= cost ? `You have ${bal} points` : `You have ${bal}; ${cost - bal} more to go`,
      image: "assets/titi/box_closed.png",
      route: "/cards",
    });
  }

  private async proposeClaim(a: any) {
    const id = idFrom(a.offer_id);
    if (!id) return { error: "No offer id. Look it up with partner_offers first. No card shown." };
    const [{ data, error }, bal] = await Promise.all([this.db.rpc("shop_vouchers", { p_limit: 100 }), this.points()]);
    if (error) throw new Error(`offers: ${error.message}`);
    const r = ((data ?? []) as any[]).find((x) => x.id === id);
    if (!r) return { error: "That voucher isn't open to claim right now. No card shown." };
    if (r.my_active_claim) return { already_have_it: true, voucher_page: `/voucher/${r.my_active_claim}`, note: "They already have it (unused). Offer open_page with that path instead." };
    if (r.per_user_limit != null && r.my_claims >= r.per_user_limit) return { error: "They've claimed this one as many times as allowed. No card shown." };
    const cost = r.points_cost ?? 0;
    if (cost > bal) return { error: `Not enough points: it costs ${cost}, they have ${bal}. No card shown.` };
    const card = offerCard(r);
    this.cards.set(`offer:${r.id}`, card);
    return this.offer({
      kind: "claim_voucher",
      label: cost ? `Claim · ${cost} pts` : "Claim free",
      title: card.title,
      detail: [r.vendor_name, discount(r)].filter(Boolean).join(" · "),
      image: card.image,
      target: r.id,
      route: card.route,
      after: cleanAfter(a.after) ?? "Claimed. Show its QR at the shop.",
    });
  }

  /** A card for a ref: from this turn's tool results, else looked up (as the member) by id. */
  async card(key: string): Promise<Card | null> {
    const hit = this.cards.get(key);
    if (hit) return hit;
    const [kind, id] = key.split(":");
    if (!UUID.test(id)) return null;
    try {
      if (kind === "meet") {
        const { data } = await this.db.from("events_with_counts").select(MEET_COLS).eq("id", id).maybeSingle();
        return data ? meetCard(data) : null;
      }
      if (kind === "spot") {
        const { data } = await this.db.from("places_with_counts").select(SPOT_COLS).eq("id", id).maybeSingle();
        return data ? spotCard(data) : null;
      }
      if (kind === "club") {
        const { data } = await this.db.from("clubs").select(CLUB_COLS).eq("id", id).maybeSingle();
        return data ? clubCard(data) : null;
      }
      if (kind === "car") {
        const { data } = await this.db.from("cars").select(CAR_COLS).eq("id", id).maybeSingle();
        return data ? carCard(data) : null;
      }
      if (kind === "voucher") {
        const r = rows(await this.db.rpc("my_vouchers", { p_limit: 100 })).find((x: any) => x.id === id);
        return r ? voucherCard(r) : null;
      }
      if (kind === "offer") {
        const r = rows(await this.db.rpc("shop_vouchers", { p_limit: 100 })).find((x: any) => x.id === id);
        return r ? offerCard(r) : null;
      }
    } catch {
      /* no card */
    }
    return null;
  }
}

/** The model's "after" line, kept short and plain. */
function cleanAfter(v: unknown): string | undefined {
  if (typeof v !== "string") return undefined;
  const s = v.replace(/\[\[[^\]]*\]\]/g, "").replace(/\s+/g, " ").trim();
  return s ? short(s, 140) : undefined;
}

// Pages an open_page card may open: the app links above, a few more, and id
// pages. The app checks the same list before it navigates.
const PAGE_TITLES: Record<string, string> = {
  "/me/points": "Points", "/cards": "Cards", "/rewards": "Rewards", "/scan": "Scan a QR", "/me/qr": "My QR",
  "/friends": "Friends", "/meets": "My meets", "/clubs": "Clubs", "/map": "Map", "/chats": "Chats", "/posts": "Posts",
  "/me": "Me", "/suggest-spot": "Suggest a spot", "/car/new": "Add a car", "/garage": "My garage", "/create-event": "Plan a meet",
  "/organizer/apply": "Become an organizer", "/club/apply": "Start a club", "/partner/apply": "Partner with TT Spot",
  "/settings": "Settings", "/settings/notifications": "Push notifications", "/me/moments": "My moments", "/activity": "Activity",
  "/saved": "Saved posts",
};
const PAGE_QUERIES = new Set(["/rewards?tab=vouchers", "/rewards?tab=partners", "/cards?tab=trades", "/cards?tab=prizes", "/create-event?session=1"]);
const PAGE_ID = /^\/(event|place|club|partner|car|profile|voucher|cards\/box|cards\/prize)\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(\/documents)?$/i;
const pageAllowed = (p: string) => p in PAGE_TITLES || PAGE_QUERIES.has(p) || PAGE_ID.test(p);

// ============================================================== the shaper ===

type Ev =
  | { t: "delta"; text: string }
  | { t: "break" }
  | { t: "ref"; key: string }
  | { t: "chips"; options: string[] }
  | { t: "title"; text: string };

/**
 * Turns the model's streamed text into events without waiting for the end:
 * a line of only dashes becomes a bubble break, [[meet:<id>]] a card ref,
 * [[chips: a | b]] the follow-ups and [[title: …]] a new chat's name. Text is
 * held back only while it could still be one of those (a line start of "-",
 * or an open "[[").
 */
class Shaper {
  private buf = "";
  private lineStart = true;
  constructor(private readonly kinds: RegExp) {}

  push(s: string): Ev[] {
    this.buf += s;
    return this.drain(false);
  }

  /** Flushes everything held back; the next text starts a fresh line. */
  end(): Ev[] {
    const out = this.drain(true);
    this.lineStart = true;
    return out;
  }

  private drain(final: boolean): Ev[] {
    const out: Ev[] = [];
    const text = (s: string) => {
      if (!s) return;
      const last = out[out.length - 1];
      if (last?.t === "delta") last.text += s;
      else out.push({ t: "delta", text: s });
    };
    while (this.buf.length) {
      if (this.lineStart) {
        const nl = this.buf.indexOf("\n");
        const line = nl < 0 ? this.buf : this.buf.slice(0, nl);
        if (/^[ \t]*-{3,}[ \t]*$/.test(line) || /^[ \t]*[*_]{3,}[ \t]*$/.test(line)) {
          if (nl < 0 && !final) break; // "---" might still grow; wait for the newline
          out.push({ t: "break" });
          this.buf = nl < 0 ? "" : this.buf.slice(nl + 1);
          continue;
        }
        if (nl < 0 && !final && /^[ \t]*[-*_]{0,2}$/.test(line)) break; // could still become "---"
      }
      const open = this.buf.indexOf("[[");
      if (open === 0) {
        const close = this.buf.indexOf("]]");
        if (close < 0) {
          if (!final && this.buf.length < 300) break; // wait for the rest of the ref
          text(this.buf);
          this.buf = "";
          this.lineStart = false;
          break;
        }
        const inner = this.buf.slice(2, close).trim();
        this.buf = this.buf.slice(close + 2);
        const chips = /^chips\s*:(.*)$/is.exec(inner);
        const title = /^title\s*:(.*)$/is.exec(inner);
        const ref = new RegExp(`^(${this.kinds.source})\\s*:\\s*([0-9a-f-]{36})$`, "i").exec(inner);
        if (chips) {
          const options = chips[1].split("|").map((o) => o.trim().replace(/^["']|["']$/g, "")).filter((o) => o && o.length <= 60).slice(0, 3);
          if (options.length) out.push({ t: "chips", options });
        } else if (title) {
          const t = title[1].replace(/["'*]/g, "").replace(/\s+/g, " ").trim();
          if (t) out.push({ t: "title", text: short(t, 48) });
        } else if (ref) {
          out.push({ t: "ref", key: `${ref[1].toLowerCase()}:${ref[2].toLowerCase()}` });
        }
        // Anything else in [[ ]] is dropped.
        continue;
      }
      // Plain text up to the next newline or "[[", whichever comes first.
      const nl = this.buf.indexOf("\n");
      let end = this.buf.length;
      if (open > 0) end = Math.min(end, open);
      if (nl >= 0) end = Math.min(end, nl + 1);
      let chunk = this.buf.slice(0, end);
      // A lone "[" at the very end might be the start of "[[".
      if (end === this.buf.length && open < 0 && !final && chunk.endsWith("[")) chunk = chunk.slice(0, -1);
      if (!chunk) break;
      text(chunk);
      this.buf = this.buf.slice(chunk.length);
      this.lineStart = chunk.endsWith("\n");
    }
    return out;
  }
}

// ======================================================= the model stream ===

type RoundResult = { items: any[]; usage: any; incomplete: boolean };

async function* sse(body: ReadableStream<Uint8Array>): AsyncGenerator<any> {
  const reader = body.pipeThrough(new TextDecoderStream()).getReader();
  let buf = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += value;
    let i: number;
    while ((i = buf.indexOf("\n\n")) >= 0) {
      const block = buf.slice(0, i);
      buf = buf.slice(i + 2);
      const data = block.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trimStart()).join("\n");
      if (!data || data === "[DONE]") continue;
      try {
        yield JSON.parse(data);
      } catch {
        /* skip a malformed block */
      }
    }
  }
}

async function callModel(input: any[], instructions: string, tools: unknown[], finalRound: boolean, signal: AbortSignal, onText: (s: string) => Promise<void>): Promise<RoundResult> {
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    signal,
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      instructions,
      input,
      tools,
      tool_choice: finalRound ? "none" : "auto",
      reasoning: { effort: "none" },
      max_output_tokens: MAX_OUTPUT,
      stream: true,
      store: false,
      include: ["reasoning.encrypted_content"],
    }),
  });
  if (!res.ok || !res.body) throw new Error(`openai ${res.status}: ${(await res.text()).slice(0, 300)}`);
  const items: any[] = [];
  let usage: any = null;
  let incomplete = false;
  for await (const ev of sse(res.body)) {
    switch (ev.type) {
      case "response.output_text.delta":
        if (ev.delta) await onText(ev.delta);
        break;
      case "response.output_item.done":
        if (ev.item) items.push(ev.item);
        break;
      case "response.completed":
        usage = ev.response?.usage ?? null;
        break;
      case "response.incomplete":
        usage = ev.response?.usage ?? null;
        incomplete = true;
        break;
      case "response.failed":
        throw new Error(`openai failed: ${JSON.stringify(ev.response?.error ?? {}).slice(0, 300)}`);
      case "error":
        throw new Error(`openai error: ${JSON.stringify(ev).slice(0, 300)}`);
    }
  }
  return { items, usage, incomplete };
}

// ============================================================ the handler ===

const LIMIT_TEXT = (n: number) =>
  `That's ${n} questions today, and this cone needs a rest. Ask me again tomorrow!`;
const ERROR_TEXT = "My radio cut out. Try again?";

// Photos that need fine print read get "high" detail; the rest "low" (cheap).
const DETAIL_WORDS = /\b(read|text|says?|written|number|code|label|dot|date|tread|wear|worn|crack|scratch|dent|rust|leak|receipt|invoice|price tag|sticker|serial|gauge|odometer|mileage|spec)/i;

const imagesOf = (r: any): string[] => (r?.role === "user" && Array.isArray(r?.parts?.images) ? r.parts.images.filter((p: unknown) => typeof p === "string") : []);

/**
 * History rows → model input. Cards and action cards in an old answer become
 * a short note so TiTi remembers what it showed and what the member did. The
 * newest few photos go back in (the model needs them for follow-ups); older
 * ones become "(sent a photo)".
 */
function historyInput(list: any[], urls: Map<string, string>): any[] {
  return list.map((r) => {
    if (r.role === "user") {
      const imgs = imagesOf(r);
      const text = String(r.content ?? "");
      if (!imgs.length) return { role: "user", content: text };
      const shown = imgs.map((p) => urls.get(p)).filter((u): u is string => !!u);
      const note = shown.length < imgs.length ? ` (sent ${imgs.length} photo${imgs.length === 1 ? "" : "s"})` : "";
      return {
        role: "user",
        content: [{ type: "input_text", text: (text || "(photo)") + note }, ...shown.map((u) => ({ type: "input_image", image_url: u, detail: "low" }))],
      };
    }
    let text = String(r.content ?? "").replace(/\n?\[\[act:[0-9a-f-]{36}\]\]\n?/g, "\n");
    const cards = r.parts?.cards && typeof r.parts.cards === "object" ? Object.entries(r.parts.cards as Record<string, Card>) : [];
    if (cards.length) text += `\n\n(Cards shown: ${cards.map(([k, c]) => `[[${k}]] ${c.title}`).join("; ")})`;
    const acts = r.parts?.actions && typeof r.parts.actions === "object" ? Object.values(r.parts.actions as Record<string, Action>) : [];
    if (acts.length) {
      const state = (a: Action) => (a.status === "done" ? "the member did it" : a.status === "dismissed" ? "the member said not now" : "not tapped");
      text += `\n\n(Action cards: ${acts.map((a) => `${a.label} "${a.title}" (${state(a)})`).join("; ")})`;
    }
    return { role: "assistant", content: text };
  });
}

function contextNote(name: string | null, here: Point | null, newChat: boolean, headsUp: string[]): string {
  const now = new Date();
  const day = new Intl.DateTimeFormat("en-GB", { timeZone: MYT, weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(now);
  const time = new Intl.DateTimeFormat("en-GB", { timeZone: MYT, hour: "numeric", minute: "2-digit", hour12: true }).format(now);
  const iso = new Date(now.getTime() + 8 * 3600e3).toISOString().slice(0, 19) + "+08:00";
  let s = `\n\n# Right now\n- Malaysia time: ${day}, ${time} (${iso}).\n- Member: ${name ?? "unknown name"}.\n- Their location: ${here ? `known (${here.lat.toFixed(3)}, ${here.lng.toFixed(3)}); pass near "me" to use it` : "unknown"}.`;
  if (headsUp.length) s += `\n\n# Heads-up (from their account; mention the most useful one briefly if it fits, once)\n${headsUp.map((h) => `- ${h}`).join("\n")}`;
  if (newChat) s += `\n\n# New chat\nThis is the first question of a new chat. After the chips line, add one more line: [[title: a 2-5 word title for this chat, in the same language as their question]].`;
  return s;
}

/** A chat's fallback title: the question, trimmed. */
function titleFrom(q: string): string | null {
  const t = q.replace(/\s+/g, " ").trim();
  if (!t) return null;
  return t.length > 40 ? t.slice(0, 39).trimEnd() + "…" : t;
}

const historyQuery = (db: SupabaseClient, sessionId: string) =>
  db.from("titi_messages").select("role, content, parts, created_at").eq("session_id", sessionId).order("created_at", { ascending: false }).limit(HISTORY);

const within = <T>(p: Promise<T>, ms: number, fallback: T) => Promise.race([p, new Promise<T>((r) => setTimeout(() => r(fallback), ms))]);

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const t0 = Date.now();

  let body: any = {};
  try {
    body = await req.json();
  } catch {
    /* empty */
  }
  const v2 = Number(body.v) >= 2;
  const message = typeof body.message === "string" ? body.message.trim().slice(0, MAX_MESSAGE) : "";
  const rawImages: string[] = v2 && Array.isArray(body.images) ? body.images.filter((p: unknown) => typeof p === "string").slice(0, MAX_IMAGES) : [];
  if (!message && !rawImages.length) return json({ error: "message required" }, 400);
  const sessionIn = v2 && typeof body.session_id === "string" && UUID.test(body.session_id) ? body.session_id.toLowerCase() : null;
  const wantNew = v2 && !sessionIn && body.new_session === true;
  const lat = num(body.lat), lng = num(body.lng);
  const here: Point | null = lat != null && lng != null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? { lat, lng, label: "your location" } : null;

  const auth = req.headers.get("Authorization") ?? "";
  const asUser = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  // Who, which chat and its recent messages, all at once (all RLS-scoped).
  const [who, sess, hist] = await Promise.all([
    asUser.auth.getUser(),
    sessionIn
      ? asUser.from("titi_sessions").select("id, title").eq("id", sessionIn).maybeSingle()
      : wantNew
      ? Promise.resolve({ data: null })
      : asUser.from("titi_sessions").select("id, title").order("updated_at", { ascending: false }).limit(1).maybeSingle(),
    sessionIn ? historyQuery(asUser, sessionIn) : Promise.resolve({ data: null }),
  ]);
  const user = who.data.user;
  if (who.error || !user) return json({ error: "Not signed in" }, 401);
  if (!OPENAI_KEY) return json({ error: "TiTi is not set up yet" }, 503);

  // The chat: the one asked for, else (old app) the latest; none = a new one.
  const session = (sess.data as { id: string; title: string | null } | null) ?? null;
  let histRows = (hist.data as any[] | null) ?? [];
  if (session && !sessionIn) histRows = ((await historyQuery(asUser, session.id)).data as any[] | null) ?? [];
  if (!session) histRows = [];

  // Photos must sit in the member's own folder.
  const images = rawImages.filter((p) => p.startsWith(`${user.id}/`) && /^[A-Za-z0-9_.-]{1,80}$/.test(p.slice(user.id.length + 1)) && !p.includes(".."));
  if (!message && !images.length) return json({ error: "message required" }, 400);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const profileP = asUser.from("profiles").select("display_name, username").eq("id", user.id).maybeSingle();

  const history = histRows.reverse();
  // A Retry sends the same question again: don't store or send it twice.
  const last = history[history.length - 1];
  const isRetry = last?.role === "user" && String(last.content).trim() === message && imagesOf(last).join("|") === images.join("|");
  if (isRetry) history.pop();

  const abort = new AbortController();
  const enc = new TextEncoder();
  let closed = false;

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const send = (ev: Record<string, unknown>) => {
        if (closed) return;
        try {
          controller.enqueue(enc.encode(`data: ${JSON.stringify(ev)}\n\n`));
        } catch {
          closed = true;
        }
      };
      const finish = (extra: Record<string, unknown> = {}) => {
        send({ t: "done", ...extra });
        if (!closed) {
          closed = true;
          try {
            controller.close();
          } catch {
            /* already closed */
          }
        }
      };

      const work = (async () => {
        const turn = new Turn(asUser, user.id, here);
        const newChat = !session;
        const needTitle = !session?.title;

        // The photos the model sees: this question's, and the newest few earlier ones.
        const earlier: string[] = [];
        for (let i = history.length - 1; i >= 0 && earlier.length < MAX_IMAGES; i--) {
          for (const p of imagesOf(history[i])) if (earlier.length < MAX_IMAGES && !earlier.includes(p)) earlier.push(p);
        }
        const toSign = [...new Set([...images, ...earlier])];

        // Everything before the model call, at once: the daily limit, the
        // member's name, a new chat's row, signed photo URLs and (first
        // question of a chat) the heads-up.
        const [count, profile, sessionId, urls, heads] = await Promise.all([
          admin.rpc("titi_take_turn", { p_user: user.id, p_limit: DAILY_LIMIT }).then(({ data, error }) => {
            if (error) console.error("titi take_turn", error.message);
            return data as number | null;
          }),
          profileP.then((r) => r.data as any),
          newChat
            ? asUser.from("titi_sessions").insert({ user_id: user.id }).select("id").single().then(({ data, error }) => {
              if (error || !data) throw new Error(`new chat: ${error?.message}`);
              return (data as any).id as string;
            })
            : Promise.resolve(session!.id),
          toSign.length
            ? asUser.storage.from(BUCKET).createSignedUrls(toSign, 900).then(({ data, error }) => {
              if (error) console.error("titi sign", error.message);
              return new Map<string, string>((data ?? []).filter((d: any) => d.signedUrl && !d.error && d.path).map((d: any) => [d.path as string, d.signedUrl as string]));
            })
            : Promise.resolve(new Map<string, string>()),
          v2 && history.length === 0 ? within(turn.headsUp().catch(() => [] as string[]), 700, [] as string[]) : Promise.resolve([] as string[]),
        ]);

        if (count === -1) {
          // Over today's limit: nothing is stored, and a chat made just now goes again.
          if (newChat) await asUser.from("titi_sessions").delete().eq("id", sessionId);
          send({ t: "delta", text: LIMIT_TEXT(DAILY_LIMIT) });
          finish();
          return;
        }
        if (newChat && v2) send({ t: "session", id: sessionId });

        const savedQuestion = isRetry ? Promise.resolve() : asUser.from("titi_messages").insert({
          user_id: user.id,
          session_id: sessionId,
          role: "user",
          content: message,
          parts: images.length ? { images } : null,
        }).then(({ error }) => {
          if (error) console.error("titi save question", error.message);
        });

        const first = (profile?.display_name ?? "").trim().split(/\s+/)[0] || profile?.username || null;
        const instructions = (v2 ? INSTRUCTIONS : INSTRUCTIONS_V1) + contextNote(first, here, v2 && needTitle, heads);
        const tools = v2 ? V2_TOOLS : V1_TOOLS;
        const shaper = new Shaper(v2 ? /meet|spot|club|car|voucher|offer/ : /meet|spot|club|car/);

        // What gets stored: the answer exactly as shown.
        let stored = "";
        const shown = new Set<string>();
        const parts: { cards: Record<string, Card>; chips: string[]; actions: Record<string, Action> } = { cards: {}, chips: [], actions: {} };
        let modelTitle: string | null = null;
        let firstDeltaMs: number | null = null;
        const usage = { model: MODEL, v: v2 ? 2 : 1, rounds: 0, tools: [] as string[], images: images.length, input_tokens: 0, cached_tokens: 0, output_tokens: 0, reasoning_tokens: 0, ttft_ms: 0, ms: 0, incomplete: false, stopped: false, steps: [] as string[] };
        const mark = (what: string) => usage.steps.push(`${what} ${Date.now() - t0}`);
        mark("ready");

        // A break only goes out once something visible follows it, so there is
        // never an empty bubble at the start, the end, or two in a row.
        let visible = false;
        let pendingBreak = false;
        const flushBreak = () => {
          if (pendingBreak && visible) {
            stored += "\n---\n";
            send({ t: "break" });
          }
          pendingBreak = false;
        };
        const emit = async (evs: Ev[]) => {
          for (const ev of evs) {
            if (ev.t === "delta") {
              const solid = ev.text.trim().length > 0;
              if (!solid && (pendingBreak || !visible)) continue; // whitespace before a bubble
              if (solid) {
                if (firstDeltaMs == null) firstDeltaMs = Date.now() - t0;
                flushBreak();
                visible = true;
              }
              stored += ev.text;
              send(ev);
            } else if (ev.t === "break") {
              pendingBreak = true;
            } else if (ev.t === "ref") {
              if (shown.has(ev.key) || shown.size >= MAX_CARDS) continue;
              const card = await turn.card(ev.key);
              if (!card) continue;
              flushBreak();
              visible = true;
              shown.add(ev.key);
              parts.cards[ev.key] = card;
              stored += `\n[[${ev.key}]]\n`;
              send({ t: "card", ...card });
            } else if (ev.t === "chips") {
              parts.chips = ev.options;
            } else if (ev.t === "title") {
              modelTitle = ev.text;
            }
          }
        };
        const emitAction = (a: Action) => {
          if (Object.keys(parts.actions).length >= MAX_ACTIONS) return;
          flushBreak();
          visible = true;
          parts.actions[a.id] = a;
          stored += `\n[[act:${a.id}]]\n`;
          send({ t: "action", ...a });
        };

        // This question: text and photos.
        const shownNow = images.map((p) => urls.get(p)).filter((u): u is string => !!u);
        const detail = DETAIL_WORDS.test(message) ? "high" : "low";
        const question = shownNow.length
          ? { role: "user", content: [{ type: "input_text", text: message || "(What can you tell me from this photo?)" }, ...shownNow.map((u) => ({ type: "input_image", image_url: u, detail }))] }
          : { role: "user", content: message || "(I sent a photo, but it didn't load.)" };

        let failed = false;
        try {
          const input: any[] = [...historyInput(history, urls), question];
          for (let round = 0; ; round++) {
            usage.rounds = round + 1;
            mark(`model${round + 1}`);
            const r = await callModel(input, instructions, tools, round >= MAX_ROUNDS, abort.signal, (s) => emit(shaper.push(s)));
            mark(`model${round + 1} done`);
            const u = r.usage;
            if (u) {
              usage.input_tokens += u.input_tokens ?? 0;
              usage.cached_tokens += u.input_tokens_details?.cached_tokens ?? 0;
              usage.output_tokens += u.output_tokens ?? 0;
              usage.reasoning_tokens += u.output_tokens_details?.reasoning_tokens ?? 0;
            }
            if (r.incomplete) usage.incomplete = true;
            const calls = r.items.filter((i) => i.type === "function_call");
            if (!calls.length || round >= MAX_ROUNDS) break;
            // Text before a tool call ("Let me check…") stays its own bubble.
            await emit([...shaper.end(), { t: "break" }]);
            // Echo the round back (store: false keeps nothing at OpenAI): reasoning
            // items as they are, the rest without their ids.
            for (const it of r.items) {
              if (it.type === "reasoning") input.push(it);
              else {
                const { id: _id, status: _status, ...rest } = it;
                input.push(rest);
              }
            }
            const outputs = await Promise.all(calls.map(async (c) => {
              let args: any = {};
              try {
                args = c.arguments ? JSON.parse(c.arguments) : {};
              } catch {
                /* bad args: the tool sees {} */
              }
              usage.tools.push(`${c.name} ${JSON.stringify(args).slice(0, 200)}`);
              const known = tools.some((t: any) => t.name === c.name);
              send({ t: "status", text: ACTION_TOOLS.has(c.name) ? "Setting that up…" : (STATUS[c.name] ?? (() => "Checking…"))(args), tool: c.name });
              let out: unknown;
              try {
                out = known ? await turn.run(c.name, args) : { error: `unknown tool ${c.name}` };
              } catch (e) {
                console.error("titi tool", c.name, String(e).slice(0, 300));
                out = { error: "That check failed. Tell the member you couldn't check right now." };
              }
              return { type: "function_call_output", call_id: c.call_id, output: JSON.stringify(out) };
            }));
            // Action cards show up now, between the text before and after them.
            for (const a of turn.takeActions()) emitAction(a);
            input.push(...outputs);
            mark("tools done");
          }
          await emit(shaper.end());
        } catch (e) {
          if (abort.signal.aborted || closed) {
            usage.stopped = true;
          } else {
            failed = true;
            console.error("titi", String(e).slice(0, 400));
          }
        }

        usage.ttft_ms = firstDeltaMs ?? 0;
        usage.ms = Date.now() - t0;
        const answer = stored.trim();
        // Stopped mid-way: OpenAI never sends that round's usage. Log a rough
        // count (~4 characters a token) so the cost view isn't blind to it.
        if (usage.stopped && usage.output_tokens === 0 && answer) {
          usage.output_tokens = Math.ceil(answer.length / 4);
          (usage as Record<string, unknown>).estimated = true;
        }

        // A new chat is named after its first answer.
        const title = v2 && needTitle ? (modelTitle ?? titleFrom(message) ?? (images.length ? "Photo check" : null)) : null;
        const answerId = crypto.randomUUID();

        if (failed && !answer) {
          send({ t: "error", text: ERROR_TEXT });
        } else if (parts.chips.length) {
          send({ t: "chips", options: parts.chips });
        }
        finish({ id: answer ? answerId : undefined, title: title ?? undefined });

        // Bookkeeping after the stream is closed: the member isn't waiting on it.
        await savedQuestion;
        const writes: PromiseLike<unknown>[] = [
          admin.rpc("titi_log_usage", { p_user: user.id, p_input: usage.input_tokens, p_cached: usage.cached_tokens, p_output: usage.output_tokens }),
        ];
        if (answer) {
          const keep: Record<string, unknown> = {};
          if (Object.keys(parts.cards).length) keep.cards = parts.cards;
          if (parts.chips.length) keep.chips = parts.chips;
          if (Object.keys(parts.actions).length) keep.actions = parts.actions;
          writes.push(admin.from("titi_messages").insert({
            id: answerId,
            user_id: user.id,
            session_id: sessionId,
            role: "assistant",
            content: answer.slice(0, 12000),
            parts: Object.keys(keep).length ? keep : null,
            usage,
          }));
        }
        if (title) writes.push(asUser.from("titi_sessions").update({ title }).eq("id", sessionId));
        const results = await Promise.allSettled(writes);
        for (const r of results) {
          const err = r.status === "rejected" ? r.reason : (r.value as any)?.error;
          if (err) console.error("titi save", String(err?.message ?? err).slice(0, 300));
        }
        console.log(`titi ${user.id.slice(0, 8)} v${usage.v} rounds=${usage.rounds} tools=${usage.tools.map((t) => t.split(" ")[0]).join(",") || "-"} img=${images.length} ttft=${usage.ttft_ms}ms total=${usage.ms}ms in=${usage.input_tokens} cached=${usage.cached_tokens} out=${usage.output_tokens}${usage.stopped ? " stopped" : ""}`);
      })().catch((e) => {
        console.error("titi fatal", String(e).slice(0, 400));
        send({ t: "error", text: ERROR_TEXT });
        finish();
      });

      // Keep saving the answer even after the member closes the stream (Stop).
      (globalThis as any).EdgeRuntime?.waitUntil?.(work);
    },
    cancel() {
      closed = true;
      abort.abort();
    },
  });

  return new Response(stream, {
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache",
      "x-accel-buffering": "no",
    },
  });
});
