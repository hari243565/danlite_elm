// ══════════════════════════════════════════════════════════════════════════
// THE RAIL DECISION — which currency, which amount, which tax treatment.
//
// WHY THIS IS A SEPARATE, DEPENDENCY-FREE MODULE
// ----------------------------------------------
// Two reasons, both load-bearing:
//
//   1. It imports nothing. No Deno globals, no jsr:, no npm:. That is what
//     lets `node --test` execute the adversarial cases in
//     supabase/functions/_shared/intl_pricing.test.ts directly against the
//     SAME bytes the Edge Function runs. A pricing rule that is only
//     "reviewed" is not tested; this one is executable.
//
//   2. The amount lives in exactly one place. Before this module, the ₹129
//     constant was inline in create-order/index.ts and the $1.29 constant was
//     inline in portal/lib/gst.ts, and nothing made them agree. The portal
//     module still owns what the customer is SHOWN (it renders the page); this
//     module owns what the customer is CHARGED. intl_pricing.test.ts asserts
//     the two agree on both rails, so a future edit to one that forgets the
//     other fails a test instead of shipping a divergence.
//
// THE ONE RULE THIS FILE EXISTS TO ENFORCE
// ----------------------------------------
// `railFor()` takes a country code and nothing else, and that country code
// MUST come from public.profiles read server-side under the service role. It
// is never read from a request body, a query string, a header, or a browser
// locale. Country selects the price. A client-editable country is a 99%
// discount (₹129 -> $1.29 is a 98.7% discount at ~₹88/USD, which is the exact
// shape of the bug this signature is designed to make unwriteable).
//
// Note there is deliberately NO overload that accepts an amount. Callers
// cannot pass one in, so no caller can accidentally honour one.
// ══════════════════════════════════════════════════════════════════════════

export type Rail = "IN" | "INTL";
export type Currency = "INR" | "USD";

/**
 * Minor units (paise, cents) as integers, mirroring `payments.amount_minor
 * bigint`. Money is never a float here — 129/1.18 in floating point is
 * exactly the kind of value that reconciles to a rounding difference six
 * months later.
 *
 * ⚠ MUST STAY IN STEP WITH portal/lib/gst.ts `PRICE_MINOR`.
 * intl_pricing.test.ts enforces this against the real portal module rather
 * than trusting this comment.
 */
export const PRICE_MINOR = {
  IN: 12_900, // ₹129.00
  INTL: 129, //  $1.29
} as const;

export const CURRENCY: Record<Rail, Currency> = {
  IN: "INR",
  INTL: "USD",
};

/**
 * Mirrors portal/lib/gst.ts. Both are placeholders pending the accountant's
 * confirmation and are duplicated rather than imported because an Edge
 * Function cannot import from the Next.js app. The test asserts they match.
 */
export const GST_RATE_PERCENT = 18;
export const GST_TREATMENT: "inclusive" | "exclusive" = "inclusive";
/** Export of service, treated as zero-rated under the IGST Act. CONFIRM. */
export const GST_ON_EXPORTS = false;

export type RailPricing = {
  rail: Rail;
  amountMinor: number;
  currency: Currency;
};

/**
 * The only way to obtain an amount in this codebase's server path.
 *
 * @param countryCode `profiles.country_code`, read server-side. Anything
 *   absent, empty or non-'IN' lands on the international rail; the `?? 'IN'`
 *   default is applied by the CALLER so it matches the profiles table's own
 *   column default and the two cannot disagree.
 */
export function railFor(countryCode: string): RailPricing {
  const rail: Rail = countryCode.trim().toUpperCase() === "IN" ? "IN" : "INTL";
  return {
    rail,
    amountMinor: PRICE_MINOR[rail],
    currency: CURRENCY[rail],
  };
}

export type TaxTreatment = {
  /** True when a GST line should appear on the invoice at all. */
  taxApplies: boolean;
  /** Pre-tax portion. Equals the total when no GST applies. */
  baseMinor: number;
  /** Tax portion. 0 on a zero-rated export. */
  taxMinor: number;
  /** Machine-readable, for the audit row and the invoice. */
  code: "gst_inclusive" | "gst_exclusive" | "zero_rated_export";
  /** Human-readable, for the invoice line. */
  note: string;
};

/**
 * Tax treatment for a completed sale.
 *
 * DOMESTIC IS UNCHANGED from what portal/lib/gst.ts has always computed —
 * inclusive extraction, base derived by SUBTRACTION so that
 * base + tax === total exactly.
 *
 * INTERNATIONAL is a supply of service to a recipient outside India, which
 * the IGST Act zero-rates. No tax is charged and no tax is extracted: the
 * base equals the total. Note the asymmetry with the domestic branch — an
 * export is not "18% of nothing", it is outside the charge entirely, which is
 * why `taxApplies` is false rather than `taxMinor` merely being 0.
 *
 * The rail is derived, never supplied: this takes a `Rail` that only
 * `railFor()` produces, so no caller can request domestic GST on an export.
 */
export function taxFor(rail: Rail, amountMinor: number): TaxTreatment {
  if (rail === "INTL") {
    return {
      taxApplies: GST_ON_EXPORTS,
      baseMinor: amountMinor,
      taxMinor: 0,
      code: "zero_rated_export",
      note:
        "Export of service — zero-rated, no GST charged. Pending accountant confirmation.",
    };
  }

  if (GST_TREATMENT === "inclusive") {
    const tax = Math.round(
      (amountMinor * GST_RATE_PERCENT) / (100 + GST_RATE_PERCENT),
    );
    return {
      taxApplies: true,
      baseMinor: amountMinor - tax,
      taxMinor: tax,
      code: "gst_inclusive",
      note: `Price includes ${GST_RATE_PERCENT}% GST.`,
    };
  }

  const tax = Math.round((amountMinor * GST_RATE_PERCENT) / 100);
  return {
    taxApplies: true,
    baseMinor: amountMinor,
    taxMinor: tax,
    code: "gst_exclusive",
    note: `${GST_RATE_PERCENT}% GST added on top of the listed price.`,
  };
}
