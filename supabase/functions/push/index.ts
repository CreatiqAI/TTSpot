// Sends a push for a new notification row or chat message (called by the
// push_hook trigger through pg_net). Body: { table: 'notifications'|'messages', id }.
// Secrets: PUSH_HOOK_SECRET (same value as the Vault secret) and
// FCM_SERVICE_ACCOUNT (Firebase → Project settings → Service accounts → JSON).
// Without FCM_SERVICE_ACCOUNT it answers { skipped } and sends nothing.
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const HOOK_SECRET = Deno.env.get("PUSH_HOOK_SECRET") ?? "";
const SA_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

type Push = { userIds: string[]; title: string; body: string; route: string | null; setting: string | null };

// ------------------------------------------------------------- FCM auth ---

let cached: { token: string; until: number } | null = null;

async function fcmToken(sa: { client_email: string; private_key: string }): Promise<string> {
  if (cached && cached.until > Date.now()) return cached.token;
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  const t = await r.json();
  if (!t.access_token) throw new Error(`FCM auth failed: ${JSON.stringify(t)}`);
  cached = { token: t.access_token, until: Date.now() + 50 * 60 * 1000 };
  return cached.token;
}

// ------------------------------------------------------------- building ---

// Settings toggle (profiles.settings) that silences each notification type.
const SETTING: Record<string, string> = {
  event_join: "notif_meets", event_comment: "notif_meets", event_reminder: "notif_meets", event_cancelled: "notif_meets",
  checkin: "notif_meets", club_event: "notif_meets", partner_event: "notif_meets",
  follow: "notif_friends", friend_request: "notif_friends", friend_accepted: "notif_friends", club_invite: "notif_friends",
  club_join: "notif_friends", club_request: "notif_friends", post_like: "notif_friends", post_comment: "notif_friends",
  tt_now: "notif_tt", garage: "notif_tt",
  points: "notif_rewards", referral: "notif_rewards", badge: "notif_rewards", voucher: "notif_rewards",
  spotted_claim: "notif_rewards", car_of_week: "notif_rewards",
};

const after = (s: string | null, prefix: string) => (s ?? "").startsWith(prefix) ? s!.slice(prefix.length) : s ?? "";

async function fromNotification(id: string): Promise<Push | null> {
  const { data: n } = await admin
    .from("notifications")
    .select("user_id, type, body, post_id, event_id, club_id, actor:profiles!notifications_actor_id_fkey(username), event:events(title), club:clubs(name)")
    .eq("id", id)
    .maybeSingle();
  if (!n) return null;
  // deno-lint-ignore no-explicit-any
  const x = n as any;
  const who = x.actor?.username ? `@${x.actor.username}` : "";
  const ev = x.event?.title ?? "your meet";
  const club = x.club?.name ?? "your club";
  const b: string | null = x.body;
  const ev_ = x.event_id ? `/event/${x.event_id}` : null;
  const post_ = x.post_id ? `/post/${x.post_id}` : null;
  const club_ = x.club_id ? `/club/${x.club_id}` : null;

  const [title, body, route]: [string, string, string | null] = (() => {
    switch (x.type) {
      case "follow": return [who, "started following you.", null];
      case "post_like": return [who, "liked your post.", post_];
      case "post_comment": return [who, `commented: ${b ?? ""}`, post_];
      case "event_join": return [who, `joined ${ev}.`, ev_];
      case "event_comment": return [ev, `${who}: ${b ?? ""}`, ev_];
      case "event_reminder": return [ev, "is within 24 hours. See you there!", ev_];
      case "event_cancelled": return [ev, `${who || "The host"} cancelled it.`, ev_];
      case "checkin": return [ev, `${who} just checked in.`, ev_];
      case "friend_request": return [who, "wants to be friends.", "/friends"];
      case "friend_accepted": return [who, "accepted your friend request.", null];
      case "tt_now": return [who, `started TT now${b ? ` @ ${b}` : ""}. Otw?`, ev_];
      case "garage": return [club, `${who} just pulled up at ${b ?? "the garage"}.`, club_];
      case "club_invite": return [club, `${who} invited you to join. Open the club to accept.`, club_];
      case "club_join": return [club, `${who} joined.`, club_];
      case "club_request":
        return b === "approved" ? [club, "You're in. Welcome!", club_]
          : b === "declined" ? [club, "Not this time.", club_]
          : [club, `${who} wants to join. Open the club to decide.`, club_];
      case "club_event": return [club, `New meet: ${ev}.`, ev_];
      case "partner_event": return [b ?? "A partner", `is hosting ${ev}.`, ev_];
      case "club_official": return [club, b?.startsWith("approved") ? "is now an official club." : "Club status changed.", club_];
      case "referral": return ["TT Spot", `${who} joined with your code. +${b ?? ""} points.`, "/me/points"];
      case "points": return ["TT Spot", b ?? "You earned points.", "/me/points"];
      case "badge": return ["TT Spot", "You earned a new badge.", null];
      case "voucher": return ["TT Spot", (b ?? "").startsWith("redeemed:") ? `Voucher used: ${after(b, "redeemed:")}` : b ?? "Voucher update.", "/rewards?tab=vouchers"];
      case "spotted_claim": return [who, "claimed the car you spotted.", post_];
      case "partner": return ["TT Spot", b ?? "Partner update.", null];
      default: return ["TT Spot", b ?? "Something new for you.", null];
    }
  })();
  return { userIds: [x.user_id], title: title || "TT Spot", body, route, setting: SETTING[x.type] ?? null };
}

