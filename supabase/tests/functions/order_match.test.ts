// ══════════════════════════════════════════════════════════════════════════
// ADVERSARIAL TESTS — the webhook's amount AND currency cross-check.
//
// The brief asks for the two crafted mismatches to be tested INDEPENDENTLY:
//   • right amount, wrong currency
//   • wrong amount, right currency
// Both are below, and both are asserted to name the correct fault rather than
// merely to fail — a currency fault reported as an amount fault sends
// whoever reads the audit row looking in the wrong place.
//
// Worth recording honestly: the SECURITY property here was already correct
// before this change. razorpay-webhook compared both fields in a single `||`
// condition, so a crafted webhook with a mismatched currency already failed
// to activate anything. What was missing was the ability to tell the two
// faults apart, which matters now that two currencies are live. The tests
// below therefore pin a property that already held, and a distinction that
// did not.
// ══════════════════════════════════════════════════════════════════════════

import { test } from "node:test";
import assert from "node:assert/strict";

import { matchOrder } from "../../functions/_shared/order_match.ts";
import { PRICE_MINOR } from "../../functions/_shared/intl_pricing.ts";

// ── THE HAPPY PATHS ──────────────────────────────────────────────────────

test("a genuine international capture matches its order", () => {
  const r = matchOrder({
    orderAmountMinor: PRICE_MINOR.INTL,
    orderCurrency: "USD",
    paidAmountMinor: PRICE_MINOR.INTL,
    paidCurrency: "USD",
  });
  assert.equal(r.ok, true);
  assert.equal(r.reason, null);
});

test("a genuine domestic capture matches its order — unchanged behaviour", () => {
  const r = matchOrder({
    orderAmountMinor: PRICE_MINOR.IN,
    orderCurrency: "INR",
    paidAmountMinor: PRICE_MINOR.IN,
    paidCurrency: "INR",
  });
  assert.equal(r.ok, true);
});

// ── CRAFTED MISMATCH 1: RIGHT AMOUNT, WRONG CURRENCY ─────────────────────
//
// ATTACK: a forged (or misrouted) webhook claiming a capture of 129 — the
// correct minor-unit amount for the $1.29 order — but denominated in INR.
// 129 paise is about one and a half US cents. An amount-only check compares
// integers and cannot see the difference.

test("right amount, WRONG currency is rejected as a currency mismatch", () => {
  const r = matchOrder({
    orderAmountMinor: PRICE_MINOR.INTL, // 129, order was in USD
    orderCurrency: "USD",
    paidAmountMinor: 129, // the same integer...
    paidCurrency: "INR", // ...but ₹1.29, not $1.29
  });

  assert.equal(r.ok, false);
  assert.equal(
    r.reason,
    "currency_mismatch",
    "this must be named a currency fault, not an amount fault",
  );
});

test("the reverse direction too — a USD claim against an INR order", () => {
  const r = matchOrder({
    orderAmountMinor: PRICE_MINOR.IN, // 12900, order was in INR
    orderCurrency: "INR",
    paidAmountMinor: PRICE_MINOR.IN, // same integer
    paidCurrency: "USD", // $129.00 claimed against a ₹129.00 order
  });
  assert.equal(r.ok, false);
  assert.equal(r.reason, "currency_mismatch");
});

test("currency is compared exactly — a lowercase code is a real anomaly", () => {
  // Both tables CHECK-constrain currency to ('INR','USD'), so 'usd' arriving
  // from the gateway means something changed upstream. Normalising it away
  // would hide that.
  const r = matchOrder({
    orderAmountMinor: 129,
    orderCurrency: "USD",
    paidAmountMinor: 129,
    paidCurrency: "usd",
  });
  assert.equal(r.ok, false);
  assert.equal(r.reason, "currency_mismatch");
});

// ── CRAFTED MISMATCH 2: WRONG AMOUNT, RIGHT CURRENCY ─────────────────────
//
// ATTACK: the classic. Pay one cent, claim the licence.

test("wrong amount, right currency is rejected as an amount mismatch", () => {
  const r = matchOrder({
    orderAmountMinor: PRICE_MINOR.INTL, // $1.29 expected
    orderCurrency: "USD",
    paidAmountMinor: 1, // $0.01 paid
    paidCurrency: "USD",
  });

  assert.equal(r.ok, false);
  assert.equal(
    r.reason,
    "amount_mismatch",
    "this must be named an amount fault, not a currency fault",
  );
});

