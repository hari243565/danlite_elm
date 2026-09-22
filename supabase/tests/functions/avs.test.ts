// ══════════════════════════════════════════════════════════════════════════
// ADVERSARIAL TESTS — the billing address is a SIGNAL, never a GATE.
//
// The requirement here is unusual: most security tests prove that something
// is blocked. These prove that nothing is. The failure mode being guarded
// against is not a fraudster getting through — at $1.29 that is a rounding
// error — it is a legitimate customer in Germany or Brazil being refused
// because their issuer never stored their address in a format AVS can match.
//
// False declines cost merchants roughly five times what card fraud does.
// That ratio is the reason every test below asserts a payment PROCEEDS.
// ══════════════════════════════════════════════════════════════════════════

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  assessBillingAddress,
  AVS_RELIABLE_COUNTRIES,
  normalizeCountry,
} from "../../functions/_shared/avs.ts";

// ── THE CENTRAL GUARANTEE ────────────────────────────────────────────────
//
// Exhaustive over a representative cross-product. Whatever goes in, the
// assessment must never contain anything a caller could read as a refusal.

test("no combination of billing and card country can produce a decline", () => {
  const countries = [
    "US", "GB", "CA", // AVS-reliable
    "DE", "FR", "JP", "BR", "IN", "AE", "SG", "NG", "RU", // not reliable
    "ZZ", "", "  ", "usa", "U", "USA", // malformed
  ];

  let checked = 0;
  for (const billing of countries) {
    for (const card of countries) {
      const a = assessBillingAddress({
        billingCountry: billing,
        cardCountry: card,
      });
      checked++;

      // The type has no decline member. This asserts the shape at runtime
      // too, so adding one later breaks this test rather than quietly
      // breaking customers.
      const keys = Object.keys(a);
      for (const forbidden of ["decline", "block", "reject", "deny", "hardDecline"]) {
        assert.ok(
          !keys.includes(forbidden),
          `assessment must not expose a '${forbidden}' field (billing=${billing}, card=${card})`,
        );
      }

      // The strongest consequence available is a review flag.
      assert.equal(typeof a.flagged, "boolean");
      assert.ok(
        ["match", "country_mismatch", "unverifiable", "not_provided"].includes(
          a.signal,
        ),
        `unexpected signal ${a.signal}`,
      );
    }
  }

  assert.equal(checked, countries.length * countries.length);
  assert.ok(checked >= 289, "the cross-product should be genuinely exhaustive");
});

// ── THE SPECIFIC SCENARIO THE BRIEF ASKS FOR ─────────────────────────────
//
// "a mismatched billing address does NOT by itself block an otherwise-valid
// payment."

test("a mismatched billing address does not block an otherwise-valid payment", () => {
  // The worst legitimate-looking case: a US billing address (where AVS is
  // reliable, so this IS flagged) against a card issued in Germany.
  const a = assessBillingAddress({ billingCountry: "US", cardCountry: "DE" });

  assert.equal(a.signal, "country_mismatch");
  assert.equal(a.flagged, true, "a reliable-country mismatch is worth recording");
  assert.equal(a.coverage, "reliable");

  // And yet: nothing here refuses anything. `flagged` writes an audit row.
  // The webhook reads this assessment strictly AFTER the licence has already
  // been activated, which is the structural half of this guarantee — see the
  // position of the avs block in razorpay-webhook/index.ts.
  assert.ok(a.note.includes("payment NOT refused"));
});

// ── COVERAGE IS RESPECTED — NOISE IS NOT MANUFACTURED ────────────────────
//
// Flagging every cross-border card would flag most of the honest
// international rail, and a flag that fires on everything trains whoever
// reads it to ignore the ones that matter.

test("AVS is only treated as meaningful in the US, UK and Canada", () => {
  assert.deepEqual([...AVS_RELIABLE_COUNTRIES], ["US", "GB", "CA"]);

  for (const c of AVS_RELIABLE_COUNTRIES) {
    const a = assessBillingAddress({ billingCountry: c, cardCountry: "DE" });
    assert.equal(a.coverage, "reliable");
    assert.equal(a.flagged, true, `${c} mismatch should be flagged`);
    assert.equal(a.signal, "country_mismatch");
  }
});

test("a mismatch outside AVS coverage is recorded but NOT flagged", () => {
  // A customer in Germany whose card was issued in France. Utterly ordinary
  // inside the EU, and AVS has nothing useful to say about it.
  for (const billing of ["DE", "FR", "JP", "BR", "AE", "SG"]) {
    const a = assessBillingAddress({ billingCountry: billing, cardCountry: "US" });
    assert.equal(a.coverage, "unreliable", `${billing} should not be AVS-reliable`);
    assert.equal(
      a.flagged,
      false,
      `${billing} mismatch must not be flagged — AVS is meaningless there`,
    );
    assert.equal(a.signal, "unverifiable");
  }
});

test("a matching address is clean on both reliable and unreliable rails", () => {
  for (const c of ["US", "GB", "CA", "DE", "JP", "BR"]) {
    const a = assessBillingAddress({ billingCountry: c, cardCountry: c });
    assert.equal(a.signal, "match");
    assert.equal(a.flagged, false);
  }
});

// ── MISSING DATA IS NOT EVIDENCE ─────────────────────────────────────────

test("no billing address collected is 'not_provided', never suspicion", () => {
  for (const input of [
    {},
    { billingCountry: null, cardCountry: "US" },
    { billingCountry: "", cardCountry: "US" },
    { billingCountry: undefined, cardCountry: "US" },
  ]) {
    const a = assessBillingAddress(input);
    assert.equal(a.signal, "not_provided");
    assert.equal(a.flagged, false);
  }
});

test("order-creation time (no card country yet) is 'not_provided', not a mismatch", () => {
  // This is the exact call create-order makes: the billing address is known,
  // the issuing country is not, because no card has been presented yet.
  const a = assessBillingAddress({ billingCountry: "US" });
  assert.equal(a.signal, "not_provided");
  assert.equal(a.flagged, false);
  assert.ok(a.note.includes("not yet known"));
});

// ── NORMALISATION — DO NOT FLAG A TYPO AS FRAUD ──────────────────────────

test("country normalisation accepts only ISO alpha-2, and never throws", () => {
  assert.equal(normalizeCountry("us"), "US");
  assert.equal(normalizeCountry(" gb "), "GB");
  assert.equal(normalizeCountry("USA"), "", "alpha-3 is not alpha-2");
  assert.equal(normalizeCountry("U"), "");
  assert.equal(normalizeCountry("U1"), "");
  assert.equal(normalizeCountry(""), "");
  assert.equal(normalizeCountry(null), "");
  assert.equal(normalizeCountry(undefined), "");
});

test("a casing difference is a match, not a mismatch", () => {
  // Comparing 'us' to 'US' and calling it a country mismatch would flag a
  // customer for the case of a dropdown value.
  const a = assessBillingAddress({ billingCountry: "us", cardCountry: "US" });
  assert.equal(a.signal, "match");
  assert.equal(a.flagged, false);
});
