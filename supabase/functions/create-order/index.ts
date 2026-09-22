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
//     public.profiles, via railFor() in ../_shared/intl_pricing.ts. A
//     client-chosen amount is a client-chosen price. This holds identically on
//     both rails — see "WHAT THE BODY MAY AND MAY NOT DO" below.
//   • RAZORPAY_KEY_SECRET is used only to sign the outbound Basic auth header.
//     It is never returned, never logged, and never included in an error path.
//   • RAZORPAY_KEY_ID *is* returned. That is safe and unavoidable — Razorpay's
//     Checkout.js needs it in the browser to identify the account, and it can
//     authorise nothing on its own without the secret. It is returned in this
//     response only; it is not baked into any committed file.
//
// ── WHAT THE BODY MAY AND MAY NOT DO (new with the international rail) ────
// This function used not to read the request body at all, and that was the
// cleanest possible statement of "the client cannot influence the price".
// The international rail needs a billing address, which by its nature the
// customer has to type, so the body is now read. The guarantee is preserved
// structurally rather than by care:
//
//   • `railFor()` takes ONE argument, a country code, and there is no
//     overload that accepts an amount. The body is never in scope when the
//     amount is chosen.
//   • The country passed to it comes from profiles.country_code under the
//     service role. The Phase 1 protect_profile_fields trigger silently
//     reverts any client attempt to change it.
//   • The three fields read from the body — billing_country,
//     billing_postal_code, bot_token — are written to the order row as
//     evidence and passed to the soft-signal assessors. None of them is read
//     by any code that computes money, and none of them can cause a refusal.
//
// The adversarial cases for all of that live in
// ../_shared/intl_pricing.test.ts and run under `node --test`.
//
// ── THE DOMESTIC RAIL IS UNCHANGED ───────────────────────────────────────
// The India branch below opens the same order, for the same 12_900 INR, with
// the same receipt, the same notes and the same response shape it did before
// this file learned about a second rail. It does not touch the new rate-limit
// ledger, does not read the billing address, and leaves the three new
// orders columns NULL. Deliberate: the international rail's risk profile is
// genuinely different and the controls added for it are not free, so they are
// not imposed on a path that does not need them.
// ══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { captureFunctionError } from "../_shared/sentry.ts";
import { type Rail, railFor, taxFor } from "../_shared/intl_pricing.ts";
import {
  BURST_WINDOW_MS,
  decideIntlOrderLimit,
  HOUR_WINDOW_MS,
  RATE_LIMITED_MESSAGE,
} from "../_shared/intl_rate_limit.ts";
import { assessBillingAddress, normalizeCountry } from "../_shared/avs.ts";
import {
  assessBotScore,
  type BotAssessment,
  CHECKOUT_ACTION,
  parseEnterpriseAssessment,
} from "../_shared/bot_score.ts";

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

/**
 * Same header order as /send-activation, so the two agree on what "the
 * client's IP" means. cf-connecting-ip first because it is set by the edge
 * and cannot be spoofed by the caller; x-forwarded-for is a fallback and its
 * FIRST entry is the original client.
 */
function clientIp(req: Request): string | null {
  return req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    null;
}

/**
 * The request body, read defensively.
 *
 * Every field is optional and every field is untrusted. A body that is
 * absent, empty, not JSON, or JSON of the wrong shape yields all-nulls and
 * the request proceeds — because none of this is required to take a payment,
 * and failing a real customer's checkout over a malformed optional field
 * would be the false-decline mistake this whole path is trying to avoid.
 */
async function readBody(req: Request): Promise<{
  billingCountry: string | null;
  billingPostalCode: string | null;
  botToken: string | null;
  deviceHash: string | null;
}> {
  let raw: Record<string, unknown> = {};
  try {
    const text = await req.text();
    if (text.trim()) {
      const parsed = JSON.parse(text);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        raw = parsed as Record<string, unknown>;
      }
    }
  } catch {
    // Not JSON. Treated exactly like an absent body.
  }

  const str = (v: unknown, max: number): string | null => {
    if (typeof v !== "string") return null;
    const t = v.trim();
    return t.length > 0 && t.length <= max ? t : null;
  };

  return {
    // Normalised to the ISO alpha-2 the CHECK constraint on
    // orders.billing_country accepts. Anything else becomes null rather than
    // failing the insert — "US of A" is a typo, not an attack.
    billingCountry: normalizeCountry(str(raw.billing_country, 64)) || null,
    billingPostalCode: str(raw.billing_postal_code, 32),
    botToken: str(raw.bot_token, 4096),
    deviceHash: str(raw.device_hash, 128),
  };
}

