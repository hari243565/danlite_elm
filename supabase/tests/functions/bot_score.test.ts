// ══════════════════════════════════════════════════════════════════════════
// ADVERSARIAL TESTS — the bot score scores the PAY action, and cannot refuse.
//
// Two things to prove:
//   • the score is bound to the payment-submission action specifically, and
//     a token minted for something else does not pass as one;
//   • no score, and no provider failure, can refuse a real customer.
//
// The second is the one with teeth. reCAPTCHA scores sit low for entirely
// ordinary people — VPNs, privacy-hardened browsers, Tor, old Android
// WebViews — and this product is sold to motorcycle mechanics, not to a
// population that looks pristine to Google's risk model.
// ══════════════════════════════════════════════════════════════════════════

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  assessBotScore,
  CHECKOUT_ACTION,
  type EnterpriseAssessment,
  parseEnterpriseAssessment,
  SCORE_ALLOW,
  SCORE_FLAG,
} from "../../functions/_shared/bot_score.ts";

const good = (score: number, action = CHECKOUT_ACTION): EnterpriseAssessment => ({
  valid: true,
  action,
  score,
});

// ── IT CANNOT REFUSE ─────────────────────────────────────────────────────

test("no score anywhere in 0.00–1.00 can refuse a payment", () => {
  for (let i = 0; i <= 100; i++) {
    const score = i / 100;
    const a = assessBotScore({ configured: true, assessment: good(score) });

    assert.ok(
      ["allow", "flag", "throttle"].includes(a.verdict),
      `score ${score} produced verdict '${a.verdict}'`,
    );
    // There is no 'block' in the verdict union. Asserted at runtime so that
    // adding one later fails here rather than in production.
    assert.notEqual(a.verdict, "block");
    assert.notEqual(a.verdict, "deny");
  }
});

test("the worst possible score still lets the customer pay", () => {
  const a = assessBotScore({ configured: true, assessment: good(0) });
  assert.equal(a.verdict, "throttle");
  assert.equal(a.score, 0);
  // `throttle` spends rate-limit budget faster. It is not a refusal, and the
  // rate-limit suite proves a first attempt survives the +1 it contributes.
  assert.ok(a.note.includes("proceeding"));
});

// ── IT FAILS OPEN ────────────────────────────────────────────────────────

test("an unconfigured provider allows everyone — the live state today", () => {
  const a = assessBotScore({ configured: false });
  assert.equal(a.verdict, "allow");
  assert.equal(a.score, null);
  assert.ok(a.note.includes("not configured"));
});

test("a provider outage is not evidence about the customer", () => {
  // create-order maps an unreachable or non-200 provider to assessment: null.
  const a = assessBotScore({ configured: true, assessment: null });
  assert.equal(a.verdict, "flag", "an outage is recorded, not punished");
  assert.notEqual(a.verdict, "throttle");
});

test("a missing token — ad blocker, tracking protection, corporate proxy — is not punished", () => {
  const a = assessBotScore({ configured: true, assessment: null });
  assert.equal(a.verdict, "flag");
  assert.ok(a.note.includes("proceeding"));
});

test("an invalid token is flagged, not throttled and never refused", () => {
  const a = assessBotScore({
    configured: true,
    assessment: { valid: false, action: CHECKOUT_ACTION, score: 0.1 },
  });
  assert.equal(a.verdict, "flag");
});

// ── IT IS BOUND TO THE PAYMENT-SUBMISSION ACTION ─────────────────────────

test("the scored action is the payment submission specifically", () => {
  assert.equal(CHECKOUT_ACTION, "intl_checkout_pay");

  // A high score for the RIGHT action passes.
  assert.equal(
    assessBotScore({ configured: true, assessment: good(0.9) }).verdict,
    "allow",
  );
});

test("a token minted for a different action does not pass as a checkout token", () => {
  // The classic token-reuse attempt: mint a cheap token on a page-load or
  // sign-in action, replay it at checkout.
  for (const action of ["homepage", "login", "signup", "activate", ""]) {
    const a = assessBotScore({
      configured: true,
      assessment: good(0.99, action),
    });
    assert.equal(
      a.verdict,
      "throttle",
      `a token for '${action}' must not be accepted as a checkout token`,
    );
  }
});

test("an action mismatch is still not a refusal — a stale page is the likelier cause", () => {
  const a = assessBotScore({
    configured: true,
    assessment: good(0.99, "old_action_name"),
  });
  assert.equal(a.verdict, "throttle");
  assert.ok(a.note.includes("proceeding"));
});

test("expectedAction is overridable but defaults to the checkout action", () => {
  const a = assessBotScore({
    configured: true,
    assessment: good(0.9, "custom"),
    expectedAction: "custom",
  });
  assert.equal(a.verdict, "allow");
});

// ── THE GRADUATED BANDS ──────────────────────────────────────────────────

test("the three bands are exactly as documented, at their boundaries", () => {
  assert.equal(SCORE_ALLOW, 0.5);
  assert.equal(SCORE_FLAG, 0.3);

  assert.equal(
    assessBotScore({ configured: true, assessment: good(SCORE_ALLOW) }).verdict,
    "allow",
    "the allow threshold is inclusive",
  );
  assert.equal(
    assessBotScore({ configured: true, assessment: good(0.49) }).verdict,
    "flag",
  );
  assert.equal(
    assessBotScore({ configured: true, assessment: good(SCORE_FLAG) }).verdict,
    "flag",
    "the flag threshold is inclusive",
  );
  assert.equal(
    assessBotScore({ configured: true, assessment: good(0.29) }).verdict,
    "throttle",
  );
});

// ── PARSING THE PROVIDER'S RESPONSE ──────────────────────────────────────

test("a well-formed Enterprise response parses into the three fields", () => {
  const parsed = parseEnterpriseAssessment({
    tokenProperties: { valid: true, action: CHECKOUT_ACTION },
    riskAnalysis: { score: 0.7, reasons: [] },
  });
  assert.deepEqual(parsed, { valid: true, action: CHECKOUT_ACTION, score: 0.7 });
});

test("an unrecognised response shape becomes 'no signal', not 'guilty'", () => {
  for (
    const body of [
      null,
      undefined,
      {},
      { tokenProperties: null },
      { riskAnalysis: { score: "high" } },
      { error: { code: 403, message: "PERMISSION_DENIED" } },
      "not json at all",
      [],
    ]
  ) {
    const parsed = parseEnterpriseAssessment(body);
    assert.equal(parsed.valid, false, `body ${JSON.stringify(body)}`);

    // And that "no signal" reaches the customer as `flag`, which proceeds.
    const a = assessBotScore({ configured: true, assessment: parsed });
    assert.equal(a.verdict, "flag");
  }
});

test("an explicitly invalid token from the provider is honoured as invalid", () => {
  const parsed = parseEnterpriseAssessment({
    tokenProperties: { valid: false, invalidReason: "EXPIRED" },
    riskAnalysis: {},
  });
  assert.equal(parsed.valid, false);
  assert.equal(parsed.score, null);
});
