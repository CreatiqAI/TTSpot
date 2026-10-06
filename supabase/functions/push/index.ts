// Sends a push for a new notification row or chat message (called by the
// push_hook trigger through pg_net). Body: { table: 'notifications'|'messages', id }.
// Secrets: PUSH_HOOK_SECRET (same value as the Vault secret) and
// FCM_SERVICE_ACCOUNT (Firebase → Project settings → Service accounts → JSON).
// Without FCM_SERVICE_ACCOUNT it answers { skipped } and sends nothing.
//
// Deploy with --no-verify-jwt (pinned in supabase/config.toml): pg_net calls
// carry only x-push-secret, so a JWT check answers 401 to every push.
//
// Names: a person shows as their display name (their @handle only when they
// have none), or as the recipient's private nickname for them (备注,
// contact_nicknames). Clubs, partners and meets keep their own names.
//
// Payload per platform:
// - Android chat messages go DATA-ONLY so the app draws them itself as a
//   conversation with the sender's avatar (ChatPushService.kt / ChatNotifications.kt)
//   and never while the app is open (the in-app banner shows instead). Only
//   to installs that said they can (push_tokens.native_chat); older builds
//   would drop a data-only push, so they keep the standard notification.
// - Everything else carries a notification block (the system draws it in the
//   background); iOS gets mutable-content so a Notification Service Extension
//   can add the sender's avatar, and thread-id to group a chat.
// - data always has: route, kind, title, body, avatar, sender_id, msg_id
//   (+ conversation_id, sender_name, group, convo_title, text for chats).
//
// Group chats (20261005000100_group_chats.sql): a friends' group ('group')
// and a club's members chat ('club') go out like meet chats: title = the
// group's name (a club chat takes the club's; an unnamed group lists its
// people as the app does, by each recipient's nicknames), body = "Sender:
// text", group = "1". Muted members, the sender, people who blocked the
// sender and anyone with Messages switched off get nothing. data.text is the
// message alone, for the Android conversation (it names the sender itself).
//
// Social pings (friend_post, friend_tt, club_member, follow) are written by
// the triggers in 20261003000097_social_notifications.sql, which already
// apply blocks, suspensions, per-author / per-club limits and the daily cap;
// rows past those limits are silent and never reach this function. The same
// goes for mention, comment_reply, comment_like, club_post and club_meet
// (20261005000102_comments_mentions.sql). Comment kinds open the post
// scrolled to the comment: /post/<id>?comment=<comment id>.
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const HOOK_SECRET = Deno.env.get("PUSH_HOOK_SECRET") ?? "";
const SA_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/** Title / body for one recipient (their nickname for the sender may differ). */
type Text = { title: string; body: string };

type Push = {
  userIds: string[];
  text: (userId: string) => Text;
  /** Per-recipient data keys (their nickname for the sender, the group title they see). */
  dataFor?: (userId: string) => Record<string, string>;
  route: string | null;
  setting: string | null;
  chat: boolean;
  /** Extra data keys (strings) for the app: avatar, sender, conversation… */
  data: Record<string, string>;
  /** iOS thread-id: one chat or one kind groups together. */
  thread: string;
};

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

// ---------------------------------------------------------------- names ---

type Person = { username?: string | null; display_name?: string | null; avatar_url?: string | null } | null;

/** Display name, else @handle, else the fallback. */
function nameOf(p: Person, fallback = "Someone"): string {
  const d = p?.display_name?.trim();
  if (d) return d;
  const u = p?.username?.trim();
  return u ? `@${u}` : fallback;
}

/** The TiTi default avatar the app draws for this user id (UserAvatar's FNV-1a pick). */
function defaultAvatar(seed: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return `${SUPABASE_URL}/storage/v1/object/public/avatars/defaults/a${(h % 8) + 1}.png`;
}

function avatarOf(p: Person, userId: string | null): string {
  const url = p?.avatar_url?.trim();
  if (url) return url;
  return userId ? defaultAvatar(userId) : "";
}

/** A short name for a list of people: first word of the display name, else @handle. */
function shortName(p: Person): string {
  const d = p?.display_name?.trim();
  if (d) return d.split(/\s+/)[0];
  const u = p?.username?.trim();
  return u ? `@${u}` : "Member";
}

