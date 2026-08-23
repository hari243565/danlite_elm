// ══════════════════════════════════════════════════════════════════════════
// ADMIN GUARD — the single gate every admin data function passes through.
//
// This module exists because the admin portal, by design, can see EVERY
// customer's data. That makes its access control the most security-sensitive
// code in the project, and the thing most likely to rot: five functions each
// hand-rolling their own allowlist check is five chances for one of them to
// be subtly wrong, and the wrong one will not announce itself.
//
// ── THE RULE THIS MODULE ENFORCES ────────────────────────────────────────
// Every admin request is authorised from scratch, on every single call:
//
//   1. The caller must present a valid Supabase Auth JWT. It is validated
//      against the auth server with getUser(), NOT decoded locally — a
//      locally-decoded JWT is an unsigned assertion, and trusting one is how
//      "admin" becomes a claim anybody can type.
//   2. The email on that verified token must be present in public.admin_users
//      RIGHT NOW. Not "was present at login", not "the session says so" —
//      the table is re-read on every request.
//
// Step 2 is the load-bearing one, and it is deliberately redundant with the
// login flow. Logging in already required passing the allowlist, so checking
// again looks like duplicated work. It is not. It is the answer to "what if
// a session cookie were forged, replayed, or stolen, or the login function
// had a bug?" — because in every one of those cases the request still
// arrives here holding an email that is not on the allowlist, and still gets
// a 403. Revocation works the same way: deleting a row from admin_users
// locks that person out on their very next request, with no session to
// invalidate and no cache to wait out.
//
// ── PRIVILEGE SPLIT ──────────────────────────────────────────────────────
// Two clients, deliberately not one:
//   • the ANON client carries the caller's JWT and is used ONLY to ask "who
//     is this?". It has no privilege of its own.
//   • the SERVICE_ROLE client reads admin_users and, after the gate passes,
//     the customer tables. It never leaves this Deno process and is never
//     placed in a response body.
// Using service_role to validate the caller's token would work but would
// mean the one client that can read every customer's row is also the one
// handling attacker-supplied credentials. Keeping them apart is free.
// ══════════════════════════════════════════════════════════════════════════

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/** '  Foo@Example.COM ' -> 'foo@example.com'. Applied on BOTH sides of every
 *  allowlist comparison and before the migration's seed insert, so the unique
 *  index and the lookup can never disagree about what counts as the same
 *  address. */
export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

/** Service-role client. Server-side only — this key is never serialised into
 *  a response, and the admin Next.js app never holds it. */
export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export type AdminIdentity = {
  userId: string;
  email: string;
};

export type GuardResult =
  | { ok: true; identity: AdminIdentity; admin: SupabaseClient }
  | { ok: false; response: Response };

/**
 * Authorise an admin request. Call this as the FIRST thing in every admin
 * data function and return `result.response` immediately if `ok` is false.
 *
 * Failure is deliberately uniform: every rejection below returns 401/403 with
 * a body that says nothing about which step failed. An admin tool's error
 * messages should not teach an attacker whether they have a valid token, a
 * valid-but-unlisted account, or neither.
 */
export async function requireAdmin(req: Request): Promise<GuardResult> {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return { ok: false, response: json({ error: "unauthorized" }, 401) };
  }

  // ── 1. Who is this? Answered by the auth server, not by us. ────────────
  const authClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authHeader } },
    },
  );

  const { data: userData, error: userErr } = await authClient.auth.getUser();
  if (userErr || !userData?.user?.email) {
    return { ok: false, response: json({ error: "unauthorized" }, 401) };
  }

  const email = normalizeEmail(userData.user.email);
  const admin = adminClient();

  // ── 2. Is this person an admin RIGHT NOW? ──────────────────────────────
  const { data: row, error: lookupErr } = await admin
    .from("admin_users")
    .select("id")
    .eq("email", email)
    .maybeSingle();

  if (lookupErr) {
    // FAIL CLOSED. A database fault must never be mistaken for a pass — this
    // is the branch where a lazy `if (error) {}` would silently hand every
    // customer's data to an unauthenticated caller during an outage.
    console.error("admin allowlist lookup failed:", lookupErr.message);
    return { ok: false, response: json({ error: "authorization check failed" }, 503) };
  }

  if (!row) {
    // Logged because a valid token belonging to a non-admin is genuinely
    // interesting: it means a real Danlite customer account reached an admin
    // endpoint. The email is logged, not the token.
    console.warn(`admin access denied for non-allowlisted account: ${email}`);
    return { ok: false, response: json({ error: "forbidden" }, 403) };
  }

  return { ok: true, identity: { userId: userData.user.id, email }, admin };
}

/** Shared preflight/method handling so the five data functions do not each
 *  reimplement it slightly differently. Returns a Response to send, or null
 *  to continue. */
export function handlePreflight(req: Request, allowed: string[]): Response | null {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (!allowed.includes(req.method)) return json({ error: "method not allowed" }, 405);
  return null;
}