test("every under-payment against an international order is refused", () => {
  for (const paid of [0, 1, 10, 100, 128]) {
    const r = matchOrder({
      orderAmountMinor: PRICE_MINOR.INTL,
      orderCurrency: "USD",
      paidAmountMinor: paid,
      paidCurrency: "USD",
    });
    assert.equal(r.ok, false, `paying ${paid} against a 129 order must not activate`);
    assert.equal(r.reason, "amount_mismatch");
  }
});

test("an OVER-payment is refused too — a mismatch is a mismatch", () => {
  // Not an attack so much as a misconfiguration or a currency-conversion
  // plugin. Refusing to activate is still correct: activate on a payment we
  // did not ask for and reconciliation is wrong from then on.
  const r = matchOrder({
    orderAmountMinor: PRICE_MINOR.INTL,
    orderCurrency: "USD",
    paidAmountMinor: 12_900,
    paidCurrency: "USD",
  });
  assert.equal(r.ok, false);
  assert.equal(r.reason, "amount_mismatch");
});

// ── BOTH WRONG ───────────────────────────────────────────────────────────

test("when both fields are wrong, the currency fault is reported first", () => {
  const r = matchOrder({
    orderAmountMinor: PRICE_MINOR.INTL,
    orderCurrency: "USD",
    paidAmountMinor: 1,
    paidCurrency: "INR",
  });
  assert.equal(r.ok, false);
  assert.equal(
    r.reason,
    "currency_mismatch",
    "currency is the coarser fault — if it is wrong, the amounts are quantities of different things",
  );
});

// ── THE CROSS-RAIL CONFUSION THIS EXISTS TO PREVENT ──────────────────────

test("an international payment cannot satisfy a domestic order, or vice versa", () => {
  const intlPayment = { paidAmountMinor: PRICE_MINOR.INTL, paidCurrency: "USD" };
  const domesticOrder = { orderAmountMinor: PRICE_MINOR.IN, orderCurrency: "INR" };

  assert.equal(matchOrder({ ...domesticOrder, ...intlPayment }).ok, false);

  const domesticPayment = { paidAmountMinor: PRICE_MINOR.IN, paidCurrency: "INR" };
  const intlOrder = { orderAmountMinor: PRICE_MINOR.INTL, orderCurrency: "USD" };

  assert.equal(matchOrder({ ...intlOrder, ...domesticPayment }).ok, false);
});

test("a $1.29 capture against a ₹129 order is refused — the 98.7% discount", () => {
  // The headline attack the two rails make possible: pay $1.29 (~₹113), get
  // the licence a domestic customer pays ₹129 for. Caught on currency first.
  const r = matchOrder({
    orderAmountMinor: PRICE_MINOR.IN,
    orderCurrency: "INR",
    paidAmountMinor: PRICE_MINOR.INTL,
    paidCurrency: "USD",
  });
  assert.equal(r.ok, false);
  assert.equal(r.reason, "currency_mismatch");
});

// ── BIGINT HANDLING ──────────────────────────────────────────────────────

test("a bigint amount arriving from PostgREST as a string still compares correctly", () => {
  // orders.amount_minor is a Postgres bigint; PostgREST hands large bigints
  // back as strings. A `===` against a number would be false for every one
  // of them, which would refuse every legitimate payment.
  assert.equal(
    matchOrder({
      orderAmountMinor: "129",
      orderCurrency: "USD",
      paidAmountMinor: 129,
      paidCurrency: "USD",
    }).ok,
    true,
  );

  assert.equal(
    matchOrder({
      orderAmountMinor: "12900",
      orderCurrency: "INR",
      paidAmountMinor: 12_900,
      paidCurrency: "INR",
    }).ok,
    true,
  );
});

test("a non-numeric amount does not accidentally match", () => {
  for (const bad of ["", "abc", "NaN"]) {
    const r = matchOrder({
      orderAmountMinor: bad,
      orderCurrency: "USD",
      paidAmountMinor: 129,
      paidCurrency: "USD",
    });
    assert.equal(r.ok, false, `order amount ${JSON.stringify(bad)} must not match`);
  }
});
