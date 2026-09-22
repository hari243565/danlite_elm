// ══════════════════════════════════════════════════════════════════════════
// DOES THIS PAYMENT MATCH THE ORDER WE OPENED?
//
// Extracted out of razorpay-webhook/index.ts so it can be executed by a test
// rather than read by a reviewer. The webhook file imports Deno globals and
// jsr: specifiers, so nothing in it can be run under `node --test`; this
// module imports nothing, and the webhook calls it. The bytes the test
// exercises are the bytes that run in production.
//
// CURRENCY IS CHECKED SEPARATELY FROM AMOUNT, AND FIRST
// -----------------------------------------------------
// Until the international rail went live these were one `||` condition. The
// security property was already correct — a disagreement on either field
// refused to activate — but one condition yields one audit action, and with
// two currencies live the difference between "they paid the wrong number" and
// "they paid the right number in the wrong money" is a different incident
// with a different cause.
//
// The failure the split makes visible: a bare integer is not a price. 129 is
// $1.29 and it is also ₹1.29. An amount-only check compares integers and is
// blind to which of those it is looking at. On this product the two rails are
// 12_900 INR and 129 USD, so they do not collide today — but "today" is doing
// real work in that sentence, and the currency check removes the dependency
// on it entirely.
//
// Currency is evaluated first because it is the coarser fault. If the
// currency is wrong then comparing the amounts is comparing quantities of
// different things, and reporting that as an "amount mismatch" points whoever
// reads the audit row at the wrong question.
// ══════════════════════════════════════════════════════════════════════════

export type OrderMatchResult =
  | { ok: true; reason: null }
  | { ok: false; reason: "currency_mismatch" | "amount_mismatch" };

export type OrderMatchInput = {
  /** From the orders row — the witness that did not travel in the webhook body. */
  orderAmountMinor: number | string;
  orderCurrency: string;
  /** From the signed webhook payload. */
  paidAmountMinor: number;
  paidCurrency: string;
};

/**
 * Both fields must agree with the order row. Neither is taken on trust from
 * the payload alone.
 *
 * `orderAmountMinor` is typed to accept a string because `amount_minor` is a
 * Postgres bigint and PostgREST hands bigints back as strings once they
 * exceed the safe integer range. Number() here rather than at the callsite so
 * the coercion cannot be forgotten in one of two places.
 *
 * Currency comparison is exact and case-sensitive on purpose. Both the orders
 * and payments tables CHECK-constrain currency to ('INR','USD'), so a
 * lowercase 'usd' arriving from the gateway is a real anomaly worth refusing
 * rather than something to normalise away — normalising it would hide a
 * genuine change in what Razorpay sends.
 */
export function matchOrder(input: OrderMatchInput): OrderMatchResult {
  if (input.orderCurrency !== input.paidCurrency) {
    return { ok: false, reason: "currency_mismatch" };
  }
  if (Number(input.orderAmountMinor) !== input.paidAmountMinor) {
    return { ok: false, reason: "amount_mismatch" };
  }
  return { ok: true, reason: null };
}
