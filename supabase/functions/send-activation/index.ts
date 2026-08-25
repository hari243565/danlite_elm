// ══════════════════════════════════════════════════════════════════════════
// /send-activation — issues a one-time activation link and emails it.
//
// This function is the ONLY connection between "a user finished signup in the
// Flutter app" and "that user receives a billing-portal link". No Flutter file
// changed to make this work: the chain is
//
//   auth.users INSERT
//     -> handle_new_user()            (Phase 3 trigger)
//       -> licences INSERT
//         -> on_licence_created_send_activation  (Phase 4 trigger)
//           -> net.http_post  ->  THIS FUNCTION  ->  Resend
//
// TWO CALLERS, TWO TRUST LEVELS:
//
//   Path A — the database trigger above. Authenticated by a shared secret in
//     the x-activation-secret header. Trusted to name a user_id directly.
//
//   Path B — a human on /activate who did not get the email. Completely
//     unauthenticated, so it is rate-limited and must never reveal whether an
//     account exists. It supplies an email/phone, never a user id.
//
// EMAIL TRANSPORT: a direct HTTPS call to Resend. Supabase Auth's own SMTP
// integration is deliberately NOT used and NOT touched — that is reserved for
// the app's 6-digit OTP emails, and borrowing it here would couple the billing
// flow to the login flow's template and rate limits.
//
// DEPLOYED WITH --no-verify-jwt: Path B is public by design. Authentication is
// performed inside this function (Path A) or replaced by rate limiting plus an
// enumeration-safe response (Path B).
// ══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { captureFunctionError } from "../_shared/sentry.ts";

/** Activation links are short-lived: they are a bridge, not a credential. */
const TOKEN_TTL_MINUTES = 15;

/** Path B budgets, both measured over a rolling hour. */
const MAX_PER_IDENTIFIER_PER_HOUR = 3;
const MAX_PER_IP_PER_HOUR = 10;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-activation-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/**
 * The ONLY response Path B ever produces on a non-rate-limited request.
 *
 * Identical whether the identifier matched an account, matched an account with
 * no email address, or matched nothing at all. This is the Phase 2
 * account-enumeration defence applied consistently: an attacker with a list of
 * a million email addresses learns nothing about which are customers.
 */
const GENERIC_OK = {
  status: "ok",
  message:
    "If that email or mobile number matches an account, an activation link is on its way. Check your inbox, including spam.",
};

// ── crypto helpers ────────────────────────────────────────────────────────

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** base64url, unpadded — URL-safe so the token survives being a query param. */
function bytesToB64Url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return bytesToHex(new Uint8Array(digest));
}

/**
 * Constant-time comparison. A plain `===` on a secret leaks its length and,
 * in principle, its content through early-exit timing. Cheap to do correctly.
 */
