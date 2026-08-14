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

    // 3. Build the claims.
    const iat = Math.floor(Date.now() / 1000);
    const claims: EntitlementClaims = {
      sub: userId,
      lic: status,
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
