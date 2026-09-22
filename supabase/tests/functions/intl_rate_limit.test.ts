// ══════════════════════════════════════════════════════════════════════════
// ADVERSARIAL TESTS — the card-testing rate limit, PROVED IN BOTH DIRECTIONS.
//
// A rate limit is two claims, and a test suite that only makes the first one
// is half a suite:
//
//   1. It stops the abuse.        (tests under "IT TRIGGERS")
//   2. It does not stop a real    (tests under "IT DOES NOT TRIGGER")
//      customer.
//
// Claim 2 is the one that actually costs money if it is wrong. False declines
// run at roughly 5x the cost of the fraud they prevent, so a limiter that
// blocks a paying customer's fourth attempt has done more damage than the
// card tester it was aimed at. Every "does not trigger" test below is
// therefore written from a specific, named, ordinary customer behaviour
// rather than from a round number.
// ══════════════════════════════════════════════════════════════════════════

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  BURST_WINDOW_MS,
  decideIntlOrderLimit,
  HOUR_WINDOW_MS,
  MAX_PER_IP_PER_BURST,
  MAX_PER_IP_PER_HOUR,
  MAX_PER_USER_PER_HOUR,
} from "../../functions/_shared/intl_rate_limit.ts";

/** Convenience: only the axis under test is non-zero. */
const counts = (o: Partial<Parameters<typeof decideIntlOrderLimit>[0]>) => ({
  ipBurst: 0,
  ipHour: 0,
  userHour: 0,
  ...o,
});

// ══════════════════════════════════════════════════════════════════════════
// IT TRIGGERS — the card-testing pattern is actually stopped
// ══════════════════════════════════════════════════════════════════════════

// ATTACK: the canonical card-testing run. A script holds a list of stolen
// card numbers and hammers /create-order to mint an order per card, looking
// for which numbers still authorise. Volume from one origin in a short
// window is the signature.
test("a rapid burst from one IP is refused once the burst budget is spent", () => {
  // Attempts 1..5 all go through — the budget is genuinely spendable.
  for (let already = 0; already < MAX_PER_IP_PER_BURST; already++) {
    const d = decideIntlOrderLimit(counts({ ipBurst: already }));
    assert.equal(
      d.allowed,
      true,
      `attempt ${already + 1} within the burst budget must be allowed`,
    );
  }

  // The 6th inside five minutes is not a customer.
  const blocked = decideIntlOrderLimit(counts({ ipBurst: MAX_PER_IP_PER_BURST }));
  assert.equal(blocked.allowed, false);
  assert.equal(blocked.rule, "ip_burst");
});

// ATTACK: the patient version. The attacker learns the burst window and
// paces the run to stay under it — four per five minutes, all day.
test("a paced run that evades the burst window is still caught by the hourly limit", () => {
  const paced = decideIntlOrderLimit(
    counts({ ipBurst: MAX_PER_IP_PER_BURST - 1, ipHour: MAX_PER_IP_PER_HOUR }),
  );
  assert.equal(paced.allowed, false);
  assert.equal(paced.rule, "ip_hour");
});

// ATTACK: the attacker rotates IPs — a proxy pool, a mobile data connection
// they can cycle, a botnet. The IP axis is defeated. They still need an
// account, because /create-order requires a verified JWT before it ever
// reaches the limiter.
test("rotating IPs does not help — the per-account limit is independent", () => {
  const rotated = decideIntlOrderLimit(
    // A fresh IP every time: both IP counters read zero.
    counts({ ipBurst: 0, ipHour: 0, userHour: MAX_PER_USER_PER_HOUR }),
  );
  assert.equal(rotated.allowed, false);
  assert.equal(rotated.rule, "user_hour");
});

// ATTACK: a low bot score arriving alongside a run already near its budget.
test("a low bot score spends burst budget faster on a requester already near the limit", () => {
  const atFour = counts({ ipBurst: MAX_PER_IP_PER_BURST - 1 });

  // Without the bot signal, the 5th attempt is allowed.
  assert.equal(decideIntlOrderLimit(atFour).allowed, true);

  // The caller folds a `throttle` verdict in as +1 — see create-order.
  const withThrottle = decideIntlOrderLimit({
    ...atFour,
    ipBurst: atFour.ipBurst + 1,
  });
  assert.equal(withThrottle.allowed, false);
  assert.equal(withThrottle.rule, "ip_burst");
});

// ══════════════════════════════════════════════════════════════════════════
// IT DOES NOT TRIGGER — a real customer is never refused
// ══════════════════════════════════════════════════════════════════════════

// THE SINGLE MOST IMPORTANT TEST IN THIS FILE.
// One customer, one checkout, first time. If this ever fails, the limiter is
// costing more than the fraud it prevents.
test("a first-time customer's single checkout is allowed", () => {
  const d = decideIntlOrderLimit(counts({}));
  assert.equal(d.allowed, true);
  assert.equal(d.rule, null);
});

