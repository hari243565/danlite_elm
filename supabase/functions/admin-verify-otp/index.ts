// ══════════════════════════════════════════════════════════════════════════
// /admin-verify-otp — step 2 of admin login.
//
// Takes the email and the 6-digit code, verifies it with Supabase Auth
// exactly as the customer app does, and returns the resulting token pair to
// the admin app's server-side route handler, which is what actually writes
// the cookies.
//
// ── WHY THIS FUNCTION RETURNS TOKENS INSTEAD OF SETTING COOKIES ──────────
// It cannot set them. This function is served from
// <project>.supabase.co; the admin app is served from its own origin. A
// Set-Cookie written here would be scoped to supabase.co and would never be
// sent to the admin app — the session would appear to work and then silently
// not exist.
//
// So the split is:
//   THIS FUNCTION          verifies the code, returns { access_token,
//                          refresh_token } over HTTPS to a server, never to
//                          a browser.
//   admin/app/api/auth/verify/route.ts
//                          receives them and calls setSession() on the
//                          @supabase/ssr server client, which writes
//                          httpOnly + Secure + SameSite=Lax cookies on the
//                          admin app's own origin.
//
// The tokens therefore travel server -> server and are never handed to
// page JavaScript. The browser only ever holds the httpOnly cookie, which it
// cannot read. That is a strictly better outcome than the common pattern of
// verifying in the browser and calling setSession() client-side, where the
// refresh token lands in JS-reachable storage and any XSS becomes permanent
// account takeover rather than a bounded session hijack.
//
// ── THE ALLOWLIST IS CHECKED AGAIN HERE ──────────────────────────────────
// admin-request-otp already checked it. This checks it again, because the
// two calls are independent HTTP requests and nothing stops someone calling
// this one directly. Without the re-check, any Danlite customer who
// requested a normal OTP through the app could present their own valid code
// here and be handed an admin session. That is the actual attack, and it is
// one line to close.
//
// DEPLOYED WITH --no-verify-jwt: the caller has no session yet; obtaining
// one is the entire purpose of this endpoint.
// ══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { adminClient, CORS_HEADERS, json, normalizeEmail } from "../_shared/admin_guard.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const rawEmail = typeof body.email === "string" ? body.email : "";
    const token = typeof body.token === "string" ? body.token.trim() : "";

    if (!rawEmail.trim() || !token) {
      return json({ error: "Email and sign-in code are both required." }, 400);
    }

    const email = normalizeEmail(rawEmail);
    const admin = adminClient();

    // ── GATE 1: still on the allowlist? ──────────────────────────────────
    // Deliberately before the code is verified, so a non-admin holding a
    // valid OTP for their own account never reaches verifyOtp through this
    // endpoint at all.
    const { data: allowRow, error: allowErr } = await admin
      .from("admin_users")
      .select("id")
      .eq("email", email)
      .maybeSingle();

    if (allowErr) {
      console.error("admin allowlist lookup failed:", allowErr.message);
      return json({ error: "Could not verify admin access. Try again shortly." }, 503);
    }
    if (!allowRow) {
      // ── SECURITY FIX, 2026-09-19 — do NOT say "not an admin" here. ─────
      //
      // THE ORACLE THIS CLOSES. /admin-request-otp answers honestly about
      // allowlist membership, which is a reasoned, documented inversion of
      // the customer-facing design — and its stated compensating control is
      // the DB-backed rate-limit ledger: "Being honest about membership
      // makes rate limiting more important, not less, because a truthful
      // yes/no is exactly what a bulk prober wants."
      //
      // This endpoint leaked the identical fact with NO ledger, NO per-IP
      // budget, no email sent and no row written. An unauthenticated caller
      // could post {email: <guess>, token: "000000"} and read the status
      // code: 403 meant "not an admin", 401 meant "IS an admin". Free,
      // unlimited, and silent. Every rate-limit argument made for the
      // request endpoint applied here and none of it had been applied.
      //
      // WHY A UNIFORM RESPONSE RATHER THAN A RATE LIMIT. The honest 403 was
      // argued for on operational grounds that belong entirely to the
      // REQUEST step — an admin who mistypes their address needs to be told,
      // instead of waiting for mail that will never arrive. That is still
      // exactly what /admin-request-otp does, and it is untouched. By the
      // time someone is typing a 6-digit code they have already been told.
      // So at this step the honest answer buys nothing and leaks everything,
      // and collapsing it into the generic code-rejection message removes
      // the oracle outright instead of merely metering it.
      //
      // GATE ORDERING IS DELIBERATELY UNCHANGED. The allowlist is still
      // checked BEFORE verifyOtp, so a non-admin holding a valid code for
      // their own account still never reaches the auth server through this
      // endpoint and still never has that code consumed. Only the response
      // text and status change — 401 with the same string the wrong-code
      // branch below returns, so the two are indistinguishable.
      //
      // The log line stays specific: the distinction is useful to an
      // operator reading logs and is not visible to the caller.
      console.warn("admin-verify-otp: rejected non-allowlisted address");
      return json({ error: "That code is incorrect or has expired." }, 401);
    }

    // ── GATE 2: is the code real? ────────────────────────────────────────
    // Verified against the installed supabase-js 2.x / auth-js:
    //   verifyOtp({ email, token, type: 'email' }): Promise<AuthResponse>
    // 'email' is a member of EmailOtpType and is the type that pairs with a
    // signInWithOtp-issued code. Supabase Auth enforces the code's own
    // expiry and attempt limits; we do not reimplement either.
    const authClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const { data, error: verifyErr } = await authClient.auth.verifyOtp({
      email,
      token,
      type: "email",
    });

    if (verifyErr || !data?.session) {
      // One message for wrong, expired, and already-used. Distinguishing
      // them would tell someone brute-forcing which codes were real.
      console.warn("admin-verify-otp: code rejected");
      return json({ error: "That code is incorrect or has expired." }, 401);
    }

    // ── GATE 3: paranoia, cheaply. ───────────────────────────────────────
    // Confirm the identity the auth server actually returned matches the
    // address we allowlisted, rather than assuming verifyOtp honoured the
    // email we passed it. If these ever disagreed, something is very wrong
    // and the right move is to issue nothing.
    const verifiedEmail = normalizeEmail(data.user?.email ?? "");
    if (verifiedEmail !== email) {
      console.error("admin-verify-otp: verified identity did not match requested address");
      return json({ error: "Sign-in failed." }, 401);
    }

    return json(
      {
        status: "ok",
        access_token: data.session.access_token,
        refresh_token: data.session.refresh_token,
        email: verifiedEmail,
      },
      200,
    );
  } catch (err) {
    console.error(
      "admin-verify-otp error:",
      err instanceof Error ? err.message : String(err),
    );
    return json({ error: "Sign-in failed." }, 500);
  }
});
