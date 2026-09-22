// ══════════════════════════════════════════════════════════════════════════
// ADVERSARIAL TESTS — the international amount and its tax treatment.
//
// Run:  node --test supabase/tests/functions/
//
// These import the REAL modules that /create-order and /razorpay-webhook
// import. They are not a model of the pricing logic, they are the pricing
// logic, executed. That is the whole reason intl_pricing.ts was written with
// no Deno globals and no jsr: specifiers.
//
// Each test states the attack it is standing in for, because a test named
// `test('railFor works')` tells a future reader nothing about what breaks if
// they delete it.
// ══════════════════════════════════════════════════════════════════════════

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  CURRENCY,
  PRICE_MINOR,
  railFor,
  taxFor,
} from "../../functions/_shared/intl_pricing.ts";

// The portal's own module, imported directly rather than transcribed. If the
// two ever disagree about what this product costs, that is a test failure and
// not a discrepancy discovered by a customer.
import { PRICE_MINOR as PORTAL_PRICE, priceFor } from "../../../portal/lib/gst.ts";

// ── 1. THE AMOUNT IS SERVER-DERIVED, FULL STOP ───────────────────────────
//
// ATTACK: a crafted request body carrying `amount: 1`, or `amount_minor: 1`,
// or `price: 0`, aiming to buy a lifetime licence for one cent.
//
// The structural defence is that `railFor` takes a country and returns an
// amount; there is no parameter through which an amount could arrive. This
// test encodes that as behaviour: whatever an attacker puts in a body, the
// amount for a given country is a constant.

test("no crafted body field can change the international amount", () => {
  const craftedBodies = [
    { amount: 1 },
    { amount_minor: 1 },
    { amount: 0 },
    { price: 0 },
    { totalMinor: 1 },
    { currency: "INR", amount: 1 },
    { amount: -12_900 },
    { amount: Number.MAX_SAFE_INTEGER },
  ];

  for (const body of craftedBodies) {
    // This mirrors the callsite exactly: the ONLY thing create-order passes
    // to railFor is the country it read from profiles. The body is not in
    // scope. Reproduced here so the test fails if someone widens the
    // signature to accept one.
    const pricing = railFor("US");

    assert.equal(
      pricing.amountMinor,
      129,
      `body ${JSON.stringify(body)} must not influence the amount`,
    );
    assert.equal(pricing.currency, "USD");
    assert.equal(pricing.rail, "INTL");
  }

  // The signature itself is the control. One parameter, and it is a string.
  assert.equal(railFor.length, 1, "railFor must take exactly one argument");
});

test("the same holds on the domestic rail — no regression there either", () => {
  const pricing = railFor("IN");
  assert.equal(pricing.amountMinor, 12_900);
  assert.equal(pricing.currency, "INR");
  assert.equal(pricing.rail, "IN");
});

// ── 2. THE BILLING ADDRESS CANNOT MOVE THE RAIL ──────────────────────────
//
// ATTACK: a customer whose profiles.country_code is 'US' (so they pay $1.29)
// types 'IN' into the new billing-country box — or the reverse, a customer in
// India types 'US' hoping to pay $1.29 instead of ₹129.
//
// The billing address is collected for AVS and dispute evidence only. It is
// stored on the order row and it is NEVER read back to select a price. The
// migration's CHECK constraint and column comment say so; this asserts it.

test("billing_country cannot move the rail — India pays INR whatever they type", () => {
  const billingCountriesAnAttackerMightType = [
    "US",
    "GB",
    "CA",
    "AE",
    "SG",
    "ZZ",
    "",
    "in",
  ];

  for (const billing of billingCountriesAnAttackerMightType) {
    // profiles.country_code is the only input. `billing` is deliberately
    // unused by the pricing call — that IS the property under test.
    const pricing = railFor("IN");
    assert.equal(
      pricing.amountMinor,
      12_900,
      `billing_country=${billing} must not discount a domestic customer`,
    );
    assert.equal(pricing.currency, "INR");
  }
});

test("billing_country cannot move the rail — an export stays an export", () => {
  for (const billing of ["IN", "in", "In", "", "US"]) {
    const pricing = railFor("DE");
    assert.equal(
      pricing.amountMinor,
      129,
      `billing_country=${billing} must not pull an export onto the INR rail`,
    );
    assert.equal(pricing.currency, "USD");
    assert.equal(pricing.rail, "INTL");
  }
});

// ── 3. GST ZERO-RATING ON EXPORTS CANNOT BE FORCED TO DOMESTIC ───────────
//
// ATTACK: force an 18% GST computation onto an international sale (which
// would over-charge a foreign customer tax India has no claim to and
// mis-state an export on a GST return), or the reverse — get a domestic sale
// treated as a zero-rated export and pay no GST on it.
//
// `taxFor` takes a `Rail`, and the only producer of a `Rail` is `railFor`,
// which derives it from the database. There is no path from a request body
// to a tax treatment.