function timingSafeEqual(a: string, b: string): boolean {
  const ab = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

/**
 * Hash an identifier for the rate-limit log.
 *
 * PEPPERED, not a bare SHA-256. A bare hash of an email address is trivially
 * reversible with a dictionary, which would make activation_requests a
 * de-facto plaintext list of who tried to activate. The pepper is derived from
 * ACTIVATION_WEBHOOK_SECRET through a domain-separating label so that the two
 * uses of that secret cannot be confused with one another.
 */
async function identifierHash(normalized: string): Promise<string> {
  const secret = Deno.env.get("ACTIVATION_WEBHOOK_SECRET") ?? "";
  const pepper = await sha256Hex(`${secret}|activation-identifier-pepper`);
  return await sha256Hex(`${pepper}|${normalized}`);
}

/** '  Foo@Example.COM ' -> 'foo@example.com';  '+91 98765 43210' -> '+919876543210'. */
function normalizeIdentifier(raw: string): { value: string; kind: "email" | "phone" } {
  const trimmed = raw.trim();
  if (trimmed.includes("@")) {
    return { value: trimmed.toLowerCase(), kind: "email" };
  }
  return { value: trimmed.replace(/[^\d+]/g, ""), kind: "phone" };
}

// ── the actual work ───────────────────────────────────────────────────────

type AdminClient = ReturnType<typeof createClient>;

/**
 * Mint a token, store only its hash, and email the raw value.
 *
 * The raw token exists in exactly two places: this function's memory, and the
 * customer's inbox. It is never logged, never returned in a response body, and
 * a complete dump of activation_tokens cannot reconstruct it.
 */
async function issueAndSend(
  admin: AdminClient,
  userId: string,
  email: string,
): Promise<{ ok: boolean; detail: string }> {
  const rawBytes = new Uint8Array(32);
  crypto.getRandomValues(rawBytes); // 256 bits of CSPRNG output, not a JWT
  const rawToken = bytesToB64Url(rawBytes);
  const tokenHash = await sha256Hex(rawToken);

  const expiresAt = new Date(Date.now() + TOKEN_TTL_MINUTES * 60_000).toISOString();

  const { error: insertErr } = await admin.from("activation_tokens").insert({
    user_id: userId,
    token_hash: tokenHash,
    expires_at: expiresAt,
  });

  if (insertErr) {
    console.error("activation_tokens insert failed:", insertErr.message);
    return { ok: false, detail: "token_persist_failed" };
  }

  const billingDomain = (Deno.env.get("BILLING_DOMAIN") ?? "http://localhost:3000")
    .replace(/\/+$/, "");
  const link = `${billingDomain}/activate?t=${rawToken}`;

  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    console.error("RESEND_API_KEY is not configured");
    return { ok: false, detail: "email_not_configured" };
  }

  // Falls back to Resend's shared sending domain so this works before a real
  // domain is verified. Override once billing.<domain> is set up.
  const from = Deno.env.get("ACTIVATION_FROM_EMAIL") ?? "Danlite ELM <onboarding@resend.dev>";

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [email],
      subject: "Activate your Danlite ELM licence",
      text: [
        "Thanks for signing up to Danlite ELM.",
        "",
        `Open this link to complete your purchase. It expires in ${TOKEN_TTL_MINUTES} minutes and can only be used once:`,
        "",
        link,
        "",
        "If you did not sign up, you can ignore this email — no account action will be taken.",
      ].join("\n"),
      html: activationHtml(link),
    }),
  });

  if (!res.ok) {
    // Log the status, never the key, never the link.
    const body = await res.text().catch(() => "");
    console.error(`resend send failed: HTTP ${res.status} ${body.slice(0, 300)}`);
    return { ok: false, detail: `resend_http_${res.status}` };
  }

  return { ok: true, detail: "sent" };
}

function activationHtml(link: string): string {
  // Deliberately plain. This is a transactional email from a company the
  // recipient just paid attention to, not a marketing blast — heavy imagery
  // and tracking pixels are what get transactional mail filtered as spam.
  return `<!doctype html>
<html><body style="margin:0;padding:24px;background:#07090E;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <div style="max-width:480px;margin:0 auto;background:#131922;border:1px solid #1C2A3A;border-radius:12px;padding:28px;">
    <h1 style="color:#EEF2F8;font-size:18px;margin:0 0 14px;">Activate your Danlite ELM licence</h1>
    <p style="color:#607080;font-size:14px;line-height:1.6;margin:0 0 22px;">
      Thanks for signing up. Use the button below to complete your one-time purchase.
      This link expires in ${TOKEN_TTL_MINUTES} minutes and can only be used once.
    </p>
    <a href="${link}" style="display:inline-block;background:#00CAFF;color:#07090E;font-weight:700;font-size:14px;text-decoration:none;padding:12px 22px;border-radius:8px;">
      Continue to checkout
    </a>
    <p style="color:#607080;font-size:12px;line-height:1.6;margin:22px 0 0;">
      If the button does not work, copy this address into your browser:<br>
      <span style="color:#00CAFF;word-break:break-all;">${link}</span>
    </p>
    <p style="color:#607080;font-size:12px;line-height:1.6;margin:18px 0 0;border-top:1px solid #1C2A3A;padding-top:14px;">
      If you did not sign up for Danlite ELM, you can ignore this email.
    </p>
  </div>
</body></html>`;
}

