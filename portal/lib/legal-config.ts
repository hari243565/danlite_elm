// ══════════════════════════════════════════════════════════════════════════
// Business details for the /legal/* pages — the ONE place they live.
//
// Every value the client, accountant or lawyer has not yet supplied is a
// placeholder token of the form {{TODO:…}} (upper-case name, digits and
// underscores). The pages render any such token
// in a highlighted box with its OPEN_QUESTIONS reference, so an unfilled value
// cannot pass for a real one. `node scripts/check-legal-placeholders.mjs`
// lists every token still open; `--strict` exits non-zero while any remain or
// while APPROVED_FOR_PUBLICATION is false.
//
// TO RESOLVE A TOKEN: replace the string with the real value (or with '' for
// the *_CONFIRMED flags, which render nothing once confirmed). Do not delete
// the key. See docs/legal/CLIENT_REVIEW_PACK.md for what each one needs and
// the proposed wording.
//
// Prices are NOT here. They are imported from lib/gst.ts by the pages, so a
// price change there cannot leave a legal page stating the old figure.
// ══════════════════════════════════════════════════════════════════════════

/** Matches one placeholder token. Kept in sync with the check script. */
export const TODO_TOKEN = /\{\{TODO:([A-Z0-9_]+)\}\}/g;

/**
 * Flip to true only after the lawyer/CA review is complete and every token is
 * resolved. While false, every legal page carries the DRAFT banner.
 */
export const APPROVED_FOR_PUBLICATION = false;

/** Document versions. Bump the version and add a changelog line on every change. */
export const LEGAL_VERSION = '0.2 (draft)';
export const LAST_UPDATED = '{{TODO:LAST_UPDATED}}';
export const CHANGELOG: ReadonlyArray<{ version: string; date: string; note: string }> = [
  { version: '0.1 (draft)', date: '15 Aug 2026', note: 'First drafts of Privacy, Terms and Refunds.' },
  {
    version: '0.2 (draft)',
    date: '30 Sep 2026',
    note:
      'Rewritten from the verified data inventory. Added Delivery, Contact, Pricing and ' +
      'Delete-account pages. Not yet approved.',
  },
];

// ── Who we are ─────────────────────────────────────────────────────────────
export const BUSINESS = {
  legalName: '{{TODO:LEGAL_NAME}}',
  entityType: '{{TODO:ENTITY_TYPE}}',
  registeredAddress: '{{TODO:REGISTERED_ADDRESS}}',
  gstin: '{{TODO:GSTIN}}',
  /** Product name used on this website and in our emails. */
  productName: 'Danlite ELM',
  /** Name under the app icon on the phone (android:label in AndroidManifest.xml). */
  appLabel: 'OBD Danlite',
  /** App name exactly as the Google Play listing shows it. */
  playListingName: '{{TODO:PLAY_LISTING_NAME}}',
  /** Developer name exactly as the Google Play listing shows it. */
  playDeveloperName: '{{TODO:PLAY_DEVELOPER_NAME}}',
  website: 'https://billing.danlite.in',
} as const;

// ── Contact and grievance ─────────────────────────────────────────────────
export const CONTACT = {
  supportEmail: '{{TODO:SUPPORT_EMAIL}}',
  supportPhone: '{{TODO:SUPPORT_PHONE}}',
  supportHours: '{{TODO:SUPPORT_HOURS}}',
  privacyEmail: '{{TODO:PRIVACY_EMAIL}}',
  grievanceOfficerName: '{{TODO:GRIEVANCE_OFFICER_NAME}}',
  grievanceOfficerDesignation: '{{TODO:GRIEVANCE_OFFICER_DESIGNATION}}',
  grievanceOfficerEmail: '{{TODO:GRIEVANCE_OFFICER_EMAIL}}',
  grievanceOfficerPhone: '{{TODO:GRIEVANCE_OFFICER_PHONE}}',
  /** e.g. "48 hours" */
  grievanceAckTime: '{{TODO:GRIEVANCE_ACK_TIME}}',
  /** e.g. "one month" */
  grievanceResolutionTime: '{{TODO:GRIEVANCE_RESOLUTION_TIME}}',
  /** e.g. "30 days" (the law allows up to 90) */
  privacyResponseTime: '{{TODO:PRIVACY_RESPONSE_TIME}}',
  /** Address our activation emails come from. */
  activationSender: '{{TODO:ACTIVATION_SENDER_ADDRESS}}',
  /** Who sends the 6-digit login codes, and from which address. */
  loginCodeSender: '{{TODO:AUTH_EMAIL_SENDER}}',
} as const;

// ── Terms decisions ───────────────────────────────────────────────────────
export const TERMS = {
  /** City whose courts have jurisdiction (non-exclusive for consumers). */
  courtCity: '{{TODO:GOVERNING_COURT_CITY}}',
  minimumAge: '{{TODO:MIN_AGE}}',
  /** e.g. "90 days" */
  shutdownNoticePeriod: '{{TODO:SHUTDOWN_NOTICE_PERIOD}}',
  /** A full sentence: what customers get if the service is discontinued. */
  discontinuationRemedy: '{{TODO:DISCONTINUATION_REMEDY}}',
} as const;

// ── Refund decisions ──────────────────────────────────────────────────────
export const REFUND = {
  /** A full sentence chosen from option A, B or C in CLIENT_REVIEW_PACK.md. */
  changeOfMindRule: '{{TODO:CHANGE_OF_MIND_RULE}}',
  /** e.g. "7 days" */
  defectReportWindow: '{{TODO:DEFECT_REPORT_WINDOW}}',
  /** e.g. "5 working days" */
  decisionTime: '{{TODO:REFUND_DECISION_TIME}}',
  /** A full sentence from the accountant: GST on refunds, credit notes. */
  taxTreatment: '{{TODO:REFUND_TAX_TREATMENT}}',
} as const;

