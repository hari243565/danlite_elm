// ══════════════════════════════════════════════════════════════════════════
// /entitlement — the trusted authority on whether a user holds a licence.
//
// Returns a SIGNED, tamper-evident statement of the caller's licence status.
// The app verifies that signature locally with an embedded Ed25519 public key,
// which is what lets it keep working for 14 days with no network at all — the
// core requirement for mechanics working in garages with no signal.
//
// THIS FUNCTION GATES NOTHING. It reports the truth and signs it. Phase 8
// decides what the app does with a status of 'inactive'.
//
// TRUST MODEL:
//   • The caller proves identity with their Supabase Auth JWT. We never take
//     a user id from the request body — it comes from the verified token only.
//     Otherwise any signed-in user could mint a token naming somebody else.
//   • We read licences with the service-role key, deliberately bypassing RLS.
//     This function IS the authority; it must be able to read the row it is
//     making a statement about. The migration grants it SELECT and nothing
//     more, so it cannot alter a licence even if this code is buggy.
//   • The private key never leaves this process. It is not logged, not
//     returned, and not included in any error path.
// ══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  buildCanonicalPayload,
  type EntitlementClaims,
} from "../_shared/canonical_payload.ts";

/** 14 days, in seconds — the offline grace window. */
const TOKEN_TTL_SECONDS = 14 * 24 * 60 * 60; // 1_209_600

/** Shape check for an optional caller-supplied session id (Phase 7). A value
 *  that is not a UUID is a client bug, and it must NOT be allowed to fall
 *  through to the mismatch branch below — that would turn a malformed string
 *  into a forced logout. It is rejected as a 400 instead. */
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ══════════════════════════════════════════════════════════════════════════
// EMERGENCY PAYWALL BYPASS (Phase 8)
//
// WHAT IT IS
//   A switch that makes /entitlement answer `lic: "active"` for every
//   authenticated caller. The token is signed normally, over the normal
//   canonical string, with the normal 14-day TTL — so the app's verification
//   path is untouched and NO client update is needed to use it. That is the
//   whole point: it can be turned on from the Supabase dashboard while
//   customers are being wrongly locked out, and it takes effect on the next
//   refresh of every phone.
//
// WHEN IT IS APPROPRIATE TO USE
//   Exactly one situation: a CONFIRMED defect in the paywall is locking out
//   real paying customers, and the fix is not yet deployed. It is a way to
//   stop the bleeding while the real bug is found. It is not a discount, not
//   a trial mechanism, not a way to hand somebody a licence, and not
//   something to leave on "just in case".
//
// IT MUST BE TURNED OFF THE MOMENT THE DEFECT IS FIXED.
//   While it is on, every caller is entitled — including people who have
//   never paid — and every one of them walks away with a token that stays
//   valid offline for 14 DAYS after the switch is turned back off. Turning it
//   off does not un-issue those tokens. The longer it is on, the longer the
//   tail.
//
//   To turn it on:   set PAYWALL_EMERGENCY_BYPASS to the exact value below.
//   To turn it off:  delete the secret (or set it to anything else) and
//                    redeploy/restart. Verify with check 9 in
//                    portal/phase8-report.json.
//
// WHY AN EXACT VALUE AND NOT A TRUTHY CHECK
//   `if (Deno.env.get(...))` would arm on "0", on "false", on "off", and on a
//   stray space left behind by a copy-paste. A switch whose failure mode is
//   "the paywall silently stopped existing and nobody noticed" has to be
//   impossible to arm by accident, so it demands one exact non-obvious
//   string and nothing else opens it.
//
// EVERY USE IS AUDITED
//   One `audit_log` row per request, action `paywall_emergency_bypass_used`,
//   naming the user and the licence status that was overridden. A silent
//   global bypass would be indefensible; a loud one is an operational tool.
// ══════════════════════════════════════════════════════════════════════════
const PAYWALL_BYPASS_ARMING_VALUE = "EMERGENCY-PAYWALL-BYPASS-ON";

