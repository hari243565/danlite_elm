// ══════════════════════════════════════════════════════════════════════════
// BILLING ADDRESS AS A SOFT AVS SIGNAL — never a gate.
//
// WHAT AVS IS, AND WHAT IT IS NOT
// -------------------------------
// The Address Verification Service compares the billing address the customer
// types against the one their card issuer holds. It is a genuine, standard
// anti-fraud signal for card-not-present digital goods — which is why mature
// subscription services collect a billing address even though nothing is ever
// shipped. This is a BILLING address for verification, not a shipping
// address; there is no parcel.
//
// It is also, outside a few countries, close to useless. AVS coverage is real
// and reliable only in the US, the UK and Canada. Elsewhere issuers commonly
// return "unavailable" or "not supported", and a customer in Germany or Japan
// or Brazil with a perfectly good card routinely produces a non-match for
// reasons that have nothing to do with fraud: transliteration, address
// formats the issuer never stored, a card registered at an old address.
//
// WHY IT IS NOT ALLOWED TO DECLINE ANYTHING HERE
// ----------------------------------------------
// Treating an AVS mismatch as an automatic decline is a well-documented and
// expensive mistake. False declines — legitimate customers wrongly refused —
// cost merchants on the order of five times what card fraud itself costs.
// On a $1.29 lifetime licence the arithmetic is not close: the most a
// fraudulent sale can cost is $1.29 plus a chargeback fee, while a wrongly
// refused customer is a lost sale AND a support ticket AND, for a one-person
// product, a bad review.
//
// So this module CANNOT decline. Look at the return type: there is no
// `decline` member and no boolean that a caller could read as one. The
// strongest thing it can say is `flagged: true`, which writes an audit row
// and nothing else. That is a deliberate type-level guarantee rather than a
// convention someone could quietly break in a later edit — the adversarial
// test in avs.test.ts asserts it holds for every possible input combination,
// including the worst one.
// ══════════════════════════════════════════════════════════════════════════

/**
 * The countries where an AVS result actually means something. Anywhere else,
 * a mismatch is far more likely to be a format difference than a thief.
 */
export const AVS_RELIABLE_COUNTRIES = ["US", "GB", "CA"] as const;

export type AvsSignal =
  /** Billing country agrees with the card's issuing country. */
  | "match"
  /** They disagree. Worth recording. Not worth refusing money over. */
  | "country_mismatch"
  /** We have both, but AVS is not meaningful in this country. */
  | "unverifiable"
  /** The customer did not give us an address, or the card country is unknown. */
  | "not_provided";

export type AvsAssessment = {
  signal: AvsSignal;
  /** Whether to write a review flag. The ONLY consequence available here. */
  flagged: boolean;
  /** Is an AVS result trustworthy in this billing country at all? */
  coverage: "reliable" | "unreliable" | "unknown";
  /** For the audit row. */
  note: string;
};

function norm(v: string | null | undefined): string {
  return (v ?? "").trim().toUpperCase();
}

/**
 * Two-letter ISO country, or "" if it is not one. Kept strict because a
 * free-text country box is how you end up comparing "USA" to "US" and
 * flagging a customer for a data-entry difference.
 */
export function normalizeCountry(v: string | null | undefined): string {
  const c = norm(v);
  return /^[A-Z]{2}$/.test(c) ? c : "";
}

/**
 * Classify the billing address against what we independently know.
 *
 * @param billingCountry what the customer typed at checkout. Client-supplied,
 *   and therefore evidence of nothing on its own — which is precisely why it
 *   is a signal and not a gate.
 * @param cardCountry the issuing country Razorpay reports on the payment
 *   entity (`payment.card.country`). Not available at order-creation time;
 *   absent then, present in the webhook.
 */
export function assessBillingAddress(input: {
  billingCountry?: string | null;
  cardCountry?: string | null;
}): AvsAssessment {
  const billing = normalizeCountry(input.billingCountry);
  const card = normalizeCountry(input.cardCountry);

  if (!billing || !card) {
    return {
      signal: "not_provided",
      flagged: false,
      coverage: "unknown",
      note: billing
        ? "Billing country collected; card issuing country not yet known."
        : "No billing country collected.",
    };
  }

  const reliable = (AVS_RELIABLE_COUNTRIES as readonly string[]).includes(
    billing,
  );

  if (billing === card) {
    return {
      signal: "match",
      flagged: false,
      coverage: reliable ? "reliable" : "unreliable",
      note: `Billing country ${billing} matches card issuing country.`,
    };
  }

  // A mismatch. Flag it ONLY where AVS actually means something — flagging
  // every cross-border card would flag most of the international rail's
  // honest customers, and a flag that fires on everything is noise that
  // trains whoever reads it to ignore the ones that matter.
  return {
    signal: reliable ? "country_mismatch" : "unverifiable",
    flagged: reliable,
    coverage: reliable ? "reliable" : "unreliable",
    note: reliable
      ? `Billing country ${billing} differs from card issuing country ${card}. Flagged for review; payment NOT refused.`
      : `Billing country ${billing} differs from card issuing country ${card}, but AVS is unreliable outside ${
        AVS_RELIABLE_COUNTRIES.join("/")
      }. Recorded, not flagged.`,
  };
}