/**
 * Score the payment-submission action with reCAPTCHA Enterprise.
 *
 * ⚠ RETURNS "not configured" TODAY. No reCAPTCHA Enterprise project exists on
 * this account yet; RECAPTCHA_PROJECT_ID / RECAPTCHA_API_KEY /
 * RECAPTCHA_SITE_KEY are unset, so this fails open and every caller is
 * allowed. That is the only safe default — an unconfigured anti-fraud control
 * that silently refused payments would be an outage wearing a fraud policy's
 * clothes. The moment the three secrets are set, the assessment goes live
 * with no code change.
 *
 * Note the catch: a provider outage returns "no signal", never "bot". Google
 * being down is not evidence about our customer.
 */
async function scoreCheckout(
  botToken: string | null,
): Promise<BotAssessment> {
  const projectId = Deno.env.get("RECAPTCHA_PROJECT_ID");
  const apiKey = Deno.env.get("RECAPTCHA_API_KEY");
  const siteKey = Deno.env.get("RECAPTCHA_SITE_KEY");

  if (!projectId || !apiKey || !siteKey) {
    return assessBotScore({ configured: false });
  }
  if (!botToken) {
    return assessBotScore({ configured: true, assessment: null });
  }

  try {
    const res = await fetch(
      `https://recaptchaenterprise.googleapis.com/v1/projects/${projectId}/assessments?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          event: {
            token: botToken,
            siteKey,
            expectedAction: CHECKOUT_ACTION,
          },
        }),
      },
    );
    if (!res.ok) {
      console.error(`recaptcha assessment failed ${res.status}`);
      return assessBotScore({ configured: true, assessment: null });
    }
    return assessBotScore({
      configured: true,
      assessment: parseEnterpriseAssessment(await res.json()),
    });
  } catch (e) {
    console.error(
      "recaptcha assessment unreachable:",
      e instanceof Error ? e.message : String(e),
    );
    return assessBotScore({ configured: true, assessment: null });
  }
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

    // THE amount decision. One call, one argument, and that argument came
    // from the database. Everything downstream uses `pricing.amountMinor` and
    // `pricing.currency`; no other amount exists in this function's scope.
    const pricing = railFor(country);
    const rail: Rail = pricing.rail;
    const tax = taxFor(rail, pricing.amountMinor);

    // ── 4. International-only controls ────────────────────────────────────
    // Read the body ONLY on the international rail. On the domestic rail the
    // body is still never read, so the domestic path's "the request body is
    // not read at all" property survives this change intact.
    let body = {
      billingCountry: null as string | null,
      billingPostalCode: null as string | null,
      botToken: null as string | null,
      deviceHash: null as string | null,
    };
    let bot: BotAssessment = {
      verdict: "allow",
      score: null,
      note: "Domestic rail — not assessed.",
    };
    let avs = assessBillingAddress({});

    if (rail === "INTL") {
      body = await readBody(req);
      const ip = clientIp(req);

      // Scored BEFORE the limiter, because a `throttle` verdict is an input
      // to the limiter rather than a veto of its own. See bot_score.ts.
      bot = await scoreCheckout(body.botToken);

      // AVS at this point can only compare against what we already know; the
      // card's issuing country does not exist until the payment is attempted.
      // The webhook re-assesses with `payment.card.country` in hand, which is
      // where the real comparison happens.
      avs = assessBillingAddress({ billingCountry: body.billingCountry });

      const now = Date.now();
      const burstStart = new Date(now - BURST_WINDOW_MS).toISOString();
      const hourStart = new Date(now - HOUR_WINDOW_MS).toISOString();

      // Counted BEFORE this attempt is logged, so the thresholds read as
      // "they have already had N goes".
      const countWhere = async (
        column: "ip" | "user_id",
        value: string,
        since: string,
      ): Promise<number> => {
        const { count } = await admin
          .from("intl_order_attempts")
          .select("id", { count: "exact", head: true })
          .eq(column, value)
          .gte("created_at", since);
        return count ?? 0;
      };

      // An absent IP cannot be counted against an IP window. It is NOT
      // treated as a shared bucket: lumping every unknown-IP caller together
      // would let one abuser lock out every other customer whose IP header
      // happened to be missing. The per-account limit still applies.
      const ipBurst = ip ? await countWhere("ip", ip, burstStart) : 0;
      const ipHour = ip ? await countWhere("ip", ip, hourStart) : 0;
      const userHour = await countWhere("user_id", userId, hourStart);

      const decision = decideIntlOrderLimit({
        // The one consequence a low bot score has: it spends budget faster.
        // It cannot refuse on its own, and at +1 it cannot turn a first
        // legitimate attempt into a refusal either.
        ipBurst: ipBurst + (bot.verdict === "throttle" ? 1 : 0),
        ipHour,
        userHour,
      });

      // Logged whether or not the attempt is served. A refused attempt that
      // did not extend the window would make the limit unreachable — every
      // rejection would age out and the attacker could hammer forever.
      await admin.from("intl_order_attempts").insert({
        user_id: userId,
        ip,
        device_hash: body.deviceHash,
        outcome: decision.allowed ? "allowed" : "rate_limited",
      });

      if (!decision.allowed) {
        console.warn(
          `intl order rate-limited (user=${userId}, rule=${decision.rule})`,
        );
        // 429 with a uniform message. Which rule tripped is in the log and
        // the ledger, not in the response — telling the caller which axis
        // they exhausted tells them which one to rotate.
        return json(
          { available: false, error: "rate_limited", message: RATE_LIMITED_MESSAGE },
          429,
        );
      }
    }

    // ── 5. Open the order at Razorpay ─────────────────────────────────────
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
        amount: pricing.amountMinor,
        currency: pricing.currency,
        receipt: buildReceipt(userId),
        // notes are echoed back in the webhook payload. They are a
        // CONVENIENCE, not evidence: the webhook cross-checks this against the
        // orders row it looks up independently, and refuses to activate if the
        // two disagree.
        //
        // On the international rail the billing country rides along so it
        // appears in Razorpay's own dashboard next to the payment, where
        // whoever is fighting a chargeback will actually look for it. It is
        // evidence, not input — the webhook reads the ORDER ROW for it, never
        // the notes.
        //
        // A DOMESTIC order's notes are `{ user_id }` and nothing else, byte
        // for byte what they were before this file learned about a second
        // rail. Not because an extra note would break anything, but because
        // "the domestic path is unchanged" should be checkable by reading
        // this object rather than by reasoning about what the webhook happens
        // to ignore.
        notes: rail === "INTL"
          ? {
            user_id: userId,
            rail,
            ...(body.billingCountry
              ? { billing_country: body.billingCountry }
              : {}),
          }
          : { user_id: userId },
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

    // ── 6. Record it ──────────────────────────────────────────────────────
    // Written BEFORE the id is handed to the browser. If this insert fails we
    // must not proceed: the webhook's independent cross-check reads this row,
    // so an order that exists at Razorpay but not here would arrive as a
    // payment we refuse to honour. Failing now is recoverable (the customer
    // retries and has not paid); failing later is a paid customer with no
    // licence.
    //
    // amount_minor and currency are written from `pricing`, the same object
    // that was sent to Razorpay — so the row the webhook cross-checks against
    // and the order Razorpay holds are derived from one value, not two that
    // have to be kept in step.
    //
    // The three risk columns are attached ONLY on the international rail. A
    // domestic insert names the same five columns it always has, so the new
    // columns take their table defaults (NULL, NULL, '{}') exactly as every
    // domestic order written before this migration did.
    const { error: ordErr } = await admin.from("orders").insert({
      user_id: userId,
      gateway_order_id: order.id,
      amount_minor: pricing.amountMinor,
      currency: pricing.currency,
      status: "created",
      ...(rail === "INTL"
        ? {
          billing_country: body.billingCountry,
          billing_postal_code: body.billingPostalCode,
          risk_signals: {
            rail,
            tax_code: tax.code,
            avs: {
              signal: avs.signal,
              flagged: avs.flagged,
              coverage: avs.coverage,
            },
            bot: { verdict: bot.verdict, score: bot.score },
          },
        }
        : {}),
    });

    if (ordErr) {
      console.error(`order row insert failed for ${order.id}: ${ordErr.message}`);
      return json({ error: "could not start checkout. Please try again." }, 500);
    }

    // ── 7. Hand back only what Checkout.js needs ──────────────────────────
    return json({
      available: true,
      order_id: order.id,
      amount: pricing.amountMinor,
      currency: pricing.currency,
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
    // Report-only (Phase 9): the 500 and its message below are unchanged.
    // No order id is attached — `order` is declared inside the try block and is
    // deliberately not hoisted, because hoisting it would be a change to the
    // business logic this phase is not permitted to make.
    await captureFunctionError("create-order", err);
    return json({ error: "could not start checkout. Please try again." }, 500);
  }
});