async function fromMessage(id: string): Promise<Push | null> {
  const { data: m } = await admin
    .from("messages")
    .select("conversation_id, sender_id, body, as_club, as_vendor, sender:profiles!messages_sender_id_fkey(username), conversation:conversations(kind, event:events(title))")
    .eq("id", id)
    .maybeSingle();
  if (!m) return null;
  // deno-lint-ignore no-explicit-any
  const x = m as any;
  let from = x.sender?.username ? `@${x.sender.username}` : "Someone";
  if (x.as_club) from = (await admin.from("clubs").select("name").eq("id", x.as_club).maybeSingle()).data?.name ?? from;
  if (x.as_vendor) from = (await admin.from("vendors").select("name").eq("id", x.as_vendor).maybeSingle()).data?.name ?? from;

  const { data: members } = await admin
    .from("conversation_members")
    .select("user_id")
    .eq("conversation_id", x.conversation_id)
    .is("muted_at", null)
    .neq("user_id", x.sender_id);
  let userIds = (members ?? []).map((r: { user_id: string }) => r.user_id);
  if (!userIds.length) return null;
  // Nobody hears from someone they blocked.
  const { data: blocks } = await admin.from("blocks").select("blocker_id").eq("blocked_id", x.sender_id).in("blocker_id", userIds);
  const blockers = new Set((blocks ?? []).map((r: { blocker_id: string }) => r.blocker_id));
  userIds = userIds.filter((u) => !blockers.has(u));

  const meet = x.conversation?.kind === "meet";
  return {
    userIds,
    title: meet ? x.conversation?.event?.title ?? "Meet chat" : from,
    body: meet ? `${from}: ${x.body}` : x.body,
    route: `/chat/${x.conversation_id}`,
    setting: "notif_messages",
  };
}

// -------------------------------------------------------------- sending ---

Deno.serve(async (req) => {
  if (!HOOK_SECRET || req.headers.get("x-push-secret") !== HOOK_SECRET) return json({ error: "forbidden" }, 403);
  if (!SA_JSON) return json({ skipped: "FCM_SERVICE_ACCOUNT not set" });
  const { table, id } = await req.json().catch(() => ({}));
  const push = table === "notifications" ? await fromNotification(id) : table === "messages" ? await fromMessage(id) : null;
  if (!push || !push.userIds.length) return json({ sent: 0 });

  // Drop people who switched this kind off in Settings.
  let userIds = push.userIds;
  if (push.setting) {
    const { data: profs } = await admin.from("profiles").select("id, settings").in("id", userIds);
    // deno-lint-ignore no-explicit-any
    userIds = (profs ?? []).filter((p: any) => p.settings?.[push.setting!] !== false).map((p: { id: string }) => p.id);
  }
  if (!userIds.length) return json({ sent: 0 });
  const { data: tokens } = await admin.from("push_tokens").select("token").in("user_id", userIds);
  if (!tokens?.length) return json({ sent: 0 });

  const sa = JSON.parse(SA_JSON);
  const access = await fcmToken(sa);
  const body = push.body.length > 180 ? `${push.body.slice(0, 177)}…` : push.body;
  let sent = 0;
  const dead: string[] = [];
  await Promise.all(tokens.map(async ({ token }: { token: string }) => {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: push.title, body },
          data: push.route ? { route: push.route } : {},
          android: { priority: "HIGH", notification: { icon: "ic_stat_notify", color: "#E00008" } },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    });
    if (r.ok) sent++;
    else if (r.status === 404 || r.status === 400) {
      const err = await r.json().catch(() => ({}));
      const code = err?.error?.details?.[0]?.errorCode ?? err?.error?.status;
      if (code === "UNREGISTERED" || code === "INVALID_ARGUMENT" || r.status === 404) dead.push(token);
    }
  }));
  if (dead.length) await admin.from("push_tokens").delete().in("token", dead);
  return json({ sent, removed: dead.length });
});