/** An unnamed group's title, like the app's groupAutoName(): "Aiman", "Aiman and Bala",
 * "Aiman, Bala and Chong", "Aiman, Bala, Chong and 4 more". */
function groupAutoName(names: string[]): string {
  const n = names.map((s) => s.trim()).filter(Boolean);
  if (!n.length) return "Group chat";
  if (n.length === 1) return n[0];
  if (n.length <= 3) return `${n.slice(0, -1).join(", ")} and ${n[n.length - 1]}`;
  return `${n.slice(0, 3).join(", ")} and ${n.length - 3} more`;
}

/** Titles for an unnamed friends' group: each recipient sees everyone else in
 * it, in join order, by their own nicknames for them. */
async function groupTitles(conversationId: string, recipients: string[]): Promise<(userId: string) => string> {
  const { data } = await admin
    .from("conversation_members")
    .select("user_id, created_at, profile:profiles(username, display_name)")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true });
  // deno-lint-ignore no-explicit-any
  const people = ((data ?? []) as any[]).map((r) => ({ id: r.user_id as string, profile: r.profile as Person }));
  const ids = people.map((p) => p.id);
  const nick = new Map<string, string>();
  if (ids.length && recipients.length) {
    const { data: rows } = await admin.from("contact_nicknames").select("owner_id, target_id, nickname").in("owner_id", recipients).in("target_id", ids);
    for (const r of (rows ?? []) as { owner_id: string; target_id: string; nickname: string }[]) {
      if (r.nickname?.trim()) nick.set(`${r.owner_id}:${r.target_id}`, r.nickname.trim());
    }
  }
  return (u) => groupAutoName(people.filter((p) => p.id !== u).map((p) => nick.get(`${u}:${p.id}`) ?? shortName(p.profile)));
}

/** Each recipient's nickname for [targetId], if they set one. */
async function nicknames(targetId: string | null, ownerIds: string[]): Promise<Map<string, string>> {
  if (!targetId || !ownerIds.length) return new Map();
  const { data } = await admin.from("contact_nicknames").select("owner_id, nickname").eq("target_id", targetId).in("owner_id", ownerIds);
  return new Map((data ?? []).filter((r: { nickname: string }) => r.nickname?.trim()).map((r: { owner_id: string; nickname: string }) => [r.owner_id, r.nickname.trim()]));
}

// ------------------------------------------------------------- building ---

// Settings toggle (profiles.settings) that silences each notification type.
const SETTING: Record<string, string> = {
  event_join: "notif_meets", event_comment: "notif_meets", event_reminder: "notif_meets", event_cancelled: "notif_meets",
  checkin: "notif_meets", club_event: "notif_meets", partner_event: "notif_meets", meet_start: "notif_meets",
  announcement: "notif_meets", lucky_draw: "notif_meets",
  friend_request: "notif_friends", friend_accepted: "notif_friends", club_invite: "notif_friends",
  club_join: "notif_friends", club_request: "notif_friends", post_like: "notif_friends", post_comment: "notif_friends",
  tt_now: "notif_tt", garage: "notif_tt",
  // Social pings (20261003000097): the database already marks rows for a
  // switched-off kind silent (no push call); this covers a switch flipped since.
  follow: "notif_followers", friend_post: "notif_friend_posts", friend_tt: "notif_friend_tt", club_member: "notif_club_members",
  // 20261005000102: comments and clubs you follow.
  mention: "notif_mentions", comment_reply: "notif_replies", comment_like: "notif_replies",
  club_post: "notif_club_follows", club_meet: "notif_club_follows",
  // 20261007000114: TiTi's own daily line (the "TiTi tips" switch).
  titi_nudge: "titi_tips",
  points: "notif_rewards", referral: "notif_rewards", badge: "notif_rewards", voucher: "notif_rewards",
  spotted_claim: "notif_rewards", car_of_week: "notif_rewards", cards: "notif_rewards", portrait: "notif_rewards",
};