// ── Tax and invoices (accountant) ─────────────────────────────────────────
export const TAX = {
  /** Set to '' once the accountant confirms the GST treatment in lib/gst.ts. */
  gstTreatmentConfirmed: '{{TODO:GST_TREATMENT_CONFIRMED}}',
  /** Set to '' once the accountant confirms the export treatment in lib/gst.ts. */
  exportTreatmentConfirmed: '{{TODO:EXPORT_TAX_CONFIRMED}}',
  /** A full sentence: how the customer receives a tax invoice. */
  invoiceDelivery: '{{TODO:INVOICE_DELIVERY}}',
} as const;

// ── Privacy decisions ─────────────────────────────────────────────────────
export const PRIVACY = {
  /** e.g. "30 days" */
  deletionCompletionTime: '{{TODO:DELETION_COMPLETION_TIME}}',
  /** Hashed-identifier + IP ledgers, activation tokens, card-testing ledger. */
  retentionSecurityRecords: '{{TODO:RETENTION_SECURITY_RECORDS}}',
  /** Audit log of licence, payment and admin events. */
  retentionAuditLog: '{{TODO:RETENTION_AUDIT_LOG}}',
  /** Logs kept by our providers (hosting, database platform, email, crash reports). */
  providerLogRetention: '{{TODO:PROVIDER_LOG_RETENTION}}',
  /** A full sentence on the legal safeguard for transfers outside India. */
  transferSafeguards: '{{TODO:TRANSFER_SAFEGUARDS}}',
  /** Delete this line's use if GB/DE are dropped (Q-17). */
  euUkRepresentative: '{{TODO:EU_UK_REPRESENTATIVE}}',
  /** A full sentence on which languages the notice is available in. */
  noticeLanguages: '{{TODO:NOTICE_LANGUAGES}}',
  hostingerLocation: '{{TODO:HOSTINGER_LOCATION}}',
  githubLocation: '{{TODO:GITHUB_LOCATION}}',
} as const;

// ── Where we sell ─────────────────────────────────────────────────────────
/** The countries the app's sign-up screen offers today (signup_screen.dart). */
export const SIGNUP_COUNTRIES = [
  'India',
  'United States',
  'United Kingdom',
  'United Arab Emirates',
  'Canada',
  'Australia',
  'Singapore',
  'Germany',
] as const;
/** Set to '' once the owner confirms the list above is where sales are offered. */
export const SALES_COUNTRIES_CONFIRMED = '{{TODO:SALES_COUNTRIES_CONFIRMED}}';

/**
 * Which OPEN_QUESTIONS item answers each token. Rendered next to the
 * highlighted placeholder, and checked by the placeholder script: a token
 * with no entry here is reported as an error.
 */
export const PLACEHOLDER_QUESTIONS: Record<string, string> = {
  LAST_UPDATED: 'Q-32',
  LEGAL_NAME: 'Q-01',
  ENTITY_TYPE: 'Q-01',
  REGISTERED_ADDRESS: 'Q-01',
  GSTIN: 'Q-03',
  PLAY_LISTING_NAME: 'Q-26',
  PLAY_DEVELOPER_NAME: 'Q-26',
  SUPPORT_EMAIL: 'Q-11',
  SUPPORT_PHONE: 'Q-27',
  SUPPORT_HOURS: 'Q-27',
  PRIVACY_EMAIL: 'Q-11',
  GRIEVANCE_OFFICER_NAME: 'Q-11',
  GRIEVANCE_OFFICER_DESIGNATION: 'Q-11',
  GRIEVANCE_OFFICER_EMAIL: 'Q-11',
  GRIEVANCE_OFFICER_PHONE: 'Q-11',
  GRIEVANCE_ACK_TIME: 'Q-11',
  GRIEVANCE_RESOLUTION_TIME: 'Q-11',
  PRIVACY_RESPONSE_TIME: 'Q-11',
  ACTIVATION_SENDER_ADDRESS: 'Q-30',
  AUTH_EMAIL_SENDER: 'Q-22',
  GOVERNING_COURT_CITY: 'Q-28',
  MIN_AGE: 'Q-10',
  SHUTDOWN_NOTICE_PERIOD: 'Q-06',
  DISCONTINUATION_REMEDY: 'Q-06',
  CHANGE_OF_MIND_RULE: 'Q-29',
  DEFECT_REPORT_WINDOW: 'Q-29',
  REFUND_DECISION_TIME: 'Q-29',
  REFUND_TAX_TREATMENT: 'Q-03',
  GST_TREATMENT_CONFIRMED: 'Q-03',
  EXPORT_TAX_CONFIRMED: 'Q-05',
  INVOICE_DELIVERY: 'Q-03',
  DELETION_COMPLETION_TIME: 'Q-08',
  RETENTION_SECURITY_RECORDS: 'Q-09',
  RETENTION_AUDIT_LOG: 'Q-09',
  PROVIDER_LOG_RETENTION: 'Q-31',
  TRANSFER_SAFEGUARDS: 'Q-15',
  EU_UK_REPRESENTATIVE: 'Q-17',
  NOTICE_LANGUAGES: 'Q-19',
  HOSTINGER_LOCATION: 'Q-15',
  GITHUB_LOCATION: 'Q-15',
  SALES_COUNTRIES_CONFIRMED: 'Q-17',
};
