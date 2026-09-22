// ══════════════════════════════════════════════════════════════════════════
// CARD-TESTING RATE LIMIT — international order creation only.
//
// WHY THIS PATH SPECIFICALLY, AND NOT THE DOMESTIC ONE
// ----------------------------------------------------
// "Card testing" (carding) is running stolen card numbers through a cheap,
// low-friction checkout to find which ones are still live, before spending
// them somewhere that matters. The attacker does not want the goods. They
// want a yes/no oracle, and they want thousands of them.
//
// This checkout is close to the ideal target: $1.29, a digital good, no
// shipping address to fake, instant automated fulfilment, and — as of this
// change — an international card rail. The domestic rail is not remotely as
// attractive: UPI dominates it, UPI is push-authorised from the payer's own
// app, and a stolen UPI handle is not a reusable number you can test in bulk.
// The risk profiles genuinely differ, so the limits do too. This ledger is
// written ONLY on the international rail and the domestic rail is untouched
// by this file — see the callsite guard in create-order/index.ts.
//
// WHY THESE NUMBERS
// -----------------
// The binding constraint is NOT "stop every bot". It is "do not bill a real
// customer's fifth attempt as fraud". Industry data on false declines is
// blunt: lost revenue from wrongly-refused legitimate customers runs at
// roughly 5x actual fraud losses. So the limits are set from the top of the
// legitimate range, not the bottom of the abusive one.
//
// A real customer whose card is declined retries. They re-enter the number,
// try a second card, call their bank, try again. Each press of Pay opens a
// NEW Razorpay order, so retries consume this budget. Three to four attempts
// in a few minutes is ordinary, unremarkable, paying-customer behaviour.
// Five is a bad afternoon. Twelve in an hour is not a customer.
//
//   BURST  5 per IP per 5 minutes  — the card-testing signature is volume in
//                                    a short window from one origin. This is
//                                    the limit that actually bites an
//                                    automated run, and it still leaves a
//                                    frustrated real customer a 5th try.
//   HOURLY 12 per IP per hour      — catches a slow, paced run that stays
//                                    under the burst limit. Also the limit
//                                    most likely to touch a shared NAT or
//                                    carrier-grade IP, which is why it is set
//                                    well above any plausible single
//                                    customer's session.
//   USER   6 per account per hour  — an attacker who rotates IPs still needs
//                                    an account. Independent of IP so the two
//                                    cannot be evaded together.
//
// For comparison, the pre-existing domestic limiter in the portal allows 10
// per IP per 60 SECONDS. Every limit here is tighter in rate terms by an
// order of magnitude (5/5min = 1/min against 10/min), which is the "scoped
// tighter than the domestic limit" requirement, discharged with real numbers.
//
// WHY THE LEDGER AND NOT AN IN-PROCESS COUNTER
// --------------------------------------------
// portal/lib/rate-limit.ts is an in-process Map. It is honest about being
// single-instance, and it is fine for what it guards. It is NOT fine here:
// Edge Functions are horizontally scaled and an in-process counter resets on
// every cold start, which is a free reset an attacker can trigger by waiting.
// This uses the same durable, append-only ledger shape already proven by
// public.activation_requests: count the window, then insert unconditionally,
// so a REFUSED attempt still extends the window. Without that, every rejection
// would age out of the window and the limit would never actually bite.
// ══════════════════════════════════════════════════════════════════════════

export const BURST_WINDOW_MS = 5 * 60_000;
export const HOUR_WINDOW_MS = 60 * 60_000;

export const MAX_PER_IP_PER_BURST = 5;
export const MAX_PER_IP_PER_HOUR = 12;
export const MAX_PER_USER_PER_HOUR = 6;

export type LimitCounts = {
  /** Attempts from this IP in the last BURST_WINDOW_MS. */
  ipBurst: number;
  /** Attempts from this IP in the last hour. */
  ipHour: number;
  /** Attempts by this account in the last hour. */
  userHour: number;
};

export type LimitDecision = {
  allowed: boolean;
  /** Which limit tripped. `null` when allowed — for the audit row, not the customer. */
  rule: "ip_burst" | "ip_hour" | "user_hour" | null;
};

/**
 * Pure decision function. Counts in, verdict out — no clock, no database, no
 * randomness, which is what makes both directions of this testable.
 *
 * The counts are of attempts ALREADY LOGGED, excluding the one being decided.
 * So `>=` is correct: at ipBurst === 5 the customer has already had five
 * goes inside five minutes and this would be the sixth.
 *
 * A bot-score `throttle` verdict is folded in by the caller as a +1 on the
 * burst count rather than as a veto of its own — see bot_score.ts for why a
 * score is never allowed to decline a payment by itself.
 */
export function decideIntlOrderLimit(counts: LimitCounts): LimitDecision {
  if (counts.ipBurst >= MAX_PER_IP_PER_BURST) {
    return { allowed: false, rule: "ip_burst" };
  }
  if (counts.ipHour >= MAX_PER_IP_PER_HOUR) {
    return { allowed: false, rule: "ip_hour" };
  }
  if (counts.userHour >= MAX_PER_USER_PER_HOUR) {
    return { allowed: false, rule: "user_hour" };
  }
  return { allowed: true, rule: null };
}

/**
 * What the customer is told. Deliberately identical whichever rule tripped:
 * telling an attacker WHICH limit they hit tells them which axis to rotate.
 * It also reads as a transient hiccup rather than an accusation, because the
 * most likely human on the other end of it is a real customer on a shared
 * office IP, not a fraudster.
 */
export const RATE_LIMITED_MESSAGE =
  "Too many checkout attempts from this connection. Please wait a few minutes and try again.";
