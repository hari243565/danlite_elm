# Sources and evidence register

**Status:** investigation working paper, 30 Sep 2026. Not legal advice. Prepared from a read-only
investigation of the repository at commit `71e2783`, the live Supabase catalog, and the live public
websites. Every other document in `docs/legal/` cites the evidence IDs (`E-nnn`) and research IDs
(`R1`–`R7`, `V-nn`) defined here.

**How to read this:** Part A checks the legal/policy research the brief was given. Part B lists the
vendor facts used in the sub-processor register. Part C is the evidence register: one line per fact
with the exact place it was observed.

**Privacy rule followed:** no personal-data value (email, name, phone, IP, token, payload value) and
no secret appears in this folder. Database evidence is limited to catalog metadata, row counts,
dates of the earliest row, and JSON **key names**. Where an example is needed it is obviously fake
(`customer@example.com`, `+91 90000 00000`).

---

## Part A — Verification of the research brief (R1–R7)

Status key: **VERIFIED** = read in a primary or official source on the access date.
**PARTLY** = the substance is confirmed but part of the claim could not be confirmed, or the only
source read was a faithful secondary transcription rather than the official text.
**UNVERIFIED** = not confirmed.

| ID | Claim (as given) | Source read | Accessed | Status | Corrections / notes |
|---|---|---|---|---|---|
| R1a | DPDP Rules 2025 notified 13 Nov 2025 as G.S.R. 846(E) | dpdprules.org Rule 1 (transcription of the Gazette text); Lexology, S.S. Rana summaries | 30 Sep 2026 | **PARTLY** | Date and G.S.R. number agree across sources. The Gazette PDF itself was **not** read (MeitY/egazette not fetched). Owner's lawyer should read the Gazette. |
| R1b | Rules 3 and 5–16 start 13 May 2027 | dpdprules.org Rule 1: "Rules 1, 2 and 17 to 21 … on the date of their publication"; secondary sources: Rules 3, 5–16, 22, 23 after 18 months; Rule 4 after 1 year | 30 Sep 2026 | **PARTLY** | Correction: the brief says "consent-manager rules start Nov 2026". That is **Rule 4**, one year after publication, i.e. **13 Nov 2026**. Rules 22 and 23 also start 13 May 2027. |
| R1c | Notice must state data, purpose, how to withdraw, how to exercise rights, how to complain to the Board | dpdprules.org Rule 3 | 30 Sep 2026 | **PARTLY** (transcription) | Rule 3 also requires the notice to be "understandable independently of any other information" and to give an **itemised** description of the data, and withdrawal must be as easy as giving consent. |
| R1d | Grievance resolution up to 90 days | dpdprules.org Rule 14(3): "within a reasonable period not exceeding ninety days" | 30 Sep 2026 | **PARTLY** (transcription) | Confirmed. |
| R1e | Certain logs retained at least one year | dpdprules.org Rule 6: "retain such logs and personal data for a period of one year, unless … any law … requires otherwise" | 30 Sep 2026 | **PARTLY** (transcription) | This is a **minimum** retention for security logs, which sits in tension with erasure. |
| R1f | Child = under 18, verifiable parental consent | DPDP Act 2023 s.2(f), s.9; Rule 10 title on dpdprules.org | 30 Sep 2026 | **PARTLY** | Rule 10 text not read in full. |
| R1g | Cross-border: restricted-country ("negative list") model | DPDP Act 2023 s.16 (from knowledge of the Act; not re-read online) | — | **UNVERIFIED** in this session | No country has been notified as restricted as far as this investigation knows; lawyer to confirm. |
| R2a | Privacy-policy link required in Play Console **and** inside the app | Play Console Help, User Data policy (answer/10144311): "All apps must post a privacy policy link in the designated field within Play Console, and a privacy policy link or text within the app itself." | 30 Sep 2026 | **VERIFIED** | |
| R2b | Policy must comprehensively disclose access, collection, use, sharing; entity named in listing must appear | same page | 30 Sep 2026 | **VERIFIED** | Also requires "developer contact information", "secure handling procedures" and "data retention/deletion policies". |
| R2c | Account deletion: in-app path **and** web link; lawful retention disclosed | Play Console Help answer/13327111 | 30 Sep 2026 | **VERIFIED** | Quoted: "provide users with an in-app path to delete their app accounts and associated data" and "provide a web link resource where users can request app account deletion". |
| R2d | Freezing/deactivating does not count | same page | 30 Sep 2026 | **PARTLY** | The page summary read in this session did not contain an explicit "deactivation does not count" sentence. The requirement is framed as deletion of data. Treat the claim as correct in substance; confirm in the Play Console form wording. |
| R2e | "Prominent disclosure" before collection | answer/10144311 | 30 Sep 2026 | **VERIFIED** | Applies where data use would not be reasonably expected. |
| R3 | Razorpay: live keys unavailable until website/app details added; site needs Shipping, Contact us, Pricing, Terms, Privacy, Cancellation & Refunds | Razorpay Docs "Business Website Details" (razorpay.com/docs/payments/dashboard/account-settings/business-website-details/) | 30 Sep 2026 | **VERIFIED** (the page list and the live-key gate) / **UNVERIFIED** (physical address + phone + refund timeline guidance; merchant-terms wording) | Docs say instant checks validate "your website, policy pages and business industry". Note: the URL given in the brief's era (`/set-up/business-website-details/`) now 404s. |
| R4a | E-Commerce Rules 2020: grievance officer acknowledges in 48 h, redresses within one month | Rule 4(5), text quoted by search result from the ICSI-hosted rules PDF | 30 Sep 2026 | **VERIFIED** (text) | Whether Danlite is an "e-commerce entity" under these Rules is a lawyer question (it sells its own digital product from its own website; most commentators treat that as an inventory e-commerce entity). |
| R4b | Display legal name, address, customer-care contact, grievance officer; refunds within reasonable time; explicit purchase consent | Not re-read in this session | — | **UNVERIFIED** | Widely reported; lawyer to confirm Rule 4(2), 4(4), 5(3), 6(5). |
| R4c | CPA 2019 s.34(2), Emaar MGF v Aftab Singh (arbitration clause does not oust consumer forum) | Not re-read | — | **UNVERIFIED** | Consistent with general knowledge; lawyer to confirm. |
| R5a | GST records kept 72 months from due date of annual return (s.36, Rule 56) | CBIC tax information portal, CGST Act s.36 | 30 Sep 2026 | **VERIFIED** | Extended to one year after final disposal where there is an appeal or investigation. |
| R5b | Export without IGST needs a valid LUT (RFD-11, Rule 96A) | CBIC Rule 96A page (found), secondary summaries | 30 Sep 2026 | **PARTLY** | Correction: Rule 96A also requires payment for exported services to be received in **convertible foreign exchange (or INR where RBI permits) within one year**. Accountant must confirm how Razorpay international settlements evidence this (FIRA/eBRC). |
| R5c | Export invoice endorsement | Rule 46 via secondary source | 30 Sep 2026 | **PARTLY** | Correction to wording: the Rule 46 endorsement is "**SUPPLY MEANT FOR EXPORT UNDER BOND OR LETTER OF UNDERTAKING WITHOUT PAYMENT OF INTEGRATED TAX**", not "…under LUT without payment of IGST". Quoting the LUT ARN is common practice, not confirmed as mandatory. |
| R6 | GDPR Art 13 contents | gdpr-info.eu Art. 13 | 30 Sep 2026 | **VERIFIED** | Also requires the **representative** (Art 27) where one is required, and DPO contact if appointed. |
| R7a | Play: apps accepting payment for in-app features must use Play Billing; no leading users to other payment methods via in-app buttons, links, messaging, other CTAs | Play Payments policy (answer/9858738) | 30 Sep 2026 | **VERIFIED** | Section 4 also names "**In-app user interface flows, including account creation or sign-up flows**" as prohibited ways of leading users out. That is directly relevant (see RISK_REGISTER T12). |
| R7b | A "consumption-only" model is recognised | same page | 30 Sep 2026 | **UNVERIFIED** | The page read in this session did **not** contain consumption-only wording. Do not rely on it without a primary source. |
| R7c | India has alternative-billing / user-choice programmes | same page, Sections 8 and 9 | 30 Sep 2026 | **PARTLY** | Sections 8 ("alternative billing system") and 9 ("lead users … outside the app") exist for "eligible countries/regions"; the country list was not visible. Confirm India eligibility and fees in Play Console. |

