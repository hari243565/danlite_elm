// ══════════════════════════════════════════════════════════════════════════
// /create-order — asks Razorpay to open an order, and records it.
//
// THIS FUNCTION CANNOT ACTIVATE ANYTHING. It writes exactly one row, to
// public.orders, with status='created'. An order is a question ("will this
// person pay?"), never an answer. Only /razorpay-webhook — after an HMAC
// signature has verified against the raw request body — may write payments or
// licences.
//
// TRUST MODEL:
//   • Identity comes from the caller's verified Supabase Auth JWT. The user id
//     is NEVER taken from the request body; otherwise any signed-in user could
//     open an order in somebody else's name and have the webhook activate it.
//   • The AMOUNT is decided here, server-side, from the country stored in
//     public.profiles. The request body is not read at all. A client-chosen
//     amount is a client-chosen price.
//   • RAZORPAY_KEY_SECRET is used only to sign the outbound Basic auth header.
//     It is never returned, never logged, and never included in an error path.
//   • RAZORPAY_KEY_ID *is* returned. That is safe and unavoidable — Razorpay's
//     Checkout.js needs it in the browser to identify the account, and it can
//     authorise nothing on its own without the secret. It is returned in this
//     response only; it is not baked into any committed file.
// ══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";

// ── PRICE ─────────────────────────────────────────────────────────────────
// ₹109.00 in paise. Phase 5 is the India rail only.
//
// ⚠ THIS MUST STAY IN STEP WITH portal/lib/gst.ts.
// That module is the source of truth for what the customer is SHOWN; this
// constant is the source of truth for what the customer is CHARGED. They agree
// today because GST_TREATMENT is 'inclusive', which makes the total ₹109.
// If GST_TREATMENT is ever flipped to 'exclusive' the portal would display
// ₹128.62 while this function still charged ₹109 — a silent divergence between
// the price on screen and the price on the card. Flagged in phase5-report.json
// as an open item rather than left as a comment nobody reads.
const PRICE_MINOR_IN = 10_900;
const CURRENCY_IN = "INR";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/**
 * Razorpay caps `receipt` at 40 characters. Short, unique, and carrying no
 * PII — a user-id prefix plus a base36 timestamp, not an email.
 */
function buildReceipt(userId: string): string {
  return `dl_${userId.replaceAll("-", "").slice(0, 12)}_${
    Date.now().toString(36)
  }`;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  try {
    // ── 1. Authenticate ───────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return json({ error: "missing bearer token" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // getUser() validates signature and expiry server-side. We never decode
    // the JWT ourselves — a self-decoded token is a trusted token.
    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userErr } = await authClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "invalid or expired token" }, 401);
    }
    const userId = userData.user.id;

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // ── 2. Already licensed? ──────────────────────────────────────────────
    // Charging a customer twice for a one-time lifetime licence is a refund
    // request and a support ticket. Cheaper to refuse here.
    const { data: licence, error: licErr } = await admin
      .from("licences")
      .select("status")
      .eq("user_id", userId)
      .maybeSingle();

    if (licErr) {
      console.error("licence read failed:", licErr.message);
      return json({ error: "could not read licence status" }, 500);
    }
    if (licence?.status === "active") {
      return json({
        error: "already_licensed",
        message:
          "You already have a lifetime licence on this account. There is nothing more to pay.",
      }, 409);
    }

    // ── 3. Which rail? ────────────────────────────────────────────────────
    // country_code is read from profiles as the authority. It is not readable
    // from the request and the Phase 1 protect_profile_fields trigger prevents
    // the client changing it — country selects the price, so a client-editable
    // country would be a 99% discount.
    const { data: profile, error: profErr } = await admin
      .from("profiles")
      .select("country_code, email, phone")
      .eq("id", userId)
      .maybeSingle();

    if (profErr) {
      console.error("profile read failed:", profErr.message);
      return json({ error: "could not read profile" }, 500);
    }

    // Same fallback as the profiles table's own default, so the two cannot
    // disagree.
    const country = (profile?.country_code ?? "IN").toUpperCase();

    if (country !== "IN") {
      // A friendly 200, not an error: this is a supported state of the world
      // in Phase 5, not a failure. Phase 6 adds the international rail.
      return json({
        available: false,
        message: "International checkout is coming soon.",
      }, 200);
    }

    // ── 4. Open the order at Razorpay ─────────────────────────────────────
    const keyId = Deno.env.get("RAZORPAY_KEY_ID");
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!keyId || !keySecret) {
      // Specific in the log, vague to the caller, and the values themselves
      // never appear in either.
      console.error("RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET not configured");
      return json({ error: "payments are not configured" }, 500);
    }

    const rzpRes = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${btoa(`${keyId}:${keySecret}`)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: PRICE_MINOR_IN,
        currency: CURRENCY_IN,
        receipt: buildReceipt(userId),
        // notes are echoed back in the webhook payload. They are a
        // CONVENIENCE, not evidence: the webhook cross-checks this against the
        // orders row it looks up independently, and refuses to activate if the
        // two disagree.
        notes: { user_id: userId },
      }),
    });

    const rzpBody = await rzpRes.text();
    if (!rzpRes.ok) {
      // Razorpay's error body carries no credential material — it echoes the
      // request's field errors. Safe and useful to log.
      console.error(`razorpay order creation failed ${rzpRes.status}: ${rzpBody}`);
      return json({ error: "could not start checkout. Please try again." }, 502);
    }

    const order = JSON.parse(rzpBody) as {
      id: string;
      amount: number;
      currency: string;
    };

    if (!order?.id) {
      console.error("razorpay returned no order id");
      return json({ error: "could not start checkout. Please try again." }, 502);
    }

    // ── 5. Record it ──────────────────────────────────────────────────────
    // Written BEFORE the id is handed to the browser. If this insert fails we
    // must not proceed: the webhook's independent cross-check reads this row,
    // so an order that exists at Razorpay but not here would arrive as a
    // payment we refuse to honour. Failing now is recoverable (the customer
    // retries and has not paid); failing later is a paid customer with no
    // licence.
    const { error: ordErr } = await admin.from("orders").insert({
      user_id: userId,
      gateway_order_id: order.id,
      amount_minor: PRICE_MINOR_IN,
      currency: CURRENCY_IN,
      status: "created",
    });

    if (ordErr) {
      console.error(`order row insert failed for ${order.id}: ${ordErr.message}`);
      return json({ error: "could not start checkout. Please try again." }, 500);
    }

    // ── 6. Hand back only what Checkout.js needs ──────────────────────────
    return json({
      available: true,
      order_id: order.id,
      amount: PRICE_MINOR_IN,
      currency: CURRENCY_IN,
      key_id: keyId,
      prefill: {
        email: profile?.email ?? userData.user.email ?? "",
        contact: profile?.phone ?? userData.user.phone ?? "",
      },
    }, 200);
  } catch (err) {
    console.error(
      "create-order error:",
      err instanceof Error ? err.message : String(err),
    );
    return json({ error: "could not start checkout. Please try again." }, 500);
  }
});
