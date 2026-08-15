// ══════════════════════════════════════════════════════════════════════════
// /claim-session — the Android app announces "this device is now the one".
//
// Called ONCE per successful login, by the app and by nothing else. The
// billing portal must never call this: a session claim logs the user's phone
// out, and doing that as a side effect of a web page load would sign a
// customer out of the app at the exact moment they finished paying for it.
//
// TRUST MODEL — the same shape as /entitlement:
//   • The caller proves identity with their Supabase Auth JWT. The user id
//     comes from the verified token and NEVER from the request body,
//     otherwise any signed-in user could claim the session of somebody else
//     and log a stranger out of their phone at will.
//   • The actual work happens in public.claim_session(), a SECURITY DEFINER
//     function that serializes on the licence row. All the race-safety lives
//     there, in Postgres, not here — two Edge Function instances handling two
//     simultaneous logins cannot coordinate with each other, but the row lock
//     they both queue behind can.
//
// PRIVACY: the fingerprint is an opaque per-install hash. It is never logged,
// not on the success path and not in any error path.
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

/** Platforms the devices table's CHECK constraint will accept. */
const ALLOWED_PLATFORMS = new Set(["android", "web"]);

/** A SHA-256 hex digest is 64 chars. The bounds are deliberately loose either
 *  side of that so a future fingerprint scheme does not need a redeploy, but
 *  tight enough that a multi-megabyte body cannot be written into the table. */
const FINGERPRINT_MIN = 8;
const FINGERPRINT_MAX = 256;

const MODEL_MAX = 120;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    // 1. Authenticate.
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return json({ error: "missing bearer token" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userErr } = await authClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "invalid or expired token" }, 401);
    }
    const userId = userData.user.id;

    // 2. Read and validate the body. Reject absurd input rather than letting
    //    the table's CHECK constraint decide — a 400 with a reason is far
    //    easier to diagnose in the field than a 500 from a constraint.
    let body: Record<string, unknown> = {};
    try {
      const raw = await req.text();
      if (raw.trim().length > 0) body = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      return json({ error: "malformed JSON body" }, 400);
    }

    const rawFingerprint = body.fingerprint;
    if (typeof rawFingerprint !== "string") {
      return json({ error: "fingerprint is required" }, 400);
    }
    const fingerprint = rawFingerprint.trim();
    if (fingerprint.length < FINGERPRINT_MIN || fingerprint.length > FINGERPRINT_MAX) {
      // Length only — the value itself is never echoed back or logged.
      return json({ error: "fingerprint has an implausible length" }, 400);
    }

    const platform = typeof body.platform === "string" ? body.platform.trim() : "android";
    if (!ALLOWED_PLATFORMS.has(platform)) {
      return json({ error: "platform must be 'android' or 'web'" }, 400);
    }

    let model: string | null = null;
    if (typeof body.model === "string" && body.model.trim().length > 0) {
      model = body.model.trim().slice(0, MODEL_MAX);
    }

    // 3. Claim. Every bit of the concurrency handling is inside this function.
    const adminClient = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data, error } = await adminClient.rpc("claim_session", {
      p_user_id: userId,
      p_fingerprint: fingerprint,
      p_platform: platform,
      p_model: model,
    });

    if (error) {
      // P0002 = the licence row is missing. Impossible after the Phase 3
      // signup trigger, but it must not read as a server fault if it happens.
      if (error.code === "P0002") {
        console.error("claim_session: no licence row for user");
        return json({ error: "NO_LICENCE" }, 409);
      }
      console.error("claim_session failed:", error.message);
      return json({ error: "claim failed" }, 500);
    }

    // claim_session RETURNS TABLE, so supabase-js hands back an array of rows.
    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.session_id) {
      console.error("claim_session returned no row");
      return json({ error: "claim failed" }, 500);
    }

    return json({
      session_id: row.session_id,
      device_id: row.device_id,
      superseded: row.superseded === true,
      prior_device_id: row.prior_device_id ?? null,
    }, 200);
  } catch (err) {
    console.error(
      "claim-session error:",
      err instanceof Error ? err.message : String(err),
    );
    return json({ error: "claim failed" }, 500);
  }
});
