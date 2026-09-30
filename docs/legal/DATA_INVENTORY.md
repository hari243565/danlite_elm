# Danlite ELM — Data inventory and data-flow map ("record of processing")

**Status:** fact base as built, 30 Sep 2026, commit `71e2783`. Not legal advice. Every row cites
evidence in [SOURCES.md](SOURCES.md). "UNKNOWN — owner to confirm" means the fact could not be
observed read-only. Retention "as built" means what the system actually does today, not what any
draft policy says.

**Who is who (proposed, to be confirmed — see OPEN_QUESTIONS Q1):** the business selling the licence
is the *data fiduciary* (DPDP) / *controller* (GDPR). Its legal name, address and GSTIN are UNKNOWN
(the draft policies carry `[CONFIRM]` placeholders — E-081).

**Systems in scope**
1. Android app "OBD Danlite" (Flutter) — `lib/`, `android/`.
2. Billing portal `billing.danlite.in` (Next.js on Hostinger) — `portal/`.
3. Admin portal (Next.js) — `admin/`; production URL UNKNOWN.
4. Supabase project (Postgres + Auth + Edge Functions), region ap-south-1 (E-099).
5. Backup pipeline (GitHub Actions → encrypted artifacts) — E-101, E-102.
6. Third parties: Razorpay, Resend (+Amazon SES), Sentry, Google (Fonts, reCAPTCHA, Play, Android backup), Hostinger, Cloudflare, GitHub.
7. Adjacent, not in this repo: the WordPress/WooCommerce site `danlite.in`, which the portal's root redirects to (E-088, E-091).

---

## 1. Inventory tables

Column key: **Req?** R = required to use the product, O = optional, A = automatic (collected without the user typing it).

### 1.1 Account and identity