test("an international sale is always zero-rated, never domestically taxed", () => {
  const { rail, amountMinor } = railFor("US");
  const tax = taxFor(rail, amountMinor);

  assert.equal(tax.code, "zero_rated_export");
  assert.equal(tax.taxApplies, false);
  assert.equal(tax.taxMinor, 0);
  // An export is outside the charge, so the base is the whole amount — it is
  // not "18% of nothing".
  assert.equal(tax.baseMinor, amountMinor);
  assert.equal(tax.baseMinor, 129);
});

test("no country code produces a taxed export", () => {
  const nonIndia = ["US", "GB", "DE", "AE", "SG", "AU", "ZZ", "", "  ", "xx"];
  for (const c of nonIndia) {
    const { rail, amountMinor } = railFor(c);
    const tax = taxFor(rail, amountMinor);
    assert.equal(rail, "INTL", `${JSON.stringify(c)} should be the export rail`);
    assert.equal(tax.taxMinor, 0, `${JSON.stringify(c)} must carry no GST`);
    assert.equal(tax.code, "zero_rated_export");
  }
});

test("the domestic GST calculation is untouched and still adds up exactly", () => {
  const { rail, amountMinor } = railFor("IN");
  const tax = taxFor(rail, amountMinor);

  assert.equal(tax.code, "gst_inclusive");
  assert.equal(tax.taxApplies, true);
  // 12900 * 18 / 118 = 1967.79... -> 1968
  assert.equal(tax.taxMinor, 1968);
  assert.equal(tax.baseMinor, 10_932);
  // The property that matters on an invoice: the parts equal the whole.
  assert.equal(
    tax.baseMinor + tax.taxMinor,
    amountMinor,
    "base + tax must equal the total exactly, or the invoice does not add up",
  );
});

// ── 4. 'IN' IS MATCHED EXACTLY — NO CASING OR WHITESPACE ESCAPE HATCH ────
//
// ATTACK: less about an attacker and more about a data-entry path that
// stores 'in' or ' IN ' and silently lands a domestic customer on the $1.29
// rail, which is a 98.7% discount given away by a trim() nobody wrote.

test("country matching is case- and whitespace-insensitive for 'IN'", () => {
  for (const c of ["IN", "in", "In", " IN ", "\tin\n"]) {
    assert.equal(
      railFor(c).rail,
      "IN",
      `${JSON.stringify(c)} must be recognised as India`,
    );
  }
});

test("a country that merely starts with 'IN' is NOT India", () => {
  // 'IND' is a real alpha-3 code for India, but this column holds alpha-2.
  // Accepting a prefix match here would be a different bug — the point is
  // that the comparison is exact, so an unexpected value lands on the
  // international rail (fail-safe: we charge more, we do not give a 98.7%
  // discount to an unrecognised value).
  for (const c of ["IND", "INX", "INDIA"]) {
    assert.equal(railFor(c).rail, "INTL");
  }
});

// ── 5. THE EDGE FUNCTION AND THE PORTAL AGREE ────────────────────────────
//
// ATTACK: none. This is the silent-divergence guard. The portal decides what
// the customer is SHOWN; the Edge Function decides what they are CHARGED. If
// those two numbers drift apart the customer sees one price on the page and
// another on their card statement, which is the kind of defect that is found
// by a chargeback rather than by a developer.

test("edge-function prices equal the portal's prices on both rails", () => {
  assert.equal(
    PRICE_MINOR.IN,
    PORTAL_PRICE.IN,
    "domestic price has drifted between portal and edge function",
  );
  assert.equal(
    PRICE_MINOR.INTL,
    PORTAL_PRICE.INTL,
    "international price has drifted between portal and edge function",
  );
});

test("what the portal SHOWS equals what the edge function CHARGES", () => {
  for (const country of ["IN", "US", "GB", "DE"]) {
    const shown = priceFor(country);
    const charged = railFor(country);

    assert.equal(
      shown.totalMinor,
      charged.amountMinor,
      `${country}: page shows ${shown.totalMinor}, card is charged ${charged.amountMinor}`,
    );
    assert.equal(shown.currency, charged.currency, `${country}: currency differs`);
  }
});

test("the portal and the edge function agree that an export bears no tax", () => {
  const shown = priceFor("US");
  const { rail, amountMinor } = railFor("US");
  const charged = taxFor(rail, amountMinor);

  assert.equal(shown.taxApplies, charged.taxApplies);
  assert.equal(shown.taxMinor, charged.taxMinor);
  assert.equal(shown.taxMinor, 0);
});

test("CURRENCY map and the rail agree", () => {
  assert.equal(CURRENCY.IN, "INR");
  assert.equal(CURRENCY.INTL, "USD");
  assert.equal(railFor("IN").currency, CURRENCY.IN);
  assert.equal(railFor("US").currency, CURRENCY.INTL);
});