// ── handler ───────────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const providedSecret = req.headers.get("x-activation-secret");

    // ── PATH A — automated, post-signup ──────────────────────────────────
    if (providedSecret !== null) {
      const expected = Deno.env.get("ACTIVATION_WEBHOOK_SECRET") ?? "";
      if (!expected || !timingSafeEqual(providedSecret, expected)) {
        console.warn("send-activation: bad webhook secret");
        return json({ error: "unauthorized" }, 401);
      }

      const userId = typeof body.user_id === "string" ? body.user_id : null;
      if (!userId) return json({ error: "user_id required" }, 400);

      const { data: profile, error } = await admin
        .from("profiles")
        .select("email")
        .eq("id", userId)
        .maybeSingle();

      if (error) {
        console.error("profile lookup failed:", error.message);
        return json({ error: "lookup failed" }, 500);
      }
      if (!profile?.email) {
        // A phone-only signup has no address to email. Reported as a real
        // outcome rather than a silent success — see the Phase 4 report; the
        // SMS equivalent belongs with the MSG91 work in Phase 5/6.
        console.log("send-activation: user has no email address, skipping");
        return json({ status: "skipped", reason: "no_email_on_profile" }, 200);
      }

      const result = await issueAndSend(admin, userId, profile.email);
      return result.ok
        ? json({ status: "sent" }, 200)
        : json({ status: "failed", reason: result.detail }, 502);
    }

    // ── PATH B — user-initiated resend, unauthenticated ──────────────────
    const rawIdentifier = typeof body.identifier === "string" ? body.identifier : "";
    if (!rawIdentifier.trim()) {
      return json({ error: "identifier required" }, 400);
    }

    const { value: normalized, kind } = normalizeIdentifier(rawIdentifier);
    const idHash = await identifierHash(normalized);

    const ip =
      req.headers.get("cf-connecting-ip") ??
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      null;

    const windowStart = new Date(Date.now() - 60 * 60_000).toISOString();

    // Count BEFORE inserting this attempt, then insert unconditionally below.
    const { count: idCount } = await admin
      .from("activation_requests")
      .select("id", { count: "exact", head: true })
      .eq("identifier_hash", idHash)
      .gte("created_at", windowStart);

    let ipCount = 0;
    if (ip) {
      const { count } = await admin
        .from("activation_requests")
        .select("id", { count: "exact", head: true })
        .eq("ip", ip)
        .gte("created_at", windowStart);
      ipCount = count ?? 0;
    }

    // Logged whether or not the request is served. If a blocked attempt did
    // not extend the window, an attacker could simply keep hammering: every
    // rejection would fall out of the hour and the limit would never bite.
    await admin.from("activation_requests").insert({ identifier_hash: idHash, ip });

    if ((idCount ?? 0) >= MAX_PER_IDENTIFIER_PER_HOUR || ipCount >= MAX_PER_IP_PER_HOUR) {
      // Reveals only that a limit was hit — the same answer for a real
      // customer and for an address that has never existed.
      return json(
        {
          status: "rate_limited",
          message: "Too many activation requests. Please try again in an hour.",
        },
        429,
      );
    }

    const column = kind === "email" ? "email" : "phone";
    const { data: profile, error } = await admin
      .from("profiles")
      .select("id, email")
      .eq(column, normalized)
      .maybeSingle();

    if (error) {
      // Even an internal fault returns the generic body: an error that appears
      // only for real accounts is itself an enumeration oracle.
      console.error("profile lookup failed:", error.message);
      return json(GENERIC_OK, 200);
    }

    if (profile?.id && profile.email) {
      const result = await issueAndSend(admin, profile.id, profile.email);
      if (!result.ok) console.error("activation send failed:", result.detail);
    }

    return json(GENERIC_OK, 200);
  } catch (err) {
    console.error(
      "send-activation error:",
      err instanceof Error ? err.message : String(err),
    );
    // Report-only (Phase 9): the 500 below is unchanged. No identifier is
    // attached — this function's whole input is an email address or a phone
    // number, and none of it may reach Sentry.
    await captureFunctionError("send-activation", err);
    return json({ error: "activation request failed" }, 500);
  }
});
