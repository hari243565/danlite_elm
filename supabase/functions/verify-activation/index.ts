// ══════════════════════════════════════════════════════════════════════════
// /verify-activation — redeems a one-time activation token for a real session.
//
// This is the session bridge. The customer clicks a link in their email and
// arrives at the billing portal already signed in as the SAME Supabase user,
// with no password and no second OTP. That is the whole point: every extra
// step between "I signed up" and "I paid" costs conversions.
//
// HOW THE SESSION IS MINTED (verified against the installed SDK, not assumed):
//   1. admin.generateLink({ type: 'magiclink', email }) produces a redeemable
//      artifact server-side and returns properties.hashed_token.
//   2. auth.verifyOtp({ token_hash, type: 'email' }) immediately redeems it
//      for access + refresh tokens.
//
// Supabase NEVER emails that generated link. It is created and consumed inside
// this function, microseconds apart. The only link a customer ever sees is our
// own branded one from /send-activation.
//
// NOTE ON `type`: the SDK's own docs mark the 'magiclink' verify type as
// deprecated ("note: signup and magiclink types are deprecated") and document
// token-hash redemption as { token_hash, type: 'email' }. The generate step
// still uses 'magiclink'; only the verify step uses 'email'.
//
// DEPLOYED WITH --no-verify-jwt: the caller has no session yet — acquiring one
// is the entire purpose. The 256-bit single-use token IS the credential.
// ══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/**
 * The single failure response for every rejected token.
 *
 * Deliberately says nothing about WHICH check failed. "Expired" tells an
 * attacker the token was real and they were merely too slow; "already used"
 * confirms a valid link exists for that customer. One opaque answer for
 * never-existed, malformed, expired, and already-redeemed alike.
 */
const GENERIC_FAILURE = {
  status: "invalid",
  message: "This link is invalid or has expired.",
};

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return bytesToHex(new Uint8Array(digest));
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const rawToken = typeof body.token === "string" ? body.token.trim() : "";

    if (!rawToken) return json(GENERIC_FAILURE, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const tokenHash = await sha256Hex(rawToken);
    const nowIso = new Date().toISOString();

    // ── ATOMIC REDEMPTION ────────────────────────────────────────────────
    // The validity test and the "mark used" write are ONE statement:
    //   UPDATE activation_tokens SET used_at = now()
    //    WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now()
    //   RETURNING user_id
    //
    // Checking first and updating second would leave a window in which two
    // concurrent requests both read used_at IS NULL and both proceed — a
    // forwarded email could then mint two sessions. Because the WHERE clause
    // is evaluated under the row lock taken by the UPDATE itself, exactly one
    // of any number of concurrent redemptions gets a row back; the rest get
    // zero rows and fall through to GENERIC_FAILURE.
    const { data: redeemed, error: redeemErr } = await admin
      .from("activation_tokens")
      .update({ used_at: nowIso })
      .eq("token_hash", tokenHash)
      .is("used_at", null)
      .gt("expires_at", nowIso)
      .select("user_id");

    if (redeemErr) {
      console.error("token redemption failed:", redeemErr.message);
      return json(GENERIC_FAILURE, 400);
    }
    if (!redeemed || redeemed.length === 0) {
      // Never existed / expired / already used — indistinguishable by design.
      return json(GENERIC_FAILURE, 400);
    }

    const userId = redeemed[0].user_id as string;

    // ── Establish a real session for that user ───────────────────────────
    const { data: userData, error: userErr } = await admin.auth.admin.getUserById(userId);
    if (userErr || !userData?.user?.email) {
      console.error(
        "cannot mint session:",
        userErr?.message ?? "user has no email address",
      );
      return json(GENERIC_FAILURE, 400);
    }
    const email = userData.user.email;

    // generateLink also CREATES a user when one does not exist. That is not a
    // risk here: userId came from a token row whose FK guarantees the user
    // exists, and the email is read back from auth.users rather than taken
    // from the request.
    const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });

    if (linkErr || !linkData?.properties?.hashed_token) {
      console.error("generateLink failed:", linkErr?.message ?? "no hashed_token returned");
      return json(GENERIC_FAILURE, 400);
    }

    // Redeem with the anon client — verifyOtp is a public auth endpoint, and
    // using the anon key keeps the service-role key off this code path.
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: sessionData, error: verifyErr } = await authClient.auth.verifyOtp({
      token_hash: linkData.properties.hashed_token,
      type: "email",
    });

    if (verifyErr || !sessionData?.session) {
      console.error("verifyOtp failed:", verifyErr?.message ?? "no session returned");
      return json(GENERIC_FAILURE, 400);
    }

    // Returned to the Next.js route handler, which writes them into httpOnly,
    // Secure, SameSite=Lax cookies. They are never rendered into a page.
    return json({
      status: "ok",
      access_token: sessionData.session.access_token,
      refresh_token: sessionData.session.refresh_token,
      expires_at: sessionData.session.expires_at,
      user: { id: userId, email },
    }, 200);
  } catch (err) {
    console.error(
      "verify-activation error:",
      err instanceof Error ? err.message : String(err),
    );
    return json(GENERIC_FAILURE, 400);
  }
});
