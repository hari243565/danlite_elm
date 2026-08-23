// ══════════════════════════════════════════════════════════════════════════
// /admin-request-otp — step 1 of admin login.
//
// Takes an email. If it is on the public.admin_users allowlist, sends the
// same 6-digit OTP the customer app already uses. If it is not, says so
// plainly and sends nothing.
//
// ── WHY THIS IS NOT ENUMERATION-SAFE, AND WHY THAT IS CORRECT HERE ───────
// /send-activation deliberately returns an identical response whether or not
// an account exists. That is right for CUSTOMERS: an open, unknown, growing
// population where confirming "this address is a Danlite customer" is a real
// privacy leak about a real person.
//
// The admin population is the opposite in every respect that matters: it is
// two or three people, fixed, and known in advance. Copying the customer
// flow's ambiguity here would buy nothing and cost three real things:
//
//   1. A stray auth.users row for anybody who guesses the URL. Every one of
//      those is a real account in the real auth system, and the customer
//      signup trigger chain (handle_new_user -> licences insert ->
//      send-activation) fires on it. A stranger poking this endpoint would
//      mint themselves a Danlite account and get a billing email.
//   2. A burnt Resend send, against a quota that customer activation emails
//      depend on.
//   3. A worse tool. An admin who fat-fingers their own address gets
//      "check your email", checks it, finds nothing, and has no idea whether
//      the mail is slow or they mistyped. The honest 403 tells them.
//
// The URL is unlinked and unindexed (three layers, see admin/proxy.ts), so
// the ambiguity would not have been hiding the endpoint's existence anyway.
// This is an intentional, documented divergence — not an oversight, and not
// a pattern to copy back into any customer-facing function.
//
// ── WHAT STILL DEFENDS THIS ENDPOINT ─────────────────────────────────────
// Being honest about membership makes rate limiting more important, not
// less, because a truthful yes/no is exactly what a bulk prober wants. So
// this function reuses the Phase 4 pattern verbatim: a DB-backed,
// append-only ledger keyed by peppered identifier hash and by IP, counted
// over a rolling hour, written whether or not the request is served.
//
// DEPLOYED WITH --no-verify-jwt: this is the front door of login. There is
// no JWT yet, by definition. Authorisation is the allowlist check below.
// ══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { adminClient, CORS_HEADERS, json, normalizeEmail } from "../_shared/admin_guard.ts";

/** Budgets, both over a rolling hour. Tighter than the customer flow's 3/10:
 *  a legitimate admin logs in a handful of times a day, so a low ceiling
 *  costs them nothing and costs a prober a great deal. */
const MAX_PER_IDENTIFIER_PER_HOUR = 5;
const MAX_PER_IP_PER_HOUR = 8;

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return bytesToHex(new Uint8Array(digest));
}

/**
 * Peppered hash of the address, for the rate-limit ledger.
 *
 * Same construction as send-activation's, with a DIFFERENT domain-separating
 * label. Sharing the secret is fine; sharing the derived pepper would mean a
 * hash in admin_otp_requests could be matched against one in
 * activation_requests, silently linking "this person tried to log into the
 * admin tool" with "this person requested a customer activation email".
 * Domain separation keeps the two ledgers unlinkable.
 */
