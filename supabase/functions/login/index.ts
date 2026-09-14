// Username-or-email login and password reset, done server-side so a username
// never has to be turned into an email on the phone (no email enumeration).
//   { action: 'password', identifier, password } -> { access_token, refresh_token }
//   { action: 'reset', identifier }               -> { ok: true }  (always, even if unknown)
import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// A web page (GitHub Pages) so the link works on any device; on phones it offers "Open in the app".
const RESET_REDIRECT = "https://creatiqai.github.io/TTSpot/reset.html";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/** Resolve "username or email" to an email, or null. Usernames are looked up with the service role. */
async function resolveEmail(identifier: string): Promise<string | null> {
  const id = identifier.trim().toLowerCase();
  if (!id) return null;
  if (id.includes("@")) return id;
  const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });
  const { data: prof } = await admin.from("profiles").select("id").ilike("username", id).maybeSingle();
  if (!prof) return null;
  const { data: u } = await admin.auth.admin.getUserById(prof.id);
  return u?.user?.email ?? null;
}

Deno.serve(async (req) => {
  const body = await req.json().catch(() => ({}));
  const action = String(body.action ?? "");

  if (action === "password") {
    const email = await resolveEmail(String(body.identifier ?? ""));
    const password = String(body.password ?? "");
    if (!email || !password) return json({ error: "Wrong username or password." }, 400);
    const anon = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await anon.auth.signInWithPassword({ email, password });
    if (error || !data.session) return json({ error: "Wrong username or password." }, 400);
    return json({ access_token: data.session.access_token, refresh_token: data.session.refresh_token });
  }

  if (action === "reset") {
    const email = await resolveEmail(String(body.identifier ?? ""));
    // Same answer whether or not the account exists.
    if (email) {
      const anon = createClient(URL, ANON, { auth: { persistSession: false } });
      const { error } = await anon.auth.resetPasswordForEmail(email, { redirectTo: RESET_REDIRECT });
      if (error && !/rate limit/i.test(error.message)) console.error("reset failed", error.message);
      if (error && /rate limit/i.test(error.message)) return json({ error: "Too many reset emails right now. Try again in an hour." }, 429);
    }
    return json({ ok: true });
  }

  return json({ error: "unknown action" }, 400);
});
