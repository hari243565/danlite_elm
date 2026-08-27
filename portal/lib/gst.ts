/**
 * GST TREATMENT — PLACEHOLDER, PENDING ACCOUNTANT CONFIRMATION.
 *
 * 'inclusive' = the displayed price (₹129) already contains GST; the
 *   invoice extracts the tax portion from within it. The customer pays
 *   exactly ₹129 either way.
 * 'exclusive' = GST is added ON TOP of ₹129 at checkout, so the amount
 *   charged becomes ₹129 + GST. This is a real pricing change, not just an
 *   invoice-math change — confirm which the client actually wants.
 *
 * DO NOT change this without an explicit instruction citing the
 * accountant's confirmation.
 */
export const GST_TREATMENT: 'inclusive' | 'exclusive' = 'inclusive';
export const GST_RATE_PERCENT = 18; // standard rate assumption — CONFIRM

/**
 * SECOND UNCONFIRMED ASSUMPTION, flagged separately because it is a different
 * question with a different answer: what happens on the INTERNATIONAL rail.
 *
 * A sale to a customer outside India is an export of service. Under the IGST
 * Act that is normally zero-rated — either supplied under a LUT with no tax
 * charged, or supplied with IGST paid and later refunded. Which of those two
 * applies depends on whether the business has filed a LUT, which is not a
 * question this code can answer.
 *
 * The code below therefore charges NO GST on the international rail. If the
 * accountant says otherwise, this is the constant to revisit.
 */
export const GST_ON_EXPORTS = false; // export of service treated as zero-rated — CONFIRM

/**
 * Prices are held in MINOR UNITS (paise, cents) as integers, mirroring the
 * `payments.amount_minor bigint` column from Phase 1. Money is never a float
 * here: 129/1.18 in floating point is exactly the kind of value that
 * reconciles to a rounding difference six months later.
 */
export const PRICE_MINOR = {
  IN: 12_900, // ₹129.00
  INTL: 129, //  $1.29
} as const;

export type Breakdown = {
  currency: 'INR' | 'USD';
  symbol: '₹' | '$';
  /** What the customer's card is actually charged. */
  totalMinor: number;
  /** Pre-tax portion. Equals totalMinor when no GST applies. */
  baseMinor: number;
  /** Tax portion. 0 when no GST applies. */
  taxMinor: number;
  /** True when a GST line should be displayed at all. */
  taxApplies: boolean;
  /** Human-readable statement of how tax relates to the total. */
  note: string;
};

/** Minor units -> display string, e.g. 12900 -> "129.00". */
export function formatMinor(minor: number): string {
  return (minor / 100).toFixed(2);
}

/**
 * The single source of truth for what a customer is shown and charged.
 *
 * `countryCode` MUST come from profiles.country_code read server-side. It is
 * deliberately not a parameter the browser can influence: country selects the
 * price, and a client-editable country is a 99% discount.
 */
export function priceFor(countryCode: string): Breakdown {
  const isIndia = countryCode.toUpperCase() === 'IN';

  if (!isIndia) {
    const total = PRICE_MINOR.INTL;
    return {
      currency: 'USD',
      symbol: '$',
      totalMinor: total,
      baseMinor: total,
      taxMinor: 0,
      taxApplies: GST_ON_EXPORTS,
      note: GST_ON_EXPORTS
        ? 'Tax treatment for exports is unconfirmed — see portal/lib/gst.ts.'
        : 'Export of service — treated as zero-rated. Pending accountant confirmation.',
    };
  }

  if (GST_TREATMENT === 'inclusive') {
    // The listed price IS the total. Extract the tax that sits inside it.
    // tax = total * rate / (100 + rate), rounded to the nearest paisa, and the
    // base is then the remainder so that base + tax === total EXACTLY. Deriving
    // the base by subtraction rather than by its own rounded division is what
    // guarantees the invoice adds up.
    const total = PRICE_MINOR.IN;
    const tax = Math.round((total * GST_RATE_PERCENT) / (100 + GST_RATE_PERCENT));
    return {
      currency: 'INR',
      symbol: '₹',
      totalMinor: total,
      baseMinor: total - tax,
      taxMinor: tax,
      taxApplies: true,
      note: `Price includes ${GST_RATE_PERCENT}% GST.`,
    };
  }

  // 'exclusive' — GST is added on top, so the customer is charged MORE than
  // the headline price. Deliberately makes the higher total visible rather
  // than hiding it until the payment screen.
  const base = PRICE_MINOR.IN;
  const tax = Math.round((base * GST_RATE_PERCENT) / 100);
  return {
    currency: 'INR',
    symbol: '₹',
    totalMinor: base + tax,
    baseMinor: base,
    taxMinor: tax,
    taxApplies: true,
    note: `${GST_RATE_PERCENT}% GST added on top of the listed price.`,
  };
}

/**
 * Who an invoice is made out to.
 *
 * The name the customer gave on the Create Account screen, or their email
 * address when there is none. That fallback is not a nicety — a GST invoice
 * has to name a recipient, and every account created before that screen
 * collected a name has only an email to name them by. Nothing about those
 * older invoices changes.
 *
 * It deliberately never falls back to the user id: an invoice that identifies
 * its recipient by a UUID identifies them to nobody. `first_name` alone is a
 * complete name here, not half of one — see the split note in
 * signup_screen.dart.
 */
export function billedTo(
  profile:
    | { first_name?: string | null; last_name?: string | null; email?: string | null }
    | null
    | undefined,
  fallbackEmail?: string | null,
): string {
  const parts = [profile?.first_name, profile?.last_name]
    .map((p) => (p ?? '').trim())
    .filter((p) => p.length > 0);
  if (parts.length > 0) return parts.join(' ');

  const email = (profile?.email ?? fallbackEmail ?? '').trim();
  return email.length > 0 ? email : '—';
}