/** True only for that exact value. Never for "1", "true", "yes" or "". */
function paywallBypassArmed(): boolean {
  const raw = Deno.env.get("PAYWALL_EMERGENCY_BYPASS");
  return typeof raw === "string" && raw.trim() === PAYWALL_BYPASS_ARMING_VALUE;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ── base64 / base64url helpers ────────────────────────────────────────────
function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** base64url, unpadded — what we put in `sig`. */
function bytesToB64Url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// ── signing ───────────────────────────────────────────────────────────────
//
// The secret is base64 of the 48-byte PKCS#8 DER. Two consumers:
//   • crypto.subtle.importKey("pkcs8", …) takes that DER directly.
//   • @noble/ed25519 wants the raw 32-byte seed, which is the last 32 bytes
//     of that same DER (the PKCS#8 wrapper for Ed25519 is a fixed 16-byte
//     prefix followed by the seed).
// One secret serves both paths, so the fallback needs no re-keying.

let cachedSubtleKey: CryptoKey | null = null;
/** Which code path actually signed — surfaced in the response for the report. */
let signingPath: "crypto.subtle" | "npm:@noble/ed25519" | null = null;

function privateKeyDer(): Uint8Array {
  const b64 = Deno.env.get("ED25519_PRIVATE_KEY");
  if (!b64) {
    // Deliberately vague to the caller; specific in the log. Never echo the value.
    throw new Error("ED25519_PRIVATE_KEY is not configured");
  }
  const der = b64ToBytes(b64.trim());
  if (der.length !== 48) {
    throw new Error(
      `ED25519_PRIVATE_KEY must be base64 of a 48-byte PKCS#8 DER, got ${der.length} bytes`,
    );
  }
  return der;
}

async function sign(message: Uint8Array): Promise<Uint8Array> {
  // Path 1 — native WebCrypto Ed25519. Preferred: no dependency, no cold-start
  // module fetch, and the key object stays non-extractable.
  try {
    if (!cachedSubtleKey) {
      cachedSubtleKey = await crypto.subtle.importKey(
        "pkcs8",
        privateKeyDer(),
        { name: "Ed25519" },
        false, // non-extractable
        ["sign"],
      );
    }
    const sig = await crypto.subtle.sign(
      { name: "Ed25519" },
      cachedSubtleKey,
      message,
    );
    signingPath = "crypto.subtle";
    return new Uint8Array(sig);
  } catch (subtleErr) {
    // Path 2 — npm fallback, for runtimes whose WebCrypto lacks Ed25519.
    // Same key material, just the raw seed instead of the PKCS#8 wrapper.
    console.log(
      "crypto.subtle Ed25519 unavailable, falling back to @noble/ed25519:",
      subtleErr instanceof Error ? subtleErr.message : String(subtleErr),
    );
    const ed = await import("npm:@noble/ed25519@2");
    const seed = privateKeyDer().slice(16); // last 32 bytes
    const sig = await ed.signAsync(message, seed);
    signingPath = "npm:@noble/ed25519";
    return sig;
  }
}

// ── handler ───────────────────────────────────────────────────────────────
Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    // 1. Authenticate. No JWT, no token — full stop.
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return json({ error: "missing bearer token" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Validate the caller's JWT with the anon client. getUser() checks the
    // signature and expiry server-side — we do not decode it ourselves.
    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userErr } = await authClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "invalid or expired token" }, 401);
    }
    const userId = userData.user.id;

    // 1b. (Phase 7) The caller MAY name the session it believes it holds.
    //
    // OPTIONAL, and that is load-bearing. An installed app from before Phase 7
    // sends no body at all, and the portal sends `{}`. Both must keep working
    // exactly as they did — an older build must never be locked out, and the
    // portal must never be able to disturb a phone's session just by rendering
    // /account. No session_id means no session check, full stop.
    let callerSessionId: string | null = null;
    try {
      const raw = await req.text();
      if (raw.trim().length > 0) {
        const body = JSON.parse(raw) as Record<string, unknown>;
        const sid = body.session_id;
        if (typeof sid === "string" && sid.trim().length > 0) {
          const trimmed = sid.trim();
          if (!UUID_RE.test(trimmed)) {
            return json({ error: "session_id is malformed" }, 400);
          }
          callerSessionId = trimmed;
        }
      }
    } catch {
      return json({ error: "malformed JSON body" }, 400);
    }

    // 2. Read the licence as the authority (service role, bypasses RLS).
    const adminClient = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: licence, error: licErr } = await adminClient
      .from("licences")
      .select("status, active_session_id, active_device_id")
      .eq("user_id", userId)
      .maybeSingle(); // no row -> null, not an error

    if (licErr) {
      console.error("licence read failed:", licErr.message);
      return json({ error: "licence lookup failed" }, 500);
    }

    // No row should be impossible after the Phase 3 migration, but a missing
    // row must never crash or, worse, fail open. Absent == not entitled.
    const status = licence?.status ?? "inactive";

    // 2b. (Phase 7) Is the caller still the active session?
    //
    // This is the ONLY place in the entire system that can tell a device to
    // log itself out, so the condition is written to be as narrow as it can
    // possibly be. All three must hold:
    //   • the caller actually named a session (older builds and the portal
    //     do not, and are therefore untouchable by this branch);
    //   • the licence actually HAS an active session (a cleared one — after
    //     "sign out all devices" — must not evict anybody; the next claim
    //     will sort it out);
    //   • the two genuinely differ.
    // Anything else falls through and gets a token as normal.
    if (
      callerSessionId !== null &&
      licence?.active_session_id != null &&
      licence.active_session_id !== callerSessionId
    ) {
      // No token is issued on this path. A superseded device gets a signal,
      // not a signed statement it could keep using for 14 days.
      return json({ error: "SESSION_SUPERSEDED" }, 409);
    }

    // Still the active session — record the heartbeat so support can tell an
    // idle device from a live one. Best-effort: a failed heartbeat is a
    // bookkeeping loss, never a reason to withhold a token.
    if (callerSessionId !== null) {
      const { error: touchErr } = await adminClient.rpc("touch_session", {
        p_session_id: callerSessionId,
      });
      if (touchErr) console.error("touch_session failed:", touchErr.message);
    }

    // 2c. (Phase 8) The emergency bypass. See the block comment at the top of
    // this file for when this is legitimate and why it demands an exact value.
    //
    // Deliberately placed AFTER the Phase 7 session check: this is a paywall
    // escape hatch, not a session one, and a superseded device must still be
    // told it was superseded. It changes exactly one thing — the licence
    // status that goes into the claims — and nothing about the signing, the
    // canonical string, the TTL or the key.
    let effectiveStatus = status;
    if (paywallBypassArmed()) {
      effectiveStatus = "active";

      // Loud, on every single request. Best-effort in the sense that a failed
      // audit write does not withhold the token — the switch is only ever on
      // because customers are already locked out, and failing closed here
      // would defeat the entire reason for its existence — but it is shouted
      // into the function log as well, so a broken audit trail is visible.
      console.warn(
        `PAYWALL_EMERGENCY_BYPASS ACTIVE — issuing lic:"active" to ${userId} ` +
          `(real status: ${status}). This must be turned off.`,
      );
      const { error: auditErr } = await adminClient.from("audit_log").insert({
        user_id: userId,
        action: "paywall_emergency_bypass_used",
        detail: {
          real_licence_status: status,
          issued_licence_status: "active",
          had_session_id: callerSessionId !== null,
          function: "entitlement",
        },
      });
      if (auditErr) {
        console.error(
          "AUDIT WRITE FAILED for paywall_emergency_bypass_used:",
          auditErr.message,
        );
      }
    }

    // 3. Build the claims.
    const iat = Math.floor(Date.now() / 1000);
    const claims: EntitlementClaims = {
      sub: userId,
      lic: effectiveStatus,
      // Phase 7 columns. Null today, and the canonical format renders null as
      // the empty string — see _shared/canonical_payload.ts.
      sid: licence?.active_session_id ?? "",
      did: licence?.active_device_id ?? "",
      iat,
      exp: iat + TOKEN_TTL_SECONDS,
    };

    // 4. Sign the canonical string — NOT the JSON. See _shared for why.
    const canonical = buildCanonicalPayload(claims);
    const sig = await sign(new TextEncoder().encode(canonical));

    return json({
      ...claims,
      sig: bytesToB64Url(sig),
      // Diagnostic only, not covered by the signature and never trusted by the
      // client. Present so Phase 3 verification can record which path ran.
      alg: "Ed25519",
      signing_path: signingPath,
    }, 200);
  } catch (err) {
    // Never let an exception carry key material out. Log the message, return a
    // generic failure.
    console.error("entitlement error:", err instanceof Error ? err.message : String(err));
    return json({ error: "entitlement generation failed" }, 500);
  }
});