const after = (s: string | null, prefix: string) => (s ?? "").startsWith(prefix) ? s!.slice(prefix.length) : s ?? "";

/** friend_post body "<what>:<first 60 characters>" → "posted: …" / "posted a new photo." */
function friendPostText(b: string | null): string {
  const s = b ?? "";
  const i = s.indexOf(":");
  const what = i < 0 ? "photo" : s.slice(0, i);
  const text = (i < 0 ? s : s.slice(i + 1)).trim();
  if (text) return what === "spotted" ? `spotted a car: ${text}` : `posted: ${text}`;
  switch (what) {
    case "video": return "posted a new video.";
    case "poll": return "posted a new poll.";
    case "guide": return "shared a new guide.";
    case "spotted": return "spotted a car.";
    default: return "posted a new photo.";
  }
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** When a session starts, in Malaysian time (UTC+8, no daylight saving), as
 * the app writes it: "today 9:30 PM", "tomorrow 8:00 PM", "Sat 9:30 PM"
 * within the week, else "11 Oct 9:30 PM". */
function whenMyt(iso: string, now = new Date()): string {
  const myt = (d: Date) => new Date(d.getTime() + 8 * 3600 * 1000);
  const t = myt(new Date(iso));
  const n = myt(now);
  const dayNo = (d: Date) => Math.floor(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) / 86400000);
  const days = dayNo(t) - dayNo(n);
  const h = t.getUTCHours();
  const time = `${h % 12 === 0 ? 12 : h % 12}:${String(t.getUTCMinutes()).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
  if (days === 0) return `today ${time}`;
  if (days === 1) return `tomorrow ${time}`;
  if (days > 1 && days < 7) return `${WEEKDAYS[t.getUTCDay()]} ${time}`;
  return `${t.getUTCDate()} ${MONTHS[t.getUTCMonth()]} ${time}`;
}

async function fromNotification(id: string): Promise<Push | null> {
  const { data: n } = await admin
    .from("notifications")
    .select("user_id, actor_id, type, body, post_id, event_id, club_id, comment_id, actor:profiles!notifications_actor_id_fkey(username, display_name, avatar_url), event:events(title, venue_name, starts_at, is_instant), club:clubs(name, avatar_url)")
    .eq("id", id)
    .maybeSingle();
  if (!n) return null;
  // deno-lint-ignore no-explicit-any
  const x = n as any;
  const nick = (await nicknames(x.actor_id, [x.user_id])).get(x.user_id);
  const who = x.actor_id ? (nick ?? nameOf(x.actor, "")) : "";
  const ev = x.event?.title ?? "your meet";
  const club = x.club?.name ?? "your club";
  const b: string | null = x.body;
  const ev_ = x.event_id ? `/event/${x.event_id}` : null;
  const post_ = x.post_id ? `/post/${x.post_id}` : null;
  // The post, scrolled to the comment the ping is about.
  const comment_ = x.post_id ? (x.comment_id ? `/post/${x.post_id}?comment=${x.comment_id}` : post_) : null;
  const club_ = x.club_id ? `/club/${x.club_id}` : null;

  const [title, body, route]: [string, string, string | null] = (() => {
    switch (x.type) {
      case "follow": return [who, "started following you.", x.actor_id ? `/profile/${x.actor_id}` : null];
      case "friend_post": return [who, friendPostText(b), post_];
      case "friend_tt": {
        const place = x.event?.venue_name ?? b ?? "a spot";
        return x.event?.is_instant || !x.event?.starts_at
          ? [who, `is at ${place} for a TT now.`, ev_]
          : [who, `planned a TT at ${place}, ${whenMyt(x.event.starts_at)}.`, ev_];
      }
      case "club_member": return [who, `joined ${club}.`, club_];
      case "post_like": return [who, "liked your post.", post_];
      case "post_comment": return [who, `commented: ${b ?? ""}`, comment_];
      case "mention": return [who, x.comment_id ? `mentioned you in a comment: ${b ?? ""}` : `mentioned you in a post: ${b ?? ""}`, comment_];
      case "comment_reply": return [who, `replied to your comment: ${b ?? ""}`, comment_];
      case "comment_like": return [who, `liked your comment: ${b ?? ""}`, comment_];
      // The club speaks: its name is the title, its logo the face.
      case "club_post": return [club, friendPostText(b), post_];
      case "club_meet":
        return [club, x.event?.starts_at ? `planned ${x.event?.title ?? b ?? "a meet"}, ${whenMyt(x.event.starts_at)}.` : `planned ${x.event?.title ?? b ?? "a meet"}.`, ev_];
      case "event_join": return [who, `joined ${ev}.`, ev_];
      case "event_comment": return [ev, `${who}: ${b ?? ""}`, ev_];
      case "event_reminder": return [ev, "is within 24 hours. See you there!", ev_];
      case "event_cancelled": return [ev, `${who || "The host"} cancelled it.`, ev_];
      case "checkin": return [ev, `${who} just checked in.`, ev_];
      case "meet_start": return [ev, "is on. Open TT Spot when you arrive to check in.", ev_];
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
      case "cards":
        return (b ?? "").startsWith("trade:") ? [who, "sent you a card trade offer.", "/cards?tab=trades"]
          : (b ?? "").startsWith("accepted:") ? [who, "accepted your trade. The cards are in your collection.", "/cards"]
          : (b ?? "").startsWith("declined:") ? [who, "passed on your trade offer.", "/cards?tab=trades"]
          : (b ?? "").startsWith("redeemed:") ? ["TT Spot", `Prize handed over: ${after(b, "redeemed:")}`, "/cards?tab=prizes"]
          : ["TT Spot", b ?? "Something new in Cards.", "/cards"];
      case "portrait": return ["TT Spot", "Your car portrait is ready. Tap to see it.", "/me"];
      // body = "<title>\n<message>" from the host / co-host.
      case "announcement": {
        const [head, ...rest] = (b ?? "").split("\n");
        return [ev, rest.length ? `${head}: ${rest.join(" ")}` : head, ev_];
      }
      case "lucky_draw": return [ev, b ?? "Lucky draw update.", ev_];
      // TiTi speaks (titi-nudge): his line is the body; it opens his chat.
      case "titi_nudge": return ["TiTi", b ?? "", "/titi"];      default: return ["TT Spot", b ?? "Something new for you.", null];
    }
  })();
  // The face on the banner: the person when the title is them, else the club, else the person.
  const personTitled = !!who && title === who;
  // TiTi's face: one of his default-avatar poses.
  const avatar = x.type === "titi_nudge" ? `${SUPABASE_URL}/storage/v1/object/public/avatars/defaults/a1.png`
    : personTitled || !x.club_id ? avatarOf(x.actor, x.actor_id) : (x.club?.avatar_url ?? avatarOf(x.actor, x.actor_id));
  const text = { title: title || "TT Spot", body };
  return {
    userIds: [x.user_id],
    text: () => text,
    route,
    setting: SETTING[x.type] ?? null,
    chat: false,
    data: { kind: x.type ?? "notice", avatar: avatar ?? "", sender_id: x.actor_id ?? "", msg_id: `n:${id}` },
    thread: x.type ?? "notice",
  };
}

async function fromMessage(id: string): Promise<Push | null> {
  const { data: m } = await admin
    .from("messages")
    .select("conversation_id, sender_id, body, image_url, video_url, as_club, as_vendor, sender:profiles!messages_sender_id_fkey(username, display_name, avatar_url), conversation:conversations(kind, title, event:events(title), club:clubs!conversations_club_id_fkey(name))")
    .eq("id", id)
    .maybeSingle();
  if (!m) return null;
  // deno-lint-ignore no-explicit-any
  const x = m as any;

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
  if (!userIds.length) return null;

  // Who it's from: the club / partner when sent as one, else the person
  // (by the recipient's nickname for them when there is one).
  let entity: string | null = null;
  let avatar = avatarOf(x.sender, x.sender_id);
  if (x.as_club) {
    const c = (await admin.from("clubs").select("name, avatar_url").eq("id", x.as_club).maybeSingle()).data;
    if (c?.name) entity = c.name;
    avatar = c?.avatar_url ?? "";
  } else if (x.as_vendor) {
    const v = (await admin.from("vendors").select("name, logo_url").eq("id", x.as_vendor).maybeSingle()).data;
    if (v?.name) entity = v.name;
    avatar = v?.logo_url ?? "";
  }
  const name = entity ?? nameOf(x.sender);
  const nicks = entity ? new Map<string, string>() : await nicknames(x.sender_id, userIds);
  const from = (u: string) => nicks.get(u) ?? name;

  const kind: string = x.conversation?.kind ?? "dm";
  // Meet, club and friends' group chats all go out as group conversations.
  const meet = kind === "meet" || kind === "group" || kind === "club";
  const ownTitle: string = (x.conversation?.title ?? "").trim();
  const fixedTitle: string = kind === "meet"
    ? x.conversation?.event?.title ?? "Meet chat"
    : kind === "club"
      ? x.conversation?.club?.name ?? "Club chat"
      : ownTitle;
  const titleFor = kind === "group" && !ownTitle ? await groupTitles(x.conversation_id, userIds) : () => fixedTitle;
  // A caption typed under a photo / video says which it was; the auto bodies
  // ("Sent a photo", "Sent a video") already do.
  const text: string = x.image_url && x.body !== "Sent a photo"
    ? `Photo: ${x.body}`
    : x.video_url && x.body !== "Sent a video"
      ? `Video: ${x.body}`
      : x.body;
  return {
    userIds,
    text: (u) => meet ? { title: titleFor(u), body: `${from(u)}: ${text}` } : { title: from(u), body: text },
    dataFor: (u): Record<string, string> => meet ? { sender_name: from(u), convo_title: titleFor(u) } : {},
    route: `/chat/${x.conversation_id}`,
    setting: "notif_messages",
    chat: true,
    data: {
      kind: "chat",
      conversation_id: x.conversation_id,
      sender_id: x.sender_id ?? "",
      sender_name: name,
      avatar: avatar ?? "",
      group: meet ? "1" : "0",
      convo_title: meet ? fixedTitle : "",
      text: clip(text, 180),
      msg_id: `m:${id}`,
    },
    thread: `chat:${x.conversation_id}`,
  };
}

// -------------------------------------------------------------- sending ---

const clip = (s: string, n: number) => s.length > n ? `${s.slice(0, n - 1)}…` : s;

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
  const { data: tokens } = await admin.from("push_tokens").select("token, user_id, platform, native_chat").in("user_id", userIds);
  if (!tokens?.length) return json({ sent: 0 });

  const sa = JSON.parse(SA_JSON);
  const access = await fcmToken(sa);
  let sent = 0;
  const dead: string[] = [];
  await Promise.all(tokens.map(async ({ token, user_id, platform, native_chat }: { token: string; user_id: string; platform: string; native_chat: boolean }) => {
    const t = push.text(user_id);
    const title = clip(t.title || "TT Spot", 80);
    const body = clip(t.body ?? "", 180);
    const data: Record<string, string> = { ...push.data, ...(push.dataFor?.(user_id) ?? {}), title, body };
    if (push.route) data.route = push.route;
    // deno-lint-ignore no-explicit-any
    const message: Record<string, any> = { token, data };
    if (platform === "android" && push.chat && native_chat) {
      // Data-only: the app draws the conversation itself (or the in-app banner).
      message.android = { priority: "HIGH" };
    } else {
      message.notification = { title, body };
      message.android = { priority: "HIGH", notification: { icon: "ic_stat_notify", color: "#E00008" } };
      message.apns = { payload: { aps: { sound: "default", "mutable-content": 1, "thread-id": push.thread } } };
    }
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({ message }),
    });
    if (r.ok) sent++;
    else if (r.status === 404 || r.status === 400) {
      const err = await r.json().catch(() => ({}));
      const code = err?.error?.details?.[0]?.errorCode ?? err?.error?.status;
      if (code === "UNREGISTERED" || r.status === 404) dead.push(token);
      else console.warn("fcm send failed", r.status, JSON.stringify(err).slice(0, 300));
    }
  }));
  if (dead.length) await admin.from("push_tokens").delete().in("token", dead);
  return json({ sent, removed: dead.length });
});