// THE SECOND MOST IMPORTANT TEST.
// A genuine decline is not a rare edge case — issuers decline international
// cards on Indian gateways routinely, often for 3DS/authentication reasons
// that have nothing to do with the customer's balance. The customer's
// response is to try again. Each press of Pay opens a NEW order and spends a
// unit of this budget, so retries are exactly what this limit must tolerate.
test("a real customer retrying after a genuine decline is NOT blocked", () => {
  // Attempt 1: card declined. Attempt 2: re-typed the number, declined again.
  // Attempt 3: tried a second card. Attempt 4: called the bank, tried again.
  // This is an ordinary bad afternoon, not an attack.
  for (let attempt = 1; attempt <= 4; attempt++) {
    const alreadyLogged = attempt - 1;
    const d = decideIntlOrderLimit(
      counts({
        ipBurst: alreadyLogged,
        ipHour: alreadyLogged,
        userHour: alreadyLogged,
      }),
    );
    assert.equal(
      d.allowed,
      true,
      `a legitimate customer's attempt ${attempt} must not be refused (rule=${d.rule})`,
    );
  }
});

// A customer whose bot score is mediocre — a VPN, a privacy browser, an old
// Android WebView — must still get through on their first try. The +1 from a
// `throttle` verdict is deliberately small enough that it cannot convert a
// first attempt into a refusal.
test("a low-scoring but legitimate customer still checks out on the first attempt", () => {
  const firstAttemptWithWorstBotVerdict = decideIntlOrderLimit(
    counts({ ipBurst: 0 + 1 }), // 0 prior attempts, +1 for `throttle`
  );
  assert.equal(
    firstAttemptWithWorstBotVerdict.allowed,
    true,
    "the bot score must never be able to refuse a first attempt by itself",
  );
});

// Two colleagues in the same workshop behind one NAT, or two customers on the
// same carrier-grade NAT, buying on the same afternoon.
test("several distinct customers sharing one NAT IP are not refused", () => {
  // Three customers, two attempts each, all from one public IP.
  const sharedIpAttempts = 6;
  assert.ok(
    sharedIpAttempts < MAX_PER_IP_PER_HOUR,
    "the hourly IP budget must leave room for a shared NAT",
  );
  const d = decideIntlOrderLimit(
    counts({ ipBurst: 2, ipHour: sharedIpAttempts, userHour: 2 }),
  );
  assert.equal(d.allowed, true);
});

// ══════════════════════════════════════════════════════════════════════════
// THE LIMITS THEMSELVES
// ══════════════════════════════════════════════════════════════════════════

// The brief requires this path be scoped TIGHTER than the existing domestic
// limit. The domestic limiter (portal/lib/rate-limit.ts, used by
// portal/app/checkout/page.tsx) allows 10 attempts per IP per 60 SECONDS.
// Comparing budgets alone would be misleading because the windows differ, so
// compare rates.
test("every international limit is tighter than the domestic limit, in rate terms", () => {
  const DOMESTIC_PER_MINUTE = 10 / 1; // 10 per 60s

  const intlBurstPerMinute = MAX_PER_IP_PER_BURST / (BURST_WINDOW_MS / 60_000);
  const intlHourPerMinute = MAX_PER_IP_PER_HOUR / (HOUR_WINDOW_MS / 60_000);
  const intlUserPerMinute = MAX_PER_USER_PER_HOUR / (HOUR_WINDOW_MS / 60_000);

  assert.ok(
    intlBurstPerMinute < DOMESTIC_PER_MINUTE,
    `burst ${intlBurstPerMinute}/min must be tighter than domestic ${DOMESTIC_PER_MINUTE}/min`,
  );
  assert.ok(intlHourPerMinute < DOMESTIC_PER_MINUTE);
  assert.ok(intlUserPerMinute < DOMESTIC_PER_MINUTE);

  // Concretely, for the record: 1/min against 10/min.
  assert.equal(intlBurstPerMinute, 1);
});

// A limiter whose headroom is below ordinary retry behaviour is a false
// decline generator. This pins the floor so a future "let's tighten it"
// cannot silently drop below what a real customer needs.
test("the budgets leave room for at least four ordinary retries", () => {
  assert.ok(MAX_PER_IP_PER_BURST >= 5, "burst budget too tight for real retries");
  assert.ok(MAX_PER_USER_PER_HOUR >= 5, "per-user budget too tight for real retries");
  assert.ok(MAX_PER_IP_PER_HOUR > MAX_PER_IP_PER_BURST);
});

test("the decision is pure — same counts, same verdict, no clock, no state", () => {
  const c = counts({ ipBurst: 3, ipHour: 7, userHour: 2 });
  const first = decideIntlOrderLimit(c);
  for (let i = 0; i < 100; i++) {
    assert.deepEqual(decideIntlOrderLimit(c), first);
  }
});