| ID | Data item | Where collected | Where stored | Sent to | Purpose | Req? | Retention as built | Who can access | Deletion behaviour today | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| D-01 | Email address | App signup/login screen (email OTP) | `auth.users.email`, `auth.identities`, `auth.users.raw_user_meta_data.email`, `public.profiles.email` | Supabase Auth (OTP mail via Supabase's configured SMTP — sender UNKNOWN); Resend (activation emails); Razorpay Checkout (prefill); shown on portal checkout/receipt ("Billed to" fallback); admin portal | Login; activation/purchase link; payment prefill; invoice recipient fallback; support lookup | R | Indefinite (no expiry) | User (own row via RLS); service_role; the 2 admins via admin portal; Supabase staff (platform) | No self-service deletion. Manual `auth.users` delete cascades to `profiles` but **fails for any user with a payment** (payments RESTRICT) | E-010, E-025, E-033, E-034, E-042, E-055, E-064, E-085, E-093, E-097, E-098 |
| D-02 | Full name (first/last) | App signup ("Full name", required on screen) | `public.profiles.first_name/last_name` | Portal receipt ("Billed to"); admin portal | Invoice recipient; support | R (screen) / nullable in DB | Indefinite | User (can edit via API — client-writable); service_role; admins | Cascades with profile (see D-01 caveat) | E-024, E-055, E-064, E-086 |
| D-03 | Phone number | App signup (optional) | `public.profiles.phone` | **Razorpay Checkout prefill `contact`**; admin portal search; `send-activation` Path B lookup | "For support only" per app copy; in practice also payment prefill | O | Indefinite | User; service_role; admins | Cascades with profile | E-024, E-033, E-034, E-042, E-071 |
| D-04 | Country (8 choices: IN, US, GB, AE, CA, AU, SG, DE) | App signup selector | `profiles.country_code`; `auth.users.raw_user_meta_data.country_code` | Determines price/currency sent to Razorpay | Pricing rail; tax treatment | R | Indefinite | User (read only; cannot change); service_role; admins | Cascades | E-013, E-025, E-064, E-097 |
| D-05 | Signup platform (`android`/`web`) | Automatic | profiles; auth metadata | — | Bookkeeping | A | Indefinite | as above | Cascades | E-013, E-097 |
| D-06 | Auth user id (UUID) | Automatic | every table | Razorpay (order `notes.user_id`, receipt prefix), entitlement token `sub`, Sentry? (not attached by code) | Primary key; order cross-check | A | Indefinite; **survives deletion** in `audit_log.user_id`, Razorpay notes, backups | service_role; admins; Razorpay | Not erased where no FK | E-030, E-033, E-036, E-093 |
| D-07 | OTP codes / magic-link hashes / PKCE flow state | Supabase Auth | `auth.one_time_tokens` (2 rows), `auth.flow_state` (58 rows), `auth.refresh_tokens` (44) | — | Authentication | A | Platform-managed; flow_state rows accumulate (UNKNOWN whether GoTrue prunes) | Supabase | Cascade on user delete (platform behaviour, UNKNOWN in detail) | E-092, E-098 |
| D-08 | **Auth session IP address and user agent** | Automatic, every Supabase Auth session (app and portal) | `auth.sessions.ip`, `auth.sessions.user_agent` (25/25 rows have IP) | — | Supabase Auth internal | A | Until session row removed by platform — UNKNOWN | service_role / postgres; Supabase staff; **backups** | Platform cascade (UNKNOWN) | E-092, E-098 |
| D-09 | Consent record (policy version, time, IP, UA) | **Never collected** — table exists, 0 rows, no writer | `public.consent_records` | — | Intended: proof of consent | — | n/a | user (select own) | Cascades | E-014, E-092, E-095 |

### 1.2 Licence, purchase and tax

| ID | Data item | Where collected | Where stored | Sent to | Purpose | Req? | Retention as built | Who can access | Deletion today | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| D-10 | Licence status, product `LIFETIME_V1`, rail, purchased_at, revoked_at, revoke_reason (free text incl. refund id/amount or admin's typed reason) | Automatic (signup trigger, webhook, admin action) | `public.licences` | Entitlement token (`lic`) | Entitlement | A | Indefinite | User (own row); service_role; admins | Cascades on user delete (licence lost) | E-019, E-023, E-036 |
| D-11 | Orders: Razorpay order id, amount, currency, status; **INTL only:** billing country, billing postal code, risk signals (AVS, bot verdict) | Portal checkout (INTL fields typed by customer) | `public.orders` (11 rows, 0 with billing data) | Razorpay (amount, currency, receipt, notes) | Reconciliation; fraud/dispute evidence | R (INTL address fields: submitted by form — required/optional status in UI UNKNOWN) | Indefinite | service_role; admins | Cascades on user delete | E-026, E-033, E-092 |
| D-12 | Payments: Razorpay payment/order id, amount, currency, status, invoice no., redacted gateway entity (method name, fee, tax, notes.user_id) | Razorpay webhook | `public.payments` (7 rows) | — | Proof of sale; tax records; idempotency | A | Indefinite; **blocks user deletion** (RESTRICT) | User (own rows); service_role; admins | Cannot be deleted by service_role (no DELETE grant); FK RESTRICT | E-011, E-030, E-093, E-095, E-097 |
| D-13 | Card/UPI/bank details | Razorpay Checkout (in the customer's browser, Razorpay's iframe/script) | **Not stored by Danlite** (dropped by redaction) | Razorpay only | Payment | R for purchase | n/a for Danlite; Razorpay per its terms | Razorpay | n/a | E-030, E-087 |
| D-14 | Card issuing country (INTL) | Razorpay webhook payload | Only the derived AVS verdict in `audit_log.detail` | — | Fraud signal (advisory) | A | Indefinite (audit_log is append-only) | service_role; admins | Not erasable (trigger) | E-032 |
| D-15 | Invoice / receipt view | Portal `/confirmation` | Rendered from payments + profiles | Customer's browser | Receipt | A | n/a (rendered on demand) | Customer | n/a | E-085 |

### 1.3 Device, session and entitlement

| ID | Data item | Where collected | Where stored | Sent to | Purpose | Req? | Retention as built | Who can access | Deletion today | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|
| D-20 | Device fingerprint = SHA-256 of a random per-install secret (no hardware IDs) | App, after login | Server: `devices.fingerprint`; phone: secret in secure storage | Supabase `claim-session` | One-active-device enforcement | A | Server: indefinite. Phone: survives logout; removed on uninstall/clear data | service_role; **admins see fingerprint** | Cascades on user delete | E-037, E-041, E-056 |
| D-21 | Device model (manufacturer + model) | App (`device_info_plus`) | `devices.model`; shown in portal account page and admin portal | Supabase | "Which device is signed in" display | A | Indefinite | User (own rows); service_role; admins | Cascades | E-037, E-056, E-087 |
| D-22 | App sessions (issued, last seen, revoked, reason) | Automatic | `public.sessions` (31 rows) — no IP/UA | — | Session supersession | A | Indefinite; revoked rows never purged | User (own rows); service_role; admins | Cascades | E-012, E-021, E-092 |
| D-23 | Entitlement token (`sub` user id, `lic`, `sid`, `did`, `iat`, `exp`, signature) | Server-signed | Phone secure storage; 14-day validity | — | Offline licence check | A | Replaced on refresh; 14-day TTL | App only | Deleted on sign-out (`EntitlementProvider._onSignedOut` → `EntitlementService.clear()`, `lib/providers/entitlement_provider.dart` L114-119, `lib/services/entitlement_service.dart` L539-567); session id cleared too | E-036, E-057 |
| D-24 | Last-known server time | App | Phone secure storage | — | Anti clock-rollback | A | Overwritten; deliberately survives sign-out | App | Uninstall / clear data | E-057 |
| D-25 | Portal session cookies (Supabase access/refresh token) | Portal after activation link | Browser cookies (`httpOnly`, `secure`, `lax`) | Supabase | Signed-in portal | A | Supabase session lifetime (UNKNOWN exact) | Browser | Sign-out / expiry | E-087 |

### 1.4 Rate-limit, anti-fraud and audit stores

| ID | Data item | Stored | Content | Retention as built | Can be erased? | Evidence |
|---|---|---|---|---|---|---|
| D-30 | Activation-resend ledger | `activation_requests` (17 rows) | Peppered SHA-256 of the email/phone typed + **client IP** | **Forever** (no purge, no FK) | service_role has no DELETE but **does hold TRUNCATE**; owner can DELETE (no trigger) | E-017, E-034, E-092, E-095 |
| D-31 | Activation tokens | `activation_tokens` (26 rows, all expired) | Token hash, user id, expiry, used_at | Forever (no purge) | Cascades on user delete | E-017, E-092 |
| D-32 | Admin OTP ledger | `admin_otp_requests` (12 rows) | Peppered hash of address typed on admin login, **IP**, was_allowed | Forever | Same as D-30 | E-022, E-092 |
| D-33 | International card-testing ledger | `intl_order_attempts` (0 rows) | user id, **IP**, device hash, outcome | Forever | Cascades on user delete; no DELETE/TRUNCATE for service_role | E-026, E-027, E-092 |
| D-34 | Audit log | `audit_log` (14 rows) | user id (no FK), action, detail (see key names E-097; `reason` is **free text typed by admins**), `ip` column (never populated), `actor_email` (admin addresses, 9 rows) | Forever | **No — append-only trigger blocks UPDATE/DELETE/TRUNCATE for every role** | E-015, E-016, E-092, E-097 |
| D-35 | Webhook idempotency | `webhook_events` (15 rows) | Razorpay event id + event type only (**no payload**) | Forever | service_role has DELETE | E-013, E-092 |
| D-36 | Admin allow-list | `admin_users` (2 rows) | Admin email addresses | Until removed by hand | By hand | E-022 |

### 1.5 Data that stays on the phone

| ID | Data item | Storage | Leaves the phone? | Evidence |
|---|---|---|---|---|
| D-40 | Supabase session + PKCE verifier | Secure storage (EncryptedSharedPreferences, Keystore key) | Only to Supabase as auth | E-055 |
| D-41 | Entitlement token, last server time, session id, device secret | Secure storage | Token/session id sent to Supabase on refresh; secret never (only its hash) | E-056, E-057 |
| D-42 | **Vehicle profiles: nickname, make, model, year, fuel type, engine size, power, weight, VIN (optional), notes** | Plain SharedPreferences | **Not sent to Danlite servers.** May be copied by **Android Auto Backup** to the user's Google account (manifest does not opt out). | E-051, E-052, E-058 |
| D-43 | Trip logs (speed, RPM, coolant etc.; lat/lng fields exist but are never filled) | SharedPreferences (last 50) | Only if the user exports CSV to the clipboard; Auto Backup as above | E-054 |
| D-44 | Settings (language, units, adapter IP/port, gauges) | SharedPreferences | Auto Backup | E-058 |
| D-45 | Learned ABS addresses (keyed by make+model) | SharedPreferences | No (local only by design) | E-058 |
| D-46 | **Live OBD data, fault codes, freeze frame, raw adapter traffic** | Memory; last 200 wire lines in memory | **Yes, partially: every OBD frame is `debugPrint`ed, and in release builds Sentry turns each `debugPrint` into a breadcrumb; the last 100 breadcrumbs are uploaded with any error event to Sentry (EU).** Not sent to Danlite's own servers. | E-059, E-060, E-061, E-062 |

### 1.6 Operational telemetry and logs

| ID | Data item | Where | Content | Retention | Evidence |
|---|---|---|---|---|---|
| D-50 | Sentry app events | Sentry EU (Frankfurt) | Stack trace, device/OS context, breadcrumbs (incl. OBD wire lines, entitlement status lines), 5% performance traces; **IP address + city-level location unless the project setting "Prevent Storing of IP Addresses" is on** (status UNKNOWN) | Sentry plan default — UNKNOWN | E-038, E-059–E-062, E-102, V-02 |
| D-51 | Sentry Edge Function events | Sentry EU | Error, function name, scrubbed context; IP nulled in code but platform may still store (same setting) | UNKNOWN | E-038 |
| D-52 | Supabase Edge Function logs | Supabase platform | Payment/order ids, user ids; **email of non-admin accounts reaching admin endpoints; acting admin's email**; Razorpay error bodies | Plan-dependent — UNKNOWN | E-030, E-039, E-040 |
| D-53 | Supabase API/Auth platform logs | Supabase platform (and Cloudflare in front) | Request metadata incl. IP (platform behaviour) | UNKNOWN | E-099 |
| D-54 | Hostinger access logs (portal) | Hostinger | IP, UA, URLs (standard web server logs) | UNKNOWN | E-090 |
| D-55 | Resend delivery logs | Resend (US) | Recipient email, subject, delivery status; body may be retained | Resend default — UNKNOWN | E-034, E-100, V-03 |
| D-56 | Android logcat | Phone | `debugPrint` output incl. OBD wire lines (visible to adb/bug reports) | Device buffer | E-061 |
| D-57 | Google Fonts requests | Google | IP address and user agent of the phone when fonts are fetched at runtime | Google's terms | E-063 |

### 1.7 Admin portal

| ID | Data item | Shown to admins | Logged? | Evidence |
|---|---|---|---|---|
| D-60 | Customer list/search | email, first/last name, phone, country, signup platform, created, deleted_at, licence summary | **Reads not logged** | E-042 |
| D-61 | Customer detail | profile, licence, payments, orders, devices (incl. fingerprint), sessions | Reads not logged | E-041 |
| D-62 | Payments list | payment/order/invoice ids, amounts, payer email/phone/country | Reads not logged | E-042 |
| D-63 | Audit log view | action, detail, ip, actor_email, subject email | Reads not logged | E-042 |
| D-64 | Actions (grant, revoke, force sign-out) | — | **Logged** in `audit_log` with actor email + reason | E-023, E-040 |

---

## 2. Data-flow diagram

```mermaid
flowchart LR
  subgraph Phone["Android phone"]
    APP[OBD Danlite app]
    SP[(SharedPreferences:\nvehicles incl. VIN, trips,\nsettings, ABS addresses)]
    SS[(Secure storage:\nsession, entitlement token,\ndevice secret)]
    CAR[Vehicle ECU via\nELM327 BT/Wi-Fi adapter]
  end
  subgraph Browser["Customer's browser"]
    PORTAL[billing.danlite.in\nNext.js on Hostinger, Mumbai edge]
    RZPJS[Razorpay Checkout.js]
  end
  subgraph Supa["Supabase ap-south-1 (Mumbai), behind Cloudflare"]
    AUTH[Supabase Auth\nauth.users / auth.sessions (IP, UA)]
    DB[(Postgres public.*)]
    EF[Edge Functions]
  end
  CAR <-->|OBD frames| APP
  APP --> SP
  APP --> SS
  APP -->|email OTP, signup metadata| AUTH
  APP -->|name, phone update| DB
  APP -->|claim-session: fingerprint hash, model| EF
  APP -->|entitlement refresh: session id| EF
  APP -->|resend link: email| EF
  APP -->|errors + breadcrumbs incl. OBD lines| SENTRY[(Sentry EU, Frankfurt)]
  APP -->|font download: IP, UA| GFONTS[Google Fonts]
  SP -.->|Android Auto Backup| GBACKUP[(User's Google account backup)]
  DB -->|licence INSERT trigger via pg_net| EF
  EF -->|activation email: address + link| RESEND[Resend (US data)\nsent via Amazon SES Tokyo]
  RESEND --> INBOX[Customer inbox]
  INBOX -->|link| PORTAL
  PORTAL -->|verify token, create order| EF
  EF -->|order: amount, currency, notes.user_id| RZP[Razorpay]
  PORTAL --> RZPJS
  RZPJS -->|card/UPI data, prefill email+phone| RZP
  RZP -->|signed webhook| EF
  EF -->|payments, licences, audit_log| DB
  EF -->|errors| SENTRY
  EF -.->|reCAPTCHA token (inert today)| RECAP[Google reCAPTCHA Enterprise]
  DB -->|nightly pg_dump incl. auth schema, age-encrypted| GH[(GitHub Actions artifacts\n90 days, private repo)]
  ADMIN[Admin portal\n2 admins] -->|admin-* functions| EF
  PORTAL -->|root redirect| WP[danlite.in\nWordPress/WooCommerce]
```

---

## 3. Sub-processor / third-party register

Role column is a **proposal for the lawyer** (processor = acts on Danlite's instructions;
independent = decides its own purposes for at least part of the data). Terms/DPA links were **not
fetched** in this session (V-06) — the "where to look" column is a pointer, not a verified fact.

| Party | Data received | Why | Processing location (evidence) | Proposed role | Where to look for terms/DPA | Evidence |
|---|---|---|---|---|---|---|
| Supabase | All account, licence, payment, device, session, audit data; auth IPs/UAs; function logs | Database, auth, functions | ap-south-1 Mumbai (V-04); Supabase is a US company — support/ops access location UNKNOWN | Processor | supabase.com/legal (DPA, sub-processors) | E-092, E-099 |
| Cloudflare (via Supabase) | All API traffic incl. IPs | CDN/proxy in front of Supabase | Global edge — UNKNOWN | Sub-processor of Supabase | Supabase sub-processor list | E-099 |
| Hostinger | Portal traffic, IPs in access logs; also hosts danlite.in and business mail (MX) | Web hosting, CDN, email | Mumbai edge observed (E-090); origin UNKNOWN | Processor | hostinger.com legal pages | E-090, E-100 |
| Razorpay | Name? (not sent by code), **email + phone (prefill)**, amount, order notes (user id, billing country), card/UPI/bank data (collected directly) | Payment processing | India (Razorpay is Indian) — INTL card processing locations UNKNOWN | **Mixed**: processor for order data; **independent regulated entity** (payment aggregator) for payment instrument data and its own KYC/fraud/receipt emails | Razorpay Terms, Privacy Policy | E-030, E-033, E-087 |
| Resend | Recipient email, activation link, email content, delivery metadata | Transactional email | Sent from AWS SES **Tokyo** (E-100); **account data, logs stored in the US** (V-03) | Processor | resend.com legal (DPA) | E-034, E-100 |
| Amazon Web Services (SES) | Same as Resend | Delivery | ap-northeast-1 Tokyo | Sub-processor of Resend | Resend sub-processor list | E-100 |
| Supabase Auth mail sender | Email address, OTP code | Login codes | **UNKNOWN** (default Supabase SMTP or custom) | Processor | — | evidence gap |
| Sentry (Functional Software Inc.) | Error events: stack traces, device context, breadcrumbs (incl. OBD wire lines), possibly IP + city | Crash/error monitoring | **EU — Frankfurt** (V-02, E-062) | Processor | sentry.io/legal (DPA) | E-038, E-059–E-062 |
| Google — Fonts | Phone IP + UA on font download | Typeface | Global | Independent (Google's own terms) | Google Fonts FAQ / privacy | E-063 |
| Google — reCAPTCHA Enterprise | Browser signals + token (only if configured; inert today) | Bot scoring on INTL checkout | Global | Processor under Google Cloud terms (to confirm) | Google Cloud DPA | E-033, E-087 |
| Google — Android backup | Plain app prefs incl. VIN; encrypted secure-storage blobs | User's own device backup | Google | Not Danlite's processor (user's own service), but must be disclosed/controlled | Android docs | E-051, E-052 |
| Google — Play | Store listing, installs; would be billing if Play Billing adopted | Distribution | Global | Independent | Play Developer Distribution Agreement | — |
| GitHub (Microsoft) | Source code (incl. owner's email in a migration seed) and **age-encrypted database dumps** | Code hosting, CI, backups | US (GitHub) — UNKNOWN precise | Processor (storage of ciphertext) | GitHub DPA | E-101, E-102 |
| WordPress/WooCommerce plugins on danlite.in | Website visitors' data, tracking cookies (sourcebuster/order attribution) | Marketing/e-shop | Hostinger | Controller's own site | — | E-091 |

---

## 4. Retention schedule (as built vs legal minimum vs recommendation)

| Data | As built | Legal minimum / driver | Recommendation (for owner/lawyer decision) |
|---|---|---|---|
| Account (profile, auth user) | Forever | None; DPDP: erase when purpose served / on request | Keep while licence usable; erase within 30 days of a deletion request, except tax-linked fields |
| Licence record | Forever; lost if user deleted (cascade) | Contract evidence | Keep while account exists; on deletion keep a pseudonymised line (licence id, dates, rail) with the payment record |
| Payments, invoice numbers, orders | Forever; payments block deletion | **GST: 72 months from due date of annual return** (R5a) — ≈ 8 years from sale | Keep 8 years from end of financial year; detach from `auth.users` so accounts can be erased (see RISK T3) |
| Name/email on invoices | Rendered live from profiles; no stored invoice copy | GST invoice must be preserved as issued | Store an immutable invoice snapshot at payment time; keep 8 years |
| Device and session rows | Forever | None | Revoked sessions 90 days; devices 12 months after last seen |
| Auth sessions IP/UA (`auth.sessions`) | Platform-managed — UNKNOWN | DPDP Rule 6: security logs ≥ 1 year (from 13 May 2027) | Confirm Supabase behaviour; disclose |
| Activation tokens | Forever (26 expired rows) | None | Delete 7 days after expiry |
| Activation/admin OTP ledgers (hashed id + IP) | Forever | Rule 6 suggests ≥ 1 year for security logs | Delete after 12 months (rate limit needs only 1 hour) |
| INTL order-attempt ledger (IP, device hash) | Forever | Chargeback evidence window (card networks typically ≤ 540 days — to confirm) | Delete after 18 months |
| Audit log | Forever, cannot be edited | Rule 6 ≥ 1 year; tax/dispute evidence | Keep 8 years for money-related actions; purge others after 2 years by documented procedure |
| Webhook event ids | Forever | None | Delete after 2 years |
| Consent records | none exist | Must be able to **prove** consent (DPDP s.6(10)) | Keep for life of account + limitation period |
| Encrypted backups (GitHub artifacts) | 90 days rolling (39 present) | None | Keep 30–90 days; disclose roll-off; keep a deletion log to re-apply after any restore |
| Sentry events | Sentry default — UNKNOWN | — | 30–90 days; IP storage off |
| Function / hosting logs | UNKNOWN | Rule 6 ≥ 1 year (from 2027) | Confirm; disclose; avoid emails in logs |
| Resend logs | US, Resend default — UNKNOWN | — | Confirm; disclose US storage |
| On-phone data | Until uninstall / clear data | — | Say so plainly; add "clear my data" in app |

---

## 5. Rights-mechanics table (does it work today?)

| Right | DPDP / GDPR basis | Works today? | How | What is missing | Evidence |
|---|---|---|---|---|---|
| Notice at collection | DPDP s.5, Rule 3; GDPR Art 13; Play prominent disclosure | **No** | Signup shows one line: "Your email is used only to secure your account." — inaccurate | Short layered notice listing name, email, phone, country, device model; link to full policy; in the user's language | E-064, E-071, E-072 |
| Consent capture | DPDP s.6; E-Commerce Rules (purchase consent) | **No** | `consent_records` has 0 rows; signup has no checkbox; checkout has passive "By paying you accept…" | Clickwrap at signup and checkout; record version/time/IP | E-014, E-084, E-092 |
| Access / summary | DPDP s.11; GDPR Art 15 | **Partly** | App Account screen shows email, name, phone, country, created date, account id; portal shows devices & receipt | No export; no "what we hold" summary covering devices, sessions, logs | E-065, E-087 |
| Correction | DPDP s.12; GDPR Art 16 | **Partly** | Name/phone writable via API (no in-app edit UI observed); email **cannot** be changed by the user | Edit screen; email-change flow (note E-025: profile email does not follow auth email changes) | E-024, E-025 |
| Erasure / account deletion | DPDP s.12; GDPR Art 17; **Play requirement** | **No** | No in-app path, no web link, no code writes `deleted_at`; a manual delete fails for payers (RESTRICT) | Full design in RISK T3 | E-066 (search), E-093 |
| Withdraw consent | DPDP s.6(4) | **No** | Only "Log out" | Mechanism "as easy as giving consent" | E-071 |
| Grievance redressal | DPDP s.13, Rule 14 (≤ 90 days); E-Commerce Rule 4(5) (48 h / 1 month) | **No** | Support address in app is `support@danlite.example` (non-deliverable); policy pages say `[CONFIRM]` | Real mailbox, named grievance officer, published timelines | E-066, E-081 |
| Nominate | DPDP s.14 | **No** | Mentioned in draft policy only | Process | E-081 |
| Complain to regulator | DPDP (Data Protection Board); GDPR Art 77 | Not stated | — | Wording in policy | E-081 |
| Stop "sale"/marketing | — | n/a (no marketing, no sale found) | — | Keep it that way; say so | E-050, E-087 |
| Device logout (security) | — | **Yes** | Portal "Sign out all devices"; admin force sign-out | — | E-021, E-087 |
