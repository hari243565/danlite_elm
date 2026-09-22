// ══════════════════════════════════════════════════════════════════════════
// /razorpay-webhook — THE SOLE GATE between "someone typed a card number" and
// "our database says they have paid".
//
// This endpoint is deployed with JWT verification DISABLED, because the caller
// is Razorpay, not a signed-in app user. Its authenticity therefore rests
// entirely on one thing: an HMAC-SHA256 signature verified against the RAW,
// UNTOUCHED request bytes, compared in constant time. If that check does not
// pass, this function does nothing at all.
//
// FOUR RULES, each of which has broken a real payment integration somewhere:
//
//   1. HASH THE RAW BYTES. Not JSON.stringify(JSON.parse(raw)). Re-serialising
//      reorders keys, changes number formatting and drops insignificant
//      whitespace, so the digest no longer matches the one Razorpay computed
//      over what it actually sent. This is THE classic failure of this class
//      of verification. Below, the body is read once as an ArrayBuffer and
//      those exact bytes are what get hashed; JSON parsing happens afterwards,
//      from the same bytes, and never feeds back into the digest.
//
//   2. COMPARE IN CONSTANT TIME. A byte-by-byte `===` on strings returns early
//      at the first difference, so response latency leaks how many leading
//      characters an attacker guessed correctly, one byte at a time. See
//      constantTimeEquals() below for the approach used and why.
//
//   3. DEDUPLICATE DELIVERIES. Razorpay retries. A replay must not create a
//      second payment row or move purchased_at. Guarded twice, independently:
//      delivery-level here via webhook_events(gateway, event_id), and
//      payment-level inside activate_licence_from_payment() via the
//      payments UNIQUE(gateway, gateway_payment_id) constraint.
//
//   4. ANSWER 2xx FOR ANYTHING YOU DO NOT ACT ON. A non-2xx tells Razorpay to
//      retry, forever, for an event we were never going to process.
//
// LOGGING POLICY: identifiers only — payment id, order id, event type. Never
// the secret, never the signature, never card / VPA / bank detail from the
// payload.
// ══════════════════════════════════════════════════════════════════════════

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { captureFunctionError } from "../_shared/sentry.ts";
import { assessBillingAddress } from "../_shared/avs.ts";
import { matchOrder } from "../_shared/order_match.ts";

const enc = new TextEncoder();

// ── hex ───────────────────────────────────────────────────────────────────
function toHex(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += b.toString(16).padStart(2, "0");
  return s;
}

async function hmacSha256(keyBytes: Uint8Array, msg: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, msg));
}

/**
 * Constant-time string equality.
 *
 * Deno's crypto.subtle exposes no timing-safe comparison the way Node's
 * crypto.timingSafeEqual does, and Node's would reject unequal lengths by
 * throwing — which is itself an early exit that leaks the expected length.
 *
 * APPROACH USED: **double HMAC**, then an XOR-accumulate full pass.
 *
 * Both operands are HMAC'd under a 32-byte key generated freshly from the CSPRNG
 * for this one comparison. That gives two digests which are:
 *   • always exactly 32 bytes, whatever the inputs' lengths — so there is no
 *     length branch anywhere, and a wrong-length signature costs precisely the
 *     same time as a right-length one. Nothing about the expected value's
 *     length is observable;
 *   • unpredictable to an attacker, who does not know this request's nonce —
 *     so even a perfect timing oracle on the loop below reveals nothing usable
 *     about the real digest.
 *
 * The comparison itself then XORs all 32 byte pairs, OR-ing the differences
 * into an accumulator and testing it only after the full pass. No `break`, no
 * early `return`: the loop takes the same time whether the first byte differs
 * or none of them do.
 */