## Part B — Vendor facts (for the sub-processor register)

| ID | Fact | Source | Accessed | Status |
|---|---|---|---|---|
| V-01 | Supabase **Free** plan projects receive **no automatic daily backups**; Pro keeps 7 days, Team 14, Enterprise up to 30 | supabase.com/docs/guides/platform/backups | 30 Sep 2026 | VERIFIED |
| V-02 | Sentry EU region data is stored in Frankfurt, Germany; EU ingest domain `de.sentry.io` | docs.sentry.io/organization/data-storage-location/ | 30 Sep 2026 | VERIFIED |
| V-03 | Resend sending regions include Tokyo (`ap-northeast-1`); **all account data, metadata and logs are stored in the United States regardless of sending region** | resend.com/docs/dashboard/domains/regions | 30 Sep 2026 | VERIFIED |
| V-04 | Supabase project runs in `ap-south-1` (Mumbai) | `npx supabase projects list` (E-054) | 30 Sep 2026 | VERIFIED |
| V-05 | GitHub artifact retention set to 90 days by the workflow | workflow file (E-061) | 30 Sep 2026 | VERIFIED |
| V-06 | Razorpay, Hostinger, Google (Fonts, reCAPTCHA), GitHub, Cloudflare: terms/DPA links and processing locations | not fetched in this session | — | **UNKNOWN — owner to confirm** (links listed in DATA_INVENTORY §4 as places to look, not as verified facts) |