async function identifierHash(normalized: string): Promise<string> {
  const secret = Deno.env.get("ACTIVATION_WEBHOOK_SECRET") ?? "";
  const pepper = await sha256Hex(`${secret}|admin-otp-identifier-pepper`);
  return await sha256Hex(`${pepper}|${normalized}`);
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const rawEmail = typeof body.email === "string" ? body.email : "";

    if (!rawEmail.trim() || !rawEmail.includes("@")) {
      return json({ error: "A valid email address is required." }, 400);
    }

    const email = normalizeEmail(rawEmail);
    const admin = adminClient();

    const ip =
      req.headers.get("cf-connecting-ip") ??
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      null;

    const idHash = await identifierHash(email);
    const windowStart = new Date(Date.now() - 60 * 60_000).toISOString();

    // ── RATE LIMIT — counted BEFORE this attempt is logged, then logged
    //    unconditionally below. If a blocked attempt did not extend the
    //    window, a prober could hammer forever: every rejection would age
    //    out of the hour and the limit would never actually bite.
    const { count: idCount } = await admin
      .from("admin_otp_requests")
      .select("id", { count: "exact", head: true })
      .eq("identifier_hash", idHash)
      .gte("created_at", windowStart);

    let ipCount = 0;
    if (ip) {
      const { count } = await admin
        .from("admin_otp_requests")
        .select("id", { count: "exact", head: true })
        .eq("ip", ip)
        .gte("created_at", windowStart);
      ipCount = count ?? 0;
    }

    const overLimit =
      (idCount ?? 0) >= MAX_PER_IDENTIFIER_PER_HOUR || ipCount >= MAX_PER_IP_PER_HOUR;

    // ── IS THIS AN ADMIN? ────────────────────────────────────────────────
    // Read before the rate-limit response so the ledger records which
    // attempts were for real admin addresses. A run of `was_allowed=false`
    // from one IP is the signature of somebody guessing.
    const { data: allowRow, error: allowErr } = await admin
      .from("admin_users")
      .select("id")
      .eq("email", email)
      .maybeSingle();

    if (allowErr) {
      console.error("admin allowlist lookup failed:", allowErr.message);
      await admin.from("admin_otp_requests").insert({
        identifier_hash: idHash,
        ip,
        was_allowed: false,
      });
      // FAIL CLOSED — an outage must not become an open door.
      return json({ error: "Could not verify admin access. Try again shortly." }, 503);
    }

    const isAdmin = Boolean(allowRow);

    await admin.from("admin_otp_requests").insert({
      identifier_hash: idHash,
      ip,
      was_allowed: isAdmin,
    });

    // Rate limit is checked AFTER logging but BEFORE any email is sent, and
    // it applies to admins and non-admins alike — otherwise the difference
    // in behaviour at the limit would itself be an oracle.
    if (overLimit) {
      return json(
        {
          error: "Too many sign-in attempts. Please try again in an hour.",
          code: "rate_limited",
        },
        429,
      );
    }

    if (!isAdmin) {
      // The plain, honest rejection. Nothing is sent, and critically
      // signInWithOtp is NOT called — so no auth.users row is created and no
      // Resend send is consumed for a stranger.
      console.warn("admin-request-otp: rejected non-allowlisted address");
      return json({ error: "This email is not authorized for admin access." }, 403);
    }

    // ── SEND THE OTP ─────────────────────────────────────────────────────
    // The ANON client, not service_role: this is an ordinary passwordless
    // sign-in, and it must go through exactly the same Supabase Auth path
    // (and therefore the same proven {{ .Token }} email template) that the
    // customer app already uses. Nothing bespoke, nothing new to maintain.
    //
    // Verified against the installed supabase-js 2.x / auth-js: the method is
    // signInWithOtp(credentials) taking options.shouldCreateUser.
    //
    // shouldCreateUser: true is safe HERE and only here, because this line is
    // unreachable unless the address is already on the allowlist. It is what
    // lets the owner log in the very first time without an account being
    // pre-created by hand.
    const authClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const { error: otpErr } = await authClient.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: true },
    });

    if (otpErr) {
      console.error("admin OTP send failed:", otpErr.message);
      return json({ error: "Could not send the sign-in code. Try again shortly." }, 502);
    }

    return json(
      { status: "sent", message: "A 6-digit sign-in code has been sent to your email." },
      200,
    );
  } catch (err) {
    console.error(
      "admin-request-otp error:",
      err instanceof Error ? err.message : String(err),
    );
    return json({ error: "Sign-in request failed." }, 500);
  }
});