async function constantTimeEquals(a: string, b: string): Promise<boolean> {
  const nonce = crypto.getRandomValues(new Uint8Array(32));
  const ha = await hmacSha256(nonce, enc.encode(a));
  const hb = await hmacSha256(nonce, enc.encode(b));

  let diff = 0;
  for (let i = 0; i < 32; i++) diff |= ha[i] ^ hb[i];
  return diff === 0;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * What we persist into payments.raw_payload.
 *
 * DELIBERATELY NOT THE WHOLE ENTITY. `card`, `token_id`, `vpa`, `upi` and
 * `acquirer_data` carry instrument detail — last four digits, network, issuer,
 * a UPI handle — that reconciliation never needs and that this system has no
 * reason to keep a second copy of. Everything required to reconcile a line
 * against a Razorpay settlement report is retained.
 */
function redactPaymentEntity(
  e: Record<string, unknown>,
  eventId: string,
  eventType: string,
): Record<string, unknown> {
  return {
    id: e.id,
    order_id: e.order_id,
    amount: e.amount,
    currency: e.currency,
    status: e.status,
    // The method NAME ('card', 'upi', 'netbanking') is reconciliation-relevant
    // and carries no instrument detail. The method's own sub-object does, and
    // is not copied.
    method: e.method,
    fee: e.fee,
    tax: e.tax,
    captured: e.captured,
    created_at: e.created_at,
    notes: e.notes,
    _webhook: { event_id: eventId, event_type: eventType },
  };
}

/** Best-effort audit write. Never allowed to fail the request. */
async function audit(
  admin: SupabaseClient,
  userId: string | null,
  action: string,
  detail: Record<string, unknown>,
): Promise<void> {
  const { error } = await admin.from("audit_log").insert({
    user_id: userId,
    action,
    detail,
  });
  if (error) console.error(`audit_log insert failed (${action}): ${error.message}`);
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  // ════════════════════════════════════════════════════════════════════════
  // STEP 1 — RAW BYTES FIRST. Before any parsing, of any kind.
  // ════════════════════════════════════════════════════════════════════════
  const rawBytes = new Uint8Array(await req.arrayBuffer());

  const signature = req.headers.get("x-razorpay-signature");
  const eventId = req.headers.get("x-razorpay-event-id");

  const secret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
  if (!secret) {
    // Fail CLOSED. A missing secret must never degrade into "skip the check".
    console.error("RAZORPAY_WEBHOOK_SECRET not configured — refusing all webhooks");
    return json({ error: "webhook not configured" }, 500);
  }

  if (!signature) {
    console.warn("webhook rejected: no x-razorpay-signature header");
    return json({ error: "missing signature" }, 400);
  }

  // ════════════════════════════════════════════════════════════════════════
  // STEP 2 — VERIFY. Nothing below this point runs on an unverified body.
  // ════════════════════════════════════════════════════════════════════════
  const expectedHex = toHex(await hmacSha256(enc.encode(secret), rawBytes));

  if (!(await constantTimeEquals(expectedHex, signature))) {
    // No detail to the caller and no digest in the log. A verification
    // failure is either a misconfiguration or an attack; neither is owed an
    // explanation, and echoing either digest would hand an attacker the
    // oracle the constant-time compare exists to deny them.
    console.warn(
      `webhook rejected: signature mismatch (event_id=${eventId ?? "none"})`,
    );
    return json({ error: "invalid signature" }, 400);
  }

  // ── From here the body is authentic. ─────────────────────────────────────

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  // Available to Edge Functions automatically — deliberately NOT added as a
  // manually managed secret.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ════════════════════════════════════════════════════════════════════════
  // STEP 3 — PARSE (from the same bytes; the digest is already computed and
  // is never recomputed from this parsed object).
  // ════════════════════════════════════════════════════════════════════════
  let body: {
    event?: string;
    payload?: Record<string, { entity?: Record<string, unknown> }>;
  };
  try {
    body = JSON.parse(new TextDecoder().decode(rawBytes));
  } catch {
    // Signed but unparseable. 400 without a retry loop is right: a redelivery
    // of the same malformed bytes will fail identically.
    console.error("webhook body verified but is not valid JSON");
    return json({ error: "malformed body" }, 400);
  }

  const eventType = body.event ?? "unknown";

  // ════════════════════════════════════════════════════════════════════════
  // STEP 4 — DELIVERY-LEVEL IDEMPOTENCY.
  //
  // Claim the event id BEFORE processing, so that two concurrent deliveries
  // of the same event cannot both proceed — the UNIQUE(gateway, event_id)
  // constraint decides the winner atomically, rather than a check-then-act
  // that both would pass.
  //
  // Missing header: process anyway. Razorpay documents x-razorpay-event-id on
  // every delivery, but the payment-level guard inside
  // activate_licence_from_payment() is independent and sufficient, and
  // refusing a genuine payment over a missing convenience header would be the
  // worse failure.
  // ════════════════════════════════════════════════════════════════════════
  let claimed = false;
  if (eventId) {
    const { error: claimErr } = await admin
      .from("webhook_events")
      .insert({ gateway: "razorpay", event_id: eventId, event_type: eventType });

    if (claimErr) {
      if (claimErr.code === "23505") {
        // Unique violation: already delivered. Return fast and do nothing.
        console.log(`webhook redelivery ignored (event_id=${eventId}, ${eventType})`);
        return json({ status: "already_processed" }, 200);
      }
      console.error(`webhook_events claim failed: ${claimErr.message}`);
      return json({ error: "could not record event" }, 500);
    }
    claimed = true;
  }

  /**
   * Release the claim so Razorpay's retry is not silently swallowed as a
   * duplicate. Without this, a transient failure after the claim would
   * suppress every retry and a paying customer would never be activated —
   * the worst failure mode this system has.
   */
  async function releaseClaim(): Promise<void> {
    if (!claimed || !eventId) return;
    const { error } = await admin
      .from("webhook_events")
      .delete()
      .eq("gateway", "razorpay")
      .eq("event_id", eventId);
    if (error) {
      console.error(
        `CRITICAL: could not release webhook claim ${eventId}; retries will be ` +
          `suppressed and this event needs manual replay: ${error.message}`,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // STEP 5 — ACT.
  // ════════════════════════════════════════════════════════════════════════
  try {
    switch (eventType) {
      // ── The only event that may ever activate a licence ─────────────────
      case "payment.captured": {
        const e = body.payload?.payment?.entity as
          | Record<string, unknown>
          | undefined;

        if (!e?.id) {
          console.error(`payment.captured with no payment entity (${eventId})`);
          await audit(admin, null, "webhook.malformed", { event: eventType, eventId });
          return json({ status: "ignored_malformed" }, 200);
        }

        const paymentId = String(e.id);
        const orderId = e.order_id ? String(e.order_id) : null;
        const amount = Number(e.amount);
        const currency = String(e.currency);
        const notesUserId =
          (e.notes as Record<string, unknown> | undefined)?.user_id;

        if (!orderId) {
          // A payment with no order cannot be tied to a purchase we opened.
          console.error(`payment.captured with no order_id (payment=${paymentId})`);
          await audit(admin, null, "webhook.payment_without_order", { paymentId });
          return json({ status: "ignored_no_order" }, 200);
        }

        // ── Second, INDEPENDENT witness ──────────────────────────────────
        // notes travel inside the webhook body. This row does not. Requiring
        // both to agree means a forged activation would need a valid HMAC AND
        // agreement with a row the attacker can neither see nor influence.
        const { data: order, error: ordErr } = await admin
          .from("orders")
          // billing_country is read from the ORDER ROW, never from the
          // webhook's notes. The row is the witness the attacker cannot see
          // or influence; the notes travel in the body they control.
          .select("user_id, amount_minor, currency, status, billing_country")
          .eq("gateway_order_id", orderId)
          .maybeSingle();

        if (ordErr) {
          console.error(`order lookup failed for ${orderId}: ${ordErr.message}`);
          await releaseClaim();
          return json({ error: "order lookup failed" }, 500);
        }

        if (!order) {
          console.error(
            `payment.captured for unknown order (payment=${paymentId}, order=${orderId})`,
          );
          await audit(admin, null, "webhook.unknown_order", { paymentId, orderId });
          // 200: deliberate refusal, not a transient fault. Retrying will
          // never make this order exist.
          return json({ status: "ignored_unknown_order" }, 200);
        }

        // Disagreement between the two witnesses -> log loudly, activate
        // NOTHING. Explicitly required by the phase brief.
        if (notesUserId && String(notesUserId) !== String(order.user_id)) {
          console.error(
            `DISCREPANCY: notes.user_id != orders.user_id ` +
              `(payment=${paymentId}, order=${orderId}) — not activating`,
          );
          await audit(admin, order.user_id as string, "webhook.user_mismatch", {
            paymentId,
            orderId,
            notes_user_id: String(notesUserId),
            order_user_id: String(order.user_id),
          });
          return json({ status: "ignored_user_mismatch" }, 200);
        }

        // ── Amount and currency, checked SEPARATELY ──────────────────────
        // These were one `||` condition until the international rail went
        // live. The security property was already correct — a mismatch on
        // either field refused to activate — but a single condition with a
        // single audit action cannot tell you WHICH field disagreed, and with
        // two currencies in play that distinction now matters operationally.
        //
        // A bare number is not a price. 129 is $1.29 and it is also ₹1.29,
        // and the difference between them is a factor of about 88. The
        // failure this splits out is a payment captured for the right NUMBER
        // in the wrong CURRENCY — which is exactly what a misconfigured rail,
        // a currency-conversion plugin, or a crafted webhook aimed at the new
        // path would produce, and which the amount check alone would wave
        // through if the minor units happened to line up. On this product
        // they do line up: PRICE_MINOR.IN is 12_900 and PRICE_MINOR.INTL is
        // 129, so a $129.00 capture against a ₹129.00 order agrees on
        // neither, but a $1.29 capture against a ₹1.29 order would agree on
        // both. The currency check is what makes that unrepresentable.
        //
        // Ordered currency-first because currency is the coarser error: if
        // the currency is wrong the amount comparison is meaningless anyway,
        // and reporting "amount mismatch" for what is really a currency fault
        // sends whoever reads the audit row looking in the wrong place.
        //
        // The comparison itself lives in ../_shared/order_match.ts so that
        // both directions of it are executed by a test instead of reviewed by
        // eye. The branches below turn its verdict into the log line, the
        // audit action and the response — that shaping is what stays here.
        const match = matchOrder({
          orderAmountMinor: order.amount_minor as number | string,
          orderCurrency: order.currency as string,
          paidAmountMinor: amount,
          paidCurrency: currency,
        });

        if (match.reason === "currency_mismatch") {
          console.error(
            `DISCREPANCY: currency mismatch (payment=${paymentId}, ` +
              `order=${orderId}, expected=${order.currency}, got=${currency}) ` +
              `— not activating`,
          );
          await audit(admin, order.user_id as string, "webhook.currency_mismatch", {
            paymentId,
            orderId,
            expected_currency: order.currency,
            received_currency: currency,
            expected_amount_minor: order.amount_minor,
            received_amount_minor: amount,
          });
          return json({ status: "ignored_currency_mismatch" }, 200);
        }

        if (match.reason === "amount_mismatch") {
          console.error(
            `DISCREPANCY: amount mismatch (payment=${paymentId}, ` +
              `order=${orderId}, expected=${order.amount_minor} ${order.currency}, ` +
              `got=${amount} ${currency}) — not activating`,
          );
          await audit(admin, order.user_id as string, "webhook.amount_mismatch", {
            paymentId,
            orderId,
            expected_amount_minor: order.amount_minor,
            expected_currency: order.currency,
            received_amount_minor: amount,
            received_currency: currency,
          });
          return json({ status: "ignored_amount_mismatch" }, 200);
        }

        // ── The one call that activates. Atomic, idempotent, service_role. ──
        const { data: result, error: rpcErr } = await admin.rpc(
          "activate_licence_from_payment",
          {
            p_user_id: order.user_id,
            p_gateway_order_id: orderId,
            p_gateway_payment_id: paymentId,
            p_amount_minor: amount,
            p_currency: currency,
            p_raw_payload: redactPaymentEntity(e, eventId ?? "", eventType),
          },
        );

        if (rpcErr) {
          console.error(
            `activation RPC failed (payment=${paymentId}): ${rpcErr.message}`,
          );
          await releaseClaim();
          // 500 so Razorpay retries — the customer HAS paid.
          return json({ error: "activation failed" }, 500);
        }

        const row = Array.isArray(result) ? result[0] : result;
        console.log(
          `payment.captured processed (payment=${paymentId}, order=${orderId}, ` +
            `already_processed=${row?.already_processed})`,
        );

        // ── AVS, assessed AFTER the licence is already active ────────────
        // Position is the guarantee. This runs downstream of the only call
        // that activates anything, and its result is not read by any branch.
        // There is therefore no arrangement of billing address, card country
        // or AVS verdict that can stop a customer who has paid from being
        // licensed — the soft-signal promise is enforced by control flow, not
        // by remembering not to write an `if`.
        //
        // This is also the first point at which the comparison is possible at
        // all: `payment.card.country` is the issuing country, and it does not
        // exist until a card has actually been presented.
        //
        // Wrapped because an audit write must never turn a successful
        // activation into a 500 that makes Razorpay redeliver a payment we
        // have already honoured.
        try {
          const avs = assessBillingAddress({
            billingCountry: order.billing_country as string | null,
            cardCountry:
              (e.card as Record<string, unknown> | undefined)?.country as
                | string
                | undefined,
          });
          if (avs.signal !== "not_provided") {
            await audit(admin, order.user_id as string, "webhook.avs_signal", {
              paymentId,
              orderId,
              signal: avs.signal,
              flagged: avs.flagged,
              coverage: avs.coverage,
              note: avs.note,
              // Stated in the row itself so nobody reading this audit trail
              // later has to go and check whether it gated anything.
              enforced: false,
            });
          }
        } catch (avsErr) {
          console.error(
            "avs assessment failed (non-fatal):",
            avsErr instanceof Error ? avsErr.message : String(avsErr),
          );
        }

        return json({
          status: row?.already_processed ? "already_processed" : "activated",
          invoice_no: row?.invoice_no ?? null,
        }, 200);
      }

      // ── Visibility only. Touches neither payments nor licences. ─────────
      case "payment.failed": {
        const e = body.payload?.payment?.entity as
          | Record<string, unknown>
          | undefined;
        const paymentId = e?.id ? String(e.id) : null;
        const orderId = e?.order_id ? String(e.order_id) : null;

        console.log(`payment.failed (payment=${paymentId}, order=${orderId})`);
        await audit(admin, null, "webhook.payment_failed", {
          paymentId,
          orderId,
          // error_description is Razorpay's own customer-safe string
          // ("payment processing cancelled by user"). No instrument detail.
          reason: e?.error_description ?? null,
          code: e?.error_code ?? null,
        });
        return json({ status: "logged" }, 200);
      }

      // ── Refund -> revoke. Both event names handled: which one a given
      //    account emits depends on dashboard configuration, and the
      //    payment-level guard makes handling both harmless (the second is a
      //    no-op re-revocation of an already-revoked licence).
      case "refund.created":
      case "refund.processed": {
        const r = body.payload?.refund?.entity as
          | Record<string, unknown>
          | undefined;

        const paymentId = r?.payment_id ? String(r.payment_id) : null;
        if (!paymentId) {
          console.error(`${eventType} with no payment_id (${eventId})`);
          await audit(admin, null, "webhook.refund_without_payment", { eventType });
          return json({ status: "ignored_malformed" }, 200);
        }

        const reason =
          `${eventType} refund_id=${r?.id ?? "unknown"} amount_minor=${r?.amount ?? "unknown"}`;

        const { data: revoked, error: rpcErr } = await admin.rpc(
          "revoke_licence_from_refund",
          { p_gateway_payment_id: paymentId, p_reason: reason },
        );

        if (rpcErr) {
          console.error(`revoke RPC failed (payment=${paymentId}): ${rpcErr.message}`);
          await releaseClaim();
          return json({ error: "revocation failed" }, 500);
        }

        console.log(
          `${eventType} processed (payment=${paymentId}, revoked=${revoked})`,
        );

        // ── AUDIT THE REVOCATION ─────────────────────────────────────────
        // Added by the 2026-09-19 security audit. Every OTHER consequential
        // path through this function already writes an audit_log row —
        // malformed bodies, unknown orders, user mismatches, amount
        // mismatches, failed payments — and so does every admin action
        // (admin.licence_revoked, admin.force_signout). The one path that
        // takes paid access away automatically did not, which made it the
        // least investigable event in the system despite being the most
        // consequential.
        //
        // licences.revoked_at / revoke_reason were the only durable record,
        // and activate_licence_from_payment() CLEARS both on a later
        // purchase — by design, so an active row does not also read as
        // revoked. The effect was that buy -> refund -> buy again erased the
        // evidence that the refund cycle ever happened, leaving only
        // payments.status='refunded' and a function log with short retention.
        //
        // Best-effort, exactly like every other audit() call here: it is
        // placed AFTER the RPC and cannot change the outcome, the status code
        // or the response. A failed audit write must never turn a processed
        // refund into a Razorpay retry.
        //
        // Identifiers only, per this function's logging policy: payment id,
        // refund id, event type, and the amount already stored on the
        // payments row. No card, VPA, bank or customer detail.
        //
        // The affected user is resolved for the audit row specifically
        // because audit_log.user_id is what admin-audit-log filters and
        // joins on to show an email — a null there would make the entry
        // unfindable from the one tool built to read this trail. Read after
        // the RPC (the payments row exists either way), and its failure is
        // swallowed into a null rather than allowed to affect the response.
        const { data: refundedPayment } = await admin
          .from("payments")
          .select("user_id")
          .eq("gateway", "razorpay")
          .eq("gateway_payment_id", paymentId)
          .maybeSingle();

        await audit(admin, (refundedPayment?.user_id as string) ?? null, "webhook.refund_revocation", {
          eventType,
          eventId,
          paymentId,
          refundId: r?.id ?? null,
          refundAmountMinor: r?.amount ?? null,
          // false === "no such payment on record"; true === handled, which
          // includes an already-refunded payment the idempotency guard
          // correctly declined to re-process.
          licenceRevoked: revoked === true,
        });
        // revoked === false means "no such payment on record" — a real and
        // acceptable state (e.g. a dashboard refund of a payment this system
        // never captured). 200 either way; retrying would not change it.
        return json({ status: revoked ? "revoked" : "no_matching_payment" }, 200);
      }

      // ── Everything else: acknowledged, not acted on. ────────────────────
      default: {
        console.log(`webhook event ignored: ${eventType} (event_id=${eventId})`);
        return json({ status: "ignored", event: eventType }, 200);
      }
    }
  } catch (err) {
    console.error(
      `webhook handler error (${eventType}):`,
      err instanceof Error ? err.message : String(err),
    );
    await releaseClaim();
    // Report-only (Phase 9), and deliberately AFTER releaseClaim(): the
    // idempotency claim must be released before anything that can block, and
    // the flush inside captureFunctionError waits up to 2s. The 500 below is
    // unchanged. `eventType` is Razorpay's event name (e.g. "payment.captured")
    // — not a customer identifier.
    await captureFunctionError("razorpay-webhook", err, { event: eventType });
    return json({ error: "handler error" }, 500);
  }
});