## Part C — Evidence register

Paths are repo-relative at commit `71e2783` (identical in the owner's folder, which was clean — E-001).
"Live" = observed on 30 Sep 2026 with read-only access.

### Environment
| ID | Evidence |
|---|---|
| E-001 | Owner's folder `git status --short` was **empty** (clean) at `71e2783` on `main`, tracking `origin/main` +0/-0. No uncommitted app code; the multi-brand ABS work is committed. |
| E-002 | Shipped build artifacts in the owner's folder: `build/app/outputs/flutter-apk/app-release.apk` and `bundle/release/app-release.aab`, both dated **22 Sep 2026 21:07**, i.e. **before** commit `71e2783` (30 Sep 2026). Which build is on Play (if any) is UNKNOWN. |

### Database schema (migrations) — `supabase/migrations/`
| ID | Evidence |
|---|---|
| E-010 | `20260812134908_initial_schema_and_rls.sql` L39-52: `profiles` (email UNIQUE, phone, country_code, signup_platform, `deleted_at`). L47-48 comment: "a scheduled job performs hard deletion after the retention window" — **no such job exists** (E-066, E-092). |
| E-011 | same file L87-103: `payments` incl. `raw_payload jsonb`, `gst_invoice_no`; L89 `user_id … on delete restrict`. |
| E-012 | same file L108-131: `devices` (fingerprint, platform, model, last_seen_at) and `sessions` (issued/last_seen/revoked, **no IP, no user agent**). |
| E-013 | same file L139-146: `webhook_events` has only `gateway, event_id, event_type, processed_at` — **no payload column**. |
| E-014 | same file L151-158: `consent_records (user_id, policy_version, consented_at, ip, user_agent)`. |
| E-015 | same file L163-170: `audit_log (user_id, action, detail jsonb, ip, created_at)`; `20260823160000_admin_actions.sql` L39-41 adds `actor_user_id` (FK SET NULL) and `actor_email`. |
| E-016 | `20260919121000_audit_log_append_only_trigger.sql` L72-110: BEFORE UPDATE/DELETE and BEFORE TRUNCATE triggers raise for **every** role incl. owner; L60-66 documents the intended purge procedure (disable trigger, purge, re-enable). |
| E-017 | `20260814204500_activation_and_rate_limit.sql` L18-57: `activation_tokens` (SHA-256 token hash, expiry) and `activation_requests` (peppered identifier hash + `ip`); L90-91 grants; L175-179 "housekeeping … deliberately NOT automated". |
| E-018 | same file L114-172: trigger on `licences` INSERT posts to `/send-activation` via `pg_net` — i.e. **every new signup triggers an activation email**. |
| E-019 | `20260815105545_orders_and_payment_rpc.sql` L27-36 `orders`; L64-67 invoice format "PLACEHOLDER — CONFIRM WITH THE ACCOUNTANT"; L127-129 `INV/<FY>/<6-digit seq>`; L170-180 activation **hard-codes `purchase_rail = 'razorpay_in'`**; L199-204 revoke on ANY refund. |
| E-020 | `20260818163000_refund_revocation_idempotency.sql` L42-48: incident refund was partial (9000 of 10900 minor units) and still revoked the whole licence; behaviour unchanged. |
| E-021 | `20260815160000_session_enforcement.sql` L38-112: `claim_session` last-login-wins; L124-148 `sign_out_all_devices`. |
| E-022 | `20260823101500_admin_users.sql` L65-69 `admin_users(email)`; L115-125 `admin_otp_requests(identifier_hash, ip, was_allowed)`; L153 seeds the owner's address (value not reproduced here). |
| E-023 | `20260823160000_admin_actions.sql` L102-297: admin grant/revoke require a reason and an identified actor; write `audit_log` with `actor_email`. |
| E-024 | `20260827120000_profiles_name_fields.sql`: adds `first_name`, `last_name`; drops phone UNIQUE; name/phone are **client-writable** by the user. |
| E-025 | `20260919120000_protect_profile_email.sql` L71-94: client cannot change `email`, `country_code`, `signup_platform`, `deleted_at`; L63-68 notes nothing syncs `profiles.email` from `auth.users` after signup. |
| E-026 | `20260922120000_intl_order_rate_limit_and_avs.sql` L38-57 `intl_order_attempts(user_id, ip, device_hash, outcome)`; L124-134 `orders.billing_country`, `billing_postal_code`, `risk_signals`. |
| E-027 | `20260922163000_revoke_truncate_intl_ledger.sql` L42: TRUNCATE revoked from service_role on `intl_order_attempts` only. |

### Edge Functions — `supabase/functions/`
| ID | Evidence |
|---|---|
| E-030 | `razorpay-webhook/index.ts` L115-137: `raw_payload` is a **redacted** copy (id, order_id, amount, currency, status, method, fee, tax, captured, created_at, notes, `_webhook`); card/VPA/bank sub-objects deliberately dropped. L35-37 logging policy: identifiers only. |
| E-031 | same file L281-615: handles only `payment.captured`, `payment.failed`, `refund.created`, `refund.processed`; **everything else (incl. disputes/chargebacks) is acknowledged and ignored** (L611-614). |
| E-032 | same file L465-491: AVS signal (card issuing country vs billing country) written to `audit_log`, never gates. |
| E-033 | `create-order/index.ts` L503-513: returns `prefill: { email, contact: phone }` which the portal passes to Razorpay Checkout; L425-433 order `notes` carry `user_id` (and billing_country on INTL); L168-212 reCAPTCHA Enterprise call is **inert unless 3 secrets are set**; L316-372 INTL rail logs IP + device_hash + user_id to `intl_order_attempts`. |
| E-034 | `send-activation/index.ts` L37 token TTL **15 min**; L40-41 resend limits **3 per identifier/hour, 10 per IP/hour**; L111-115 peppered identifier hash; L65-69 generic reply still says "**email or mobile number**"; L172 sender fallback; L183-193 email text: "Open this link to complete your purchase". L338-343 Path B looks a profile up by **phone** (phone is no longer unique — E-024). |
| E-035 | `verify-activation/index.ts` L103-171: redeems token, mints a Supabase session for the portal. |
| E-036 | `entitlement/index.ts` L32 token TTL **14 days**; L331-340 claims `sub` (user id), `lic`, `sid`, `did`, `iat`, `exp`; L84-90 & L299-327 emergency paywall bypass (every use audited). |
| E-037 | `claim-session/index.ts` L89-119: stores fingerprint (hash), platform, model (≤120 chars); L20-21 fingerprint never logged. |
| E-038 | `_shared/sentry.ts` L55-114: `sendDefaultPii:false`, request bodies off, IP explicitly nulled; L84-93 states IP **still arrived** until the Sentry project setting "Prevent Storing of IP Addresses" is enabled. |
| E-039 | `_shared/admin_guard.ts` L133-138: logs the **email address** of any non-admin account that reaches an admin endpoint to function logs. |
| E-040 | `admin-grant-licence/index.ts` L85-86, `admin-revoke-licence/index.ts` L66-67, `admin-force-signout/index.ts` L113-119: log the acting admin's email and target user id. |
| E-041 | `admin-user-detail/index.ts` L45-80: returns profile (email, name, phone, country, signup platform, deleted_at), licence, payments, orders, devices (**incl. fingerprint**), sessions. L4-10: read-only, writes nothing to audit_log. |
| E-042 | `admin-list-users/index.ts` L102-116: lists and searches by email, first/last name, phone, country. `admin-list-payments/index.ts` L85-152: payer email/phone. `admin-audit-log/index.ts` L62-121: shows `ip`, `actor_email`, and resolves subject emails. `admin-overview/index.ts` L5: writes nothing to audit_log. **Admin reads are not logged.** |
| E-043 | `admin-request-otp/index.ts` L180-195: `shouldCreateUser: true` for allow-listed admins → admins become `auth.users` rows and therefore also get `profiles` + `licences` rows and an activation email (via E-018). |

### Flutter app — `lib/`, `android/`, `pubspec.yaml`
| ID | Evidence |
|---|---|
| E-050 | `pubspec.yaml` L15-65: provider, shared_preferences, fl_chart, google_fonts, permission_handler, lottie, intl, package_info_plus, supabase_flutter, flutter_secure_storage, flutter_dotenv, device_info_plus, cryptography, **sentry_flutter 9.27.0**. **No analytics or ads SDK.** |
| E-051 | `android/app/src/main/AndroidManifest.xml` L4-26 permissions: INTERNET, ACCESS_WIFI_STATE, CHANGE_WIFI_STATE, ACCESS_NETWORK_STATE, BLUETOOTH & BLUETOOTH_ADMIN (maxSdk 30), BLUETOOTH_SCAN (neverForLocation), BLUETOOTH_CONNECT, BLUETOOTH_ADVERTISE, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION (**no maxSdkVersion**), WAKE_LOCK. L31-36: **no `android:allowBackup`, no `fullBackupContent`, no `dataExtractionRules`**. |
| E-052 | Merged release manifest (owner's folder, `build/app/intermediates/packaged_manifests/release/…/AndroidManifest.xml`, 22 Sep 2026): same permission set plus a Sentry provider/receiver and `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`; `minSdkVersion 24`, `targetSdkVersion 36`; no allowBackup attribute → Android default (backup enabled). |
| E-053 | `lib/services/bluetooth_classic_service.dart` L122-129: runtime request is BLUETOOTH_CONNECT + BLUETOOTH_SCAN on API ≥31, **locationWhenInUse on API <31** only. No location plugin in pubspec (E-050); no code reads location. No usage of BLUETOOTH_ADVERTISE, CHANGE_WIFI_STATE or WAKE_LOCK found in Dart/Kotlin. |
| E-054 | `lib/services/trip_logger.dart` L39 `logPoint(…lat, lng, altitude)`; grep finds **no caller** passing coordinates. Trips stored in SharedPreferences (L126-133); CSV export copies to clipboard (`trip_history_screen.dart` L77). |
| E-055 | `lib/services/supabase_service.dart` L88-171: Supabase session and PKCE verifier stored in `flutter_secure_storage` (EncryptedSharedPreferences, Keystore master key). L308-315 signup metadata `{signup_platform, country_code}`. L385-422 writes first/last name and phone to `profiles` after OTP. |
| E-056 | `lib/services/session_service.dart` L25-45, L166-203: fingerprint = SHA-256 of a **random 256-bit per-install secret** (no hardware identifiers); L207-216 model = manufacturer + model; secure-storage keys `danlite_session_id_v1`, `danlite_device_secret_v1`. |
| E-057 | `lib/services/entitlement_service.dart` L171-175, L204-205: entitlement token and last-server-time in secure storage (`danlite_entitlement_token_v1`, `danlite_entitlement_last_server_time_v1`). |
| E-058 | `lib/providers/vehicle_provider.dart` L15, L39, L79-136: vehicle profiles incl. **VIN**, make, model, year, notes in **plain SharedPreferences**. `settings_provider.dart` L59-65: language, units, adapter Wi-Fi IP/port, dashboard PIDs. `chassis_address_memory.dart` L1-96: learned ABS addresses keyed by make+model, SharedPreferences, **local only**. |
| E-059 | `lib/services/error_reporting_service.dart` L80-100: Sentry init with `sendDefaultPii=false`, `maxRequestBodySize=never`, `tracesSampleRate=0.05`; enabled only if `SENTRY_DSN` non-empty. |
| E-060 | Pub cache `sentry_flutter-9.27.0/lib/src/integrations/debug_print_integration.dart` L21-60: in **non-debug builds**, every `debugPrint` call is turned into a Sentry breadcrumb; `sentry-9.27.0/lib/src/sentry_options.dart` L332 `enablePrintBreadcrumbs = true` (default), L76 max 100 breadcrumbs. The app does not override this (E-059). |
| E-061 | `lib/services/obd_service.dart` L218-224: `_logWire` calls `debugPrint('[WIRE] … TX>/RX< …')` for **every OBD command and response frame**. Combined with E-060, raw diagnostic traffic (fault-code responses, PIDs) is attached as breadcrumbs to any Sentry error event. Other debugPrints: `entitlement_provider.dart` L196 prints status/expiry (no user id). |
| E-062 | Owner's `.env` (bundled into the APK as `assets/flutter_assets/.env`, verified in the APK listing): keys `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`; `SENTRY_DSN` is **non-empty** and its ingest host is the **EU (`de`)** region. Values not reproduced. |
| E-063 | Pub cache `google_fonts-6.3.3` `google_fonts_all_parts.g.dart` L44 `allowRuntimeFetching = true`; `lib/theme/app_theme.dart` L32-122 uses `GoogleFonts.nunito`; no font files bundled under `assets/` → the app **downloads fonts from Google at runtime**. |
| E-064 | `lib/screens/auth/signup_screen.dart` L34-43: country list **IN, US, GB, AE, CA, AU, SG, DE**; fields: country, full name (required), email, phone (optional); L264 shows `auth_privacy_note`; **no consent checkbox, no Terms/Privacy link**. `login_screen.dart` L236 shows `auth_privacy_note`. |
| E-065 | `lib/screens/account_screen.dart` L47 `kBillingDomain = https://billing.danlite.in`; L66-81 legal URLs "Rendered as SelectableText, never launched"; L683-686. Reached only from Settings (`settings_screen.dart` L171), which is behind the paywall gate (`auth_gate.dart` L39-41, L219-222; `app_strings.dart` L693-695). **Unlicensed users never see a privacy-policy link in the app.** |
| E-066 | `lib/screens/paywall_screen.dart` L15-23: `kPaywallSupportContact = 'support@danlite.example' // [CONFIRM]` — a **reserved, non-working domain** shown to customers as the support address (also on the Account screen). |
| E-067 | `lib/screens/paywall_screen.dart` L170-230: "Email me a new link" invokes `send-activation` (Path B) with the account's email. The email it triggers says "Continue to checkout" (E-034). |
| E-068 | `lib/screens/dtc_screen.dart` L31-56: `clearOutcomeMessageKey` returns `'clearSucceeded'` **unconditionally**; colour always success; the real outcome is still computed but not shown. L576-584: "No fault codes" screen shows `noFaultCodesDesc`. |
| E-069 | `lib/screens/about_screen.dart` L27-39 feature claims incl. "23 Indian Languages — Full UI…", "Works with all ELM327 OBD2 adapters", "HUD Mode — Heads-up display for night driving"; L88-92 legal note ("original application… informational purposes only… Do not operate the device while driving"). English-only, hard-coded. |
| E-070 | `lib/constants/chassis_dtc_dictionary.dart` L34-41 data provenance: Classic 350 table from "owner's photographs of the Classic 350 service manual"; Bullet EFI from "the publicly hosted … service manual, page 167". Brand names appearing in app code/strings: Honda, Bosch, Royal Enfield, Suzuki, Yamaha, Bajaj, KTM, Hero, OBDLink, Vgate, PLX. Only own logo assets (`assets/images/logo*.png`). |
| E-071 | `lib/constants/app_strings.dart` — claim strings (English line / Hindi line): `auth_privacy_note` 551/1174 "Your email is used only to secure your account."; `auth_phone_note` 534/1157 "For support only. We never send codes or messages to this number."; `auth_signup_subtitle` 514/1141; `account_logout_confirm_body` 699/1268 "You will need your email **or phone**…"; paywall block 601-661 (Hindi from 1203); `paywall_resend_cta` 642/1224; `paywall_resend_sent` 646/1227; `account_purchased_via` 712/1276; `account_legal_*` 737-739/1299; `noFaultCodesDesc` 176 "Your vehicle has no stored DTCs. Great news! 🎉" (+hi 848, bn 1454, te 1674, mr 1929, ta 2184, gu 2439, kn 2694, ml 2949, pa 3228, ne 3724); `clearSucceeded` 188/852; `clearWarning` 179 (+10 languages); `legalText` 454 (+hi 1130, bn 1520, te 1765, mr 2020, ta 2275, gu 2530, kn 2785, ml 3040, pa 3319, ne 3815); `absNoFaultsDesc` 221/974. |
| E-072 | Same file: every `auth_*`, `paywall_*`, `account_*` key exists **only in `en` and `hi`**; the other 21 languages fall back to English (awk key→language map, 30 Sep 2026). `l10n/app_*.arb` contain only generic UI labels (incl. "Privacy Policy", "Terms of Service") — no claims. |

### Billing portal — `portal/`
| ID | Evidence |
|---|---|
| E-080 | `portal/app/legal/layout.tsx` L34-40: live banner "DRAFT — for client and legal review. Not yet approved for publication… must not be published as-is." Pages set `robots: NOINDEX`. |
| E-081 | `portal/app/legal/privacy/page.tsx`: names Supabase, Resend, "SMS provider for Indian one-time passcodes [CONFIRM: MSG91…]", Razorpay; says consent is "given at signup"; says deletion "marks it for erasure immediately"; says no analytics on the portal; many `[CONFIRM]` placeholders (entity, address, contact, grievance officer). |
| E-082 | `portal/app/legal/terms/page.tsx`: price ₹129 / US$1.29; licence "revocable"; single active device; "keep access to your email address **or mobile number** secure"; revoke for "reversed or disputed payment"; liability cap = price; `[CONFIRM: city]` jurisdiction. |
| E-083 | `portal/app/legal/refund/page.tsx`: full refund within **24 hours** if "not yet activated on a device"; "or use the mobile number on your account"; `[CONFIRM]` decision window. |
| E-084 | `portal/app/checkout/page.tsx` L176-338: price table; "**By paying you accept the Terms and Refund policy**" (text + links, **no checkbox, no record**); Privacy only in footer. |
| E-085 | `portal/app/confirmation/page.tsx` L183-213: receipt rows = Billed to, Amount, GST, Payment reference, Invoice number, Date. **No supplier legal name, address, GSTIN, SAC code, place of supply, recipient state, or export (LUT) endorsement.** L125 intl shows "Nil — zero-rated export of service". `portal/app/account/page.tsx` L10-13, L395: "Download invoice" rendered disabled. No code sends a receipt or invoice email (grep of functions/portal). |
| E-086 | `portal/lib/gst.ts` L14 `GST_TREATMENT='inclusive'` (placeholder), L15 rate 18 "CONFIRM", L30 `GST_ON_EXPORTS=false` "CONFIRM", L38-41 prices 12 900 paise / 129 cents; L137-151 invoice "Billed to" = name, else email. |
| E-087 | `portal/lib/supabase/server.ts` L47-49 and `portal/proxy.ts` L58-60: session cookies `httpOnly`, `secure` in production, `sameSite=lax`. `portal/app/checkout/pay-button.tsx` L72 loads `checkout.razorpay.com/v1/checkout.js`; L118/L193 loads Google reCAPTCHA Enterprise **only when a site key is configured**; L258-260 passes prefill. `portal/app/layout.tsx` uses `next/font/google` (self-hosted at build). No analytics script found. |
| E-088 | `portal/app/page.tsx`: root redirects to `https://danlite.in`. `portal/app/robots.ts`: disallow all. `portal/lib/rate-limit.ts` L32, L91-93: in-memory IP buckets (not persisted). |

### Live observations (read-only, 30 Sep 2026)
| ID | Evidence |
|---|---|
| E-090 | `curl -I` billing.danlite.in legal pages: 200, `platform: hostinger`, `Server: hcdn`, Mumbai edge, `x-robots-tag: noindex, nofollow`, `Content-Security-Policy: upgrade-insecure-requests` only; **no HSTS, no frame-ancestors/X-Frame-Options** observed; no Set-Cookie on legal pages. `/checkout` → 307 `/activate` when signed out; `/` → 307 `https://danlite.in`. |
| E-091 | danlite.in: WordPress + WooCommerce + Elementor on Hostinger LiteSpeed; loads WooCommerce `order-attribution` and `sourcebuster` scripts (tracking cookies). WP REST read of pages: `privacy-policy` (modified 2025-06-26) is a generic website policy about accounts, shipping addresses, cookies — not the app; `refund_returns` (modified 2025-06-26) **begins "This is a sample page."**, a 30-day physical-goods returns template that lists "Downloadable software products" as non-returnable. |
| E-092 | Supabase catalog (see q-files in the investigator's scratchpad, not committed): **row counts** — profiles 11 (0 with deleted_at), licences 11 (6 active), payments 7 (all INR; 6 captured, 1 refunded), orders 11 (0 with billing address), devices 18, sessions 31, webhook_events 15, **consent_records 0**, audit_log 14 (**0 with ip**; 9 with actor_email), activation_tokens 26 (**26 expired, none purged**), activation_requests 17 (all with IP), admin_users 2, admin_otp_requests 12 (all with IP), intl_order_attempts 0; auth.users 11, auth.sessions 25 (**25 with IP**), auth.refresh_tokens 44, auth.audit_log_entries 0, auth.one_time_tokens 2, auth.flow_state 58, auth.identities 11. Earliest rows: 13–16 Aug 2026. |
| E-093 | Live FKs: every user-linked table **CASCADE** from `auth.users` except `payments` = **RESTRICT** and `audit_log.actor_user_id` = SET NULL; `audit_log.user_id`, `activation_requests`, `admin_otp_requests`, `webhook_events` have **no FK** (survive user deletion). `sessions.device_id` CASCADE from devices. |
| E-094 | Live triggers: `on_auth_user_created`; `profiles_protect_fields`, `profiles_updated_at`; `licences_updated_at`, `on_licence_created_send_activation`; `audit_log_no_rewrite`, `audit_log_no_truncate`. Event trigger `ensure_rls` / function `rls_auto_enable` exist live but not in migrations (platform-provided or drift — UNKNOWN). |
| E-095 | Live grants: `authenticated` = SELECT on consent_records, licences, payments, sessions; SELECT+UPDATE on profiles; SELECT+INSERT+UPDATE on devices. `service_role` holds **TRUNCATE** on activation_requests, admin_otp_requests, activation_tokens, consent_records, devices, sessions, licences, orders, payments, webhook_events, profiles; **DELETE only** on profiles and webhook_events. |
| E-096 | Live extensions: pg_net, pg_stat_statements, pgcrypto, supabase_vault, uuid-ossp; **pg_cron not installed**; storage: 0 buckets, 0 objects; Postgres 17.6. `activate_licence_from_payment` body does **not** mention `razorpay_intl`; `handle_new_user` does not mention consent. |
| E-097 | Live JSON **key names**: `payments.raw_payload` = `_webhook, amount, captured, created_at, currency, fee, id, method, notes, order_id, status, tax`; `notes` = `order_id, user_id`. `audit_log.detail` keys: `code, function, had_session_id, issued_licence_status, licence_id, orderId, paymentId, purchase_rail_after/before, real_licence_status, reason, revoke_reason, sessions_revoked, status_after/before`. `audit_log.action` values: admin.force_signout ×1, admin.licence_granted ×4, admin.licence_revoked ×4, **paywall_emergency_bypass_used ×1**, webhook.payment_failed ×2, webhook.unknown_order ×2. `auth.users.raw_user_meta_data` keys: `country_code, email, email_verified, phone_verified, signup_platform, sub`. Licences: razorpay_in/active 6, (null)/inactive 5. Invoice numbers: 7 in series `INV/2026-27/…`. Webhook events: payment.captured 11, payment.failed 2, refund.created 1, refund.processed 1. Session revoke reasons: superseded 13, reissued_same_device 12, active 6. |
| E-098 | Live auth schema columns: `auth.sessions` has `ip` and `user_agent`; `auth.audit_log_entries` has `ip_address` and `payload`; `auth.users` has email, phone, metadata, `last_sign_in_at`. |
| E-099 | Supabase CLI `projects list`: region **ap-south-1**; DB 17.6. `curl` of the project's auth health endpoint: `Server: cloudflare` (Supabase API is fronted by Cloudflare). |
| E-100 | DNS (8.8.8.8): `mail.danlite.in` has Resend DKIM (`resend._domainkey`) and `send.mail.danlite.in` MX `feedback-smtp.ap-northeast-1.amazonses.com`; `danlite.in` and `billing.danlite.in` MX = Hostinger; `_dmarc.danlite.in` = `p=none`. |
| E-101 | GitHub API: repository is **private**, 1 collaborator, 0 webhooks; 41 workflow runs; **39 backup artifacts** currently stored (≈0.36 MB each), earliest expiring 11 Dec 2026, each expiring 90 days after creation. |
| E-102 | `.github/workflows/backup-database.yml` L11-18 nightly 22:00 UTC; L108-110 DB URL + age **public** key only; L135-140 artifact `retention-days: 90`; `scripts/backup-database.sh` L199: dump covers `public`, **`auth`**, `storage` schemas. `docs/RUNBOOK.md` L15-16: project is on the Supabase **free tier**; L741-752: Sentry IP storage not yet prevented as of writing. |
| E-103 | Live catalog (counts only): Vault secret named `activation_webhook_secret` **exists** (1); **11** `activation_tokens` were created within 5 minutes of their user's `auth.users.created_at`; 10 users were created after the trigger was installed. I.e. the signup → activation (checkout) email trigger **does fire in production**. |

### Evidence gaps (things that could not be observed)
- Supabase Auth email (OTP) sender: Supabase default SMTP or custom SMTP (Resend?) — UNKNOWN.
- Whether Razorpay live or test keys are configured; whether the 7 invoice numbers were test-mode payments — UNKNOWN.
- Sentry project settings (IP storage, data scrubbing, retention) — UNKNOWN (dashboard not accessed).
- Hostinger access-log retention; Supabase platform log retention for this plan — UNKNOWN.
- Admin portal production URL and hosting — UNKNOWN (not found in repo or DNS probes).
- Google Play listing: developer/entity name, current Data Safety answers, whether any build is published — UNKNOWN.
