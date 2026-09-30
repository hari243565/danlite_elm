# Claim ledger — the /legal/* pages

**Status:** draft, 30 Sep 2026, branch `chore/legal-drafts`. Not legal advice.
One row per factual sentence group on the billing-portal legal pages. Every row cites evidence
([SOURCES.md](SOURCES.md): `E-nnn`, `V-nn`, `R…`; data IDs `D-nn` in
[DATA_INVENTORY.md](DATA_INVENTORY.md)) or an open question
([OPEN_QUESTIONS.md](OPEN_QUESTIONS.md): `Q-nn`).

**Type key**
- **F** — fact about the system, verified by the cited evidence.
- **D** — a client/owner decision. Either an unresolved placeholder (`{{TODO:…}}`, shown highlighted on the page) or a proposed default written into the text that the client must confirm.
- **L** — a statement about the law. Needs the lawyer or accountant to confirm; the cited R-item says how far it was verified.
- **M** — a promise that today depends on someone doing it by hand (Q-34). If nobody does it, the sentence becomes false.

**Rule for editors:** change this ledger in the same commit as the page text. Any sentence that
cannot be given a row here must be removed.

Page source files: `portal/app/legal/<page>/page.tsx`. Shared text is in
`portal/app/legal/_components/deletion.tsx` (rows DA-xx, rendered on both the Privacy Policy
§13 and the delete-account page). Business values are in `portal/lib/legal-config.ts`; prices come
from `portal/lib/gst.ts`.

---

## All pages (layout, shell)

| ID | Claim | Type | Evidence / question |
|---|---|---|---|
| G-01 | DRAFT banner: "not yet approved… not legal advice"; count of unresolved items | D | Q-32; computed from `legal-config.ts` at build |
| G-02 | Version "0.2 (draft)", last-updated date, version history (0.1 on 15 Aug 2026, 0.2 on 30 Sep 2026) | F / D | `git log -- portal/app/legal` (e3d5ad6, 2026-08-15); date of approval Q-32 |
| G-03 | App shown on the phone as "OBD Danlite"; product/website/emails say "Danlite ELM"; website billing.danlite.in | F | E-111, E-065 |
| G-04 | Play listing name and developer name | D | Q-26 |
| G-05 | Legal name, entity type, registered address, GSTIN | D | Q-01, Q-03 |

## Privacy Policy (`/legal/privacy`)

| ID | § | Claim | Type | Evidence / question |
|---|---|---|---|---|
| P-01 | Summary | Account needs email, name, country; phone optional | F | E-064, E-055 |
| P-02 | Summary, §7 | Creating an account automatically emails a link to buy | F | E-018, E-034, E-103 |
| P-03 | Summary, §2, §8 | Email and phone passed to Razorpay to prefill the payment form | F | E-033 L503-513, E-087 L258-260 |
| P-04 | Summary, §3 | We never see card, UPI or bank details; Razorpay handles them | F | E-030, E-087, D-13 |
| P-05 | Summary, §5 | Vehicle profiles/trips stay on the phone; crash reports can include recent diagnostic messages; Sentry in Germany | F | E-058, E-059–E-062, V-02 |
| P-06 | Summary, §9 | Some providers store data outside India: US, Germany, Japan | F | V-02, V-03, E-100 |
| P-07 | Summary, §10 | Purchase records kept for years for tax law even after deletion; backups keep deleted data up to 90 days | F / L | R5a; E-101, E-102 |
| P-08 | Summary, §13 | Deletion by email; no delete button in the app yet | F / M | E-066 (no deletion code), T3; Q-34 |
| P-09 | Summary, §6 | We do not sell data, show ads or send marketing email | F | E-050 (no ads/analytics SDK), E-087; only transactional senders exist (E-034); DATA_INVENTORY §5 |
| P-10 | §1 | Vehicle diagnostics app for Android; sold through billing.danlite.in | F | E-050, E-065 |
| P-11 | §1 | Operator is the entity in Q-01 and decides purposes → Data Fiduciary; customer = Data Principal (DPDP Act 2023) | D / L | Q-01; R1 (Act), role proposed in DATA_INVENTORY header; Q-33 |
| P-12 | §1 | Policy does not cover Razorpay's window; link to Razorpay's policy | F | V-07, E-087 |
| P-13 | §1, §19 | Privacy email; grievance officer named in §19 | D | Q-11 |
| P-14 | §2 | Email: login code, activation/purchase links, receipt fallback when no name, support lookup | F | E-055, E-034, E-086 L137-151, E-042 |
| P-15 | §2 | Full name asked for on sign-up; shown on receipt as buyer | F | E-064, E-086, E-085 |
| P-16 | §2 | Phone optional; used for support; passed to Razorpay | F | E-064, E-033 |
| P-17 | §2 | Country decides price, currency, tax; chosen at sign-up; cannot be changed by the user | F | E-064, E-086, E-025 |
| P-18 | §2 | Account ID is a random code used in our systems and payment records | F | E-036 (`sub`), E-033 (order `notes.user_id`), E-097 |
| P-19 | §2 | Phone make/model and a random app-generated device ID; not IMEI/serial/advertising ID; for one-phone rule and "which phone is signed in" | F | E-056, E-037, E-051 (no AD_ID/phone-state permission), E-087 |
| P-20 | §2 | Sign-in records: IP address and device/browser type per session, kept by the login provider | F | E-092, E-098 (`auth.sessions.ip`, `user_agent`) |
| P-21 | §2 | Purchase records: order/payment refs, amount, currency, status, invoice number, method type, Razorpay fee and tax | F | E-030, E-097, E-019 |
| P-22 | §2 | International buyers: billing country, optional postcode, checkout IP and device ID, card-country match check | F | E-026, E-032, E-033 L316-372, E-104 |
| P-23 | §2 | Messages you send us | F | (self-evident; support channel Q-11) |
| P-24 | §3 | Location permission requested only on Android 11 and older, only for Bluetooth scanning; location never read | F | E-053 (API < 31 only), E-054, E-050 (no location plugin) |
| P-25 | §3 | No contacts, photos, files, camera or microphone permissions | F | E-051 |
| P-26 | §3 | No advertising or analytics services in the app or on the website | F | E-050, E-087, T19 |
| P-27 | §4 | Data sources: you; phone/browser automatically; Razorpay (status, refs, method, fee, tax, card country); email provider's delivery records held by the provider | F | E-030, E-032, D-55, V-03 |
| P-28 | §5 | App reads fault codes, live data, identifiers via BT/Wi-Fi adapter; stores vehicle profiles (incl. optional VIN), trips, settings on the phone only; not uploaded | F | E-058, E-054, D-42–D-46 |
| P-29 | §5 | Crash report contents: phone model, Android version, app version, error, recent log messages that can include vehicle communication; possibly IP and city-level location; small performance sample | F | E-059 (5% traces), E-060, E-061, E-038 (IP setting UNKNOWN → "may"), Q-23 |
| P-30 | §5 | Fonts downloaded from Google on first run; Google receives IP and request details | F | E-063 |
| P-31 | §5 | Android backup may include settings, profiles, trips; trip export copies to clipboard | F | E-051, E-052, E-054 |
| P-32 | §6 | Purposes table and plain-words bases | F (purposes) / L (bases) | Purposes: D-01–D-57. Bases: Q-33 |
| P-33 | §6 | Withdrawal of consent at any time; not retroactive; withdrawing consent for licence data ends the licence | L / M | DPDP s.6(4) (DATA_INVENTORY §5 "Withdraw consent"); no mechanism exists other than email (T2) — Q-33, Q-34 |
| P-34 | §7 | Login codes sent by the login provider (sender to confirm) | F / D | E-055; Q-22 |
| P-35 | §7 | Activation links sent on account creation and on any request for the address (including by others); single-use; 15 minutes; sender address | F / D | E-018, E-103, E-034 (TTL, Path A public form), E-067; Q-30 |
| P-36 | §8 | Two staff can see account, licence, payment and device records; changes they make are logged | F | E-092 (`admin_users` = 2), E-041, E-042, E-023, E-040 |
| P-37 | §8 | Supabase: database, login, functions; Mumbai | F | V-04, E-099 |
| P-38 | §8 | Cloudflare carries traffic to the database; global network | F | E-099 |
| P-39 | §8 | Razorpay Software Limited, Bengaluru; receives email, phone, amount, account ID, INTL billing country; own legal duties | F / L | V-07, E-033; role (independent vs processor) Q-15 |
| P-40 | §8 | Resend via AWS; sent from Tokyo; account data and logs stored in the US | F | V-03, E-100, E-034 |
| P-41 | §8 | Sentry: crash reports; Frankfurt | F | V-02, E-062 |
| P-42 | §8 | Hostinger hosts the website; standard server logs; location to confirm | F / D | E-090; Q-15 |
| P-43 | §8 | GitHub stores backups encrypted before storage; decryption key not at GitHub; location to confirm | F / D | E-101, E-102 (workflow holds only the age public key); Q-14, Q-15 |
| P-44 | §8 | Google Fonts (own terms); Google reCAPTCHA only when switched on | F | E-063; E-033 L168-212, E-087 L118/L193 |
| P-45 | §8 | Disclosure where the law requires | L | Q-33 |
| P-46 | §9 | Main database in India; processing in US, Japan, Germany, global networks; transfer safeguard | F / D | V-02, V-03, V-04, E-099, E-063; Q-15 |
| P-47 | §10 | Account, devices, sessions, licence kept while the account exists | F | E-092/§4 retention "Indefinite"; E-093 (cascade on deletion) |
| P-48 | §10, DA | Payment records: six years (72 months) from the due date of the annual return; longer if a case is open | L | R5a (VERIFIED, CGST s.36) |
| P-49 | §10 | Security records and audit log periods | D | Q-09 (as built: no expiry — E-017 L175-179, E-016) |
| P-50 | §10 | Provider log periods | D | Q-31 |
| P-51 | §10 | Backups deleted automatically after 90 days | F | E-101, E-102 L135-140 |
| P-52 | §10 | Phone data until uninstall/clear; Android backup per Google settings | F | E-058, E-051 |
| P-53 | §10 | "Automatic deletion is not yet in place for every row; where not, we delete by hand" | F / M | E-096 (no pg_cron), E-017 L175-179; Q-34, B-07, B-26 |
| P-54 | §11 | Database access rules: each customer reads only their own records | F | E-010 (RLS migration), E-095 (authenticated grants on own-row tables) |
| P-55 | §11 | Login by one-time email code; no password | F | E-055, E-064 |
| P-56 | §11 | Tokens in Android encrypted storage | F | E-055, E-057 |
| P-57 | §11 | Activation links single-use, 15 minutes, stored hashed | F | E-017, E-034 |
| P-58 | §11 | Razorpay notifications checked with a cryptographic signature | F | E-105 |
| P-59 | §11 | Data to us and providers over HTTPS | F | E-090, E-099; DATA_SAFETY_WORKSHEET §2 |
| P-60 | §11 | Backups encrypted before they are stored | F | E-102 (age-encrypted in the workflow before upload) |
| P-61 | §11 | Staff access limited to named people; changes logged | F | E-022 (allow-list), E-023 |
| P-62 | §11 | "No system is completely secure"; breach: tell you and report as the law requires | L / M | DPDP (breach intimation, not re-read this session); no runbook exists (A-26) — Q-34 |
| P-63 | §12 | Rights: summary, correction/update, deletion, withdraw consent, nominate, grievance | L | DPDP ss.11–14 as listed in DATA_INVENTORY §5; R1c |
| P-64 | §12 | Correction includes email address (by request) | F / M | E-025 (user cannot change email; profile email does not sync — A-25); done by hand, Q-34 |
| P-65 | §12 | Request by email from the account address; identity check; response time | D / M | Q-11, Q-34 |
| P-66 | §12 | In-app Account screen shows details once licensed; portal account page shows email, phone, country, signed-in phone, sign-out-all | F | E-065, E-107, E-108 |
| P-67 | §12 | Complaint to the Data Protection Board of India | L | R1c |
| P-68 | §14 | Minimum age; app does not ask or check age; under-age accounts deleted | D / F / M | Q-10; E-064; Q-34 |
| P-69 | §15 | Website cookies only to keep you signed in after an activation link; not for tracking; policy pages set none; no analytics/ad cookies | F | E-087, E-090; smoke test in REVIEW_LOG §3 (no Set-Cookie on any /legal route) |
| P-70 | §15 | Razorpay window follows Razorpay's cookie practices | F | E-087 (Checkout.js loaded from checkout.razorpay.com) |
| P-71 | §15 | App: tokens in encrypted storage; profiles/trips/settings in ordinary app storage | F | E-055, E-057, E-058 |
| P-72 | §16 | UK/EU: rights to restrict, object, portability; complain to local authority; bases = contract, legal obligation, legitimate interest | L | R6 (Art 13 VERIFIED); Q-33 |
| P-73 | §16 | UK/EU representative | D | Q-17 (remove if GB/DE dropped) |
| P-74 | §17 | Without email, name, country no account; without account and licence the app cannot be used; phone optional | F | E-064, E-107 |
| P-75 | §18 | Version/date updates; email before changes affecting existing data | D / M | Q-32, Q-34 |
| P-76 | §18 | Notice languages | D | Q-19 |
| P-77 | §19 | Grievance officer name, designation, email; postal address | D | Q-11, Q-01 |

## Terms and Conditions (`/legal/terms`)

| ID | § | Claim | Type | Evidence / question |
|---|---|---|---|---|
| T-01 | Summary | One-time licence, no subscription | F | E-019 (`LIFETIME_V1`), E-084 |
| T-02 | Summary, §5 | "Lifetime" = while we run the service; licence checked at least every 14 days | F / D | E-036; Q-06 |
| T-03 | Summary, §4 | One person; one phone at a time; new sign-in signs the old phone out | F / D | E-021; personal/non-transferable is a client decision carried from draft 0.1 (E-082) |
| T-04 | Summary, §6 | Bought on the website via an emailed link, not in the app; Razorpay handles payment | F | E-018, E-034, E-035, E-033; app has no checkout (E-065 comments, `app_strings.dart` L588-600) |
| T-05 | Summary, §7 | Any refund, full or partial, ends the licence; duplicate-payment refund exception (licence switched back on) | F / M | E-019 L199-204, E-020, E-106; re-grant by hand E-023, Q-34, B-23 |
| T-06 | Summary, §16 | Consumer-law rights kept; consumer commission where you live | L | R4c (UNVERIFIED) — lawyer |
| T-07 | Safety box | Never use while riding/driving; HUD and performance tests only as passenger/closed course | D | Features exist: E-069, E-071; safety rule is policy (A-15, Q-18) |
| T-08 | Safety box, §9 | Not an inspection; brake/ABS faults need a mechanic | D | P7 of the brief; E-069 existing legal note |
| T-09 | Safety box | "No fault codes" ≠ safe; some systems unreadable; many adapters cannot reach ABS | F | T14; E-071 (ABS copy `absNoModuleDesc`, adapter notes) |
| T-10 | Safety box | Clearing codes can hide faults; the app may show success even if the clear was not accepted; re-read codes | F | E-068 (`clearSucceeded` unconditional) |
| T-11 | §1 | Parties; app names; policies form part of the terms | D / F | Q-01, Q-26; E-111 |
| T-12 | §2 | Agreement by creating an account or buying | D / L | No clickwrap exists (T2, E-064, E-110) — enforceability weak until B-04/B-20; Q-33 |
| T-13 | §2 | Minimum age | D | Q-10 |
| T-14 | §3 | Account by email; one-time code each login; no password; anyone reading your email can log in | F | E-055, E-064 |
| T-15 | §3 | Country sets price/currency; user cannot change it | F | E-025, E-086 |
| T-16 | §3 | Report misuse to support email; sign out every device from the portal account page | F / D | E-087, E-108 (sign-out-all); Q-11 |
| T-17 | §4 | Licence is permission to use, personal (incl. own workshop), not transferable | D | Carried from draft 0.1 (E-082); lawyer |
| T-18 | §4 | One phone at a time; previous phone signed out without warning; unlimited phone moves | F | E-021 (last login wins; no device-count limit) |
| T-19 | §4 | Works offline up to 14 days; then must connect once | F | E-036 L32, E-071 `activate_body` |
| T-20 | §4 | Licence ends if the account is deleted; cannot be restored | F | E-093 (cascade) ; payers by hand, Q-34 |
| T-21 | §5 | No end date/renewal fee while we operate; not tied to phone/vehicle life | D | Q-06 |
| T-22 | §5 | App needs our servers; stops within 14 days if they stop | F | E-036; A-14 |
| T-23 | §5 | Shutdown notice period and remedy | D | Q-06 |
| T-24 | §5 | No promise to support every Android version/phone/adapter/vehicle in future | D | Q-06 |
| T-25 | §6 | Prices (India INR, elsewhere USD) | F | Imported from `lib/gst.ts` (E-086); smoke test REVIEW_LOG §3 |
| T-26 | §6 | Purchase steps; app takes no payments; Razorpay window; licence switches on when Razorpay confirms | F | E-018, E-034, E-035, E-030, E-019; E-065 |
| T-27 | §6 | Price change applies only to new purchases; never affects a bought licence | F | One-time product with no renewal (E-019) |
| T-28 | §8 | Prohibited uses (sharing, reselling, reverse-engineering, bypassing licence, server interference, hiding faults, tampering, unlawful use) | D | Client/lawyer; carried in part from E-082 |
| T-29 | §9 | Readings can be incomplete/wrong if a component or adapter is faulty | F | T14; E-071 adapter/ABS notes |
| T-30 | §9 | Fault-code descriptions are general reference, may be incomplete or differ by model | F | E-070 (sourced tables), T15 |
| T-31 | §9 | Performance figures are estimates from sensor data | F | E-069 (0-100, quarter mile, dyno features computed in-app) |
| T-32 | §10 | Needs an ELM327-compatible adapter bought elsewhere; many cannot read ABS; we do not make/sell/guarantee adapters | F | E-053, E-071; no adapter product sold (E-019 single product) |
| T-33 | §10 | Readable data depends on vehicle; no guarantee every feature works with every vehicle | F | E-071 (ABS/adapter capability copy) |
| T-34 | §11 | Independent product; not endorsed; names used to identify compatibility; names belong to owners | D / L | T15, E-070; Q-16 |
| T-35 | §12 | Online parts may be unavailable; 14-day offline period covers short outages | F | E-036; A-14 |
| T-36 | §12 | Updates may add/change/remove features; won't remove core features without telling you | D / M | Q-06, Q-34 |
| T-37 | §12 | May temporarily let the app work for everyone during a problem; grants no licence | F | E-036 L84-90 (emergency bypass), E-097 (used once) |
| T-38 | §13 | Grounds to suspend/end: fraud, refund/reversal/chargeback, breach of §8 | D / M | Q-20; chargebacks not automated (E-031) — revoke by hand (E-023) |
| T-39 | §13 | Email first where practical; restore or refund if not at fault | D / M | Q-29, Q-34 |
| T-40 | §14 | Ownership of app and name | D | Client; Q-16 (manual-sourced data) |
| T-41 | §15 | Non-excludable liability preserved; liability for foreseeable loss from breach/negligence; exclusions for misuse; cap at amount paid | L | Lawyer (R4c UNVERIFIED); cap carried from E-082 |
| T-42 | §16 | Indian law; named court city non-exclusively; consumer commission available; no arbitration | D / L | Q-28; R4c |
| T-43 | §16 | Overseas consumers keep mandatory local rights | L | Lawyer (Q-17) |
| T-44 | §17 | Changes: version/date; email before significant changes | D / M | Q-32, Q-34 |
| T-45 | §18 | Notices, entire agreement, severability, assignment, events outside control | L | Lawyer |
| T-46 | Intro | The app calls this page "Terms of Service" | F | E-113 |

## Cancellation and Refund Policy (`/legal/refund`)

| ID | § | Claim | Type | Evidence / question |
|---|---|---|---|---|
| R-01 | Summary, §1 | One-time purchase, no subscription, never charged again | F | E-019, E-084 |
| R-02 | §1 | Closing checkout or Razorpay window charges nothing; creating an account does not commit you | F | Payment only on Razorpay capture (E-030/E-031); new accounts start `inactive` (E-097 licences null/inactive) |
| R-03 | Summary, §2 | Always refund duplicates; charged-but-no-licence → fix or full refund | D | Q-29 (carried from draft 0.1, E-083) |
| R-04 | §2 | Duplicate refund currently revokes the licence automatically; switched back on by hand; app may briefly show "No active licence" | F / M | E-106, E-023; Q-34, B-23 |
| R-05 | §2 | Licence ended by us without fault → restore or refund | D | Q-29 |
| R-06 | Summary, §3 | "Not as described": report within the window; fix or full refund | D | Q-29 |
| R-07 | §3 | Results depend on vehicle and adapter; many adapters cannot read ABS; limits explained in the Terms are not faults | F / D | E-071; Terms T-32/T-33; About-screen contradiction noted (E-069, B-28) |
| R-08 | Summary, §4 | Change-of-mind rule | D | Q-29 (options A/B/C) |
| R-09 | §5 | Not covered: what the vehicle reports; licences ended for fraud/chargeback/breach; statutory rights preserved | D / L | Q-29; R4c |
| R-10 | §6 | Ask by email from the account address with payment reference or invoice number; Account ID from the app; phone option | F / D | E-085 (receipt shows both refs), E-071 `account_id_hint`; Q-11, Q-27 |
| R-11 | §7 | Acknowledge; decide within N; explain refusals | D / M | Q-29 |
| R-12 | §7 | Refund via Razorpay to the original payment method; cannot redirect | F | V-08; refunds arrive as Razorpay events (E-031) |
| R-13 | Summary, §7 | Bank takes several working days (Razorpay: normal refunds 5–7 working days); refund reference after 10 working days | F / D | V-08; Q-29 |
| R-14 | §8 | Any refund incl. partial ends the licence; warn before a partial refund | F / M | E-019 L199-204, E-020, E-106; Q-29, Q-34 |
| R-15 | §9 | Failed/pending payments: email us; we check with Razorpay and switch on or ensure return | D / M | Q-29, Q-34 |
| R-16 | §10 | Disputes/chargebacks: may end licence; restore if decided in our favour | D / M | Q-20; E-031 (no automatic handling), E-023 |
| R-17 | §11 | Tax on refunds / credit notes | D | Q-03 (no credit notes exist today — T6) |
| R-18 | §12 | Overseas refunds in USD; FX/bank differences | F | E-086 (INTL currency USD) |
| R-19 | §13 | Consumer Protection Act 2019 rights preserved; grievance process; consumer commission | L | R4c (UNVERIFIED) — lawyer |
| R-20 | Intro | The app calls this page "Refund Policy" | F | E-113 |

## Delivery Policy (`/legal/delivery`)

| ID | § | Claim | Type | Evidence / question |
|---|---|---|---|---|
| D-01 | Summary, §1 | Digital licence delivered to the account; nothing shipped; no adapters sold | F | E-019 (single digital product `LIFETIME_V1`) |
| D-02 | §1 | App installed from Google Play or wherever we make it available; not emailed | F / D | Q-25 |
| D-03 | §2 | Account creation triggers the link email automatically | F | E-018, E-103 |
| D-04 | §2 | Link signs you in to the billing site and goes to checkout | F | E-035, E-112 |
| D-05 | §2 | Receipt shown after successful payment | F | E-085 |
| D-06 | Summary, §2 | Licence switches on automatically when Razorpay confirms; usually within minutes | F | E-030, E-019; E-071 `paywall_body` ("can take a few minutes") |
| D-07 | Summary, §2 | Open the app on the same account; tap Refresh on "No active licence yet"; internet needed for the first check | F | E-071 (`paywall_title`, `paywall_refresh_cta`, `activate_body`) |
| D-08 | Summary, §3 | Link works once and expires 15 minutes after sending | F | E-034 L37, E-017 |
| D-09 | §3 | New link via `/activate` or in-app "Email me a new link" | F | E-112, E-067 |
| D-10 | §3 | Up to 3 link requests an hour per email address | F | E-034 L40-41 |
| D-11 | §4 | Sender address to look for in spam | D | Q-30 |
| D-12 | §4 | Paid but no licence → email with payment reference; fix or refund | D | Q-29 (R-03) |
| D-13 | §5 | Receipt shows amount, tax, payment reference, invoice number, date | F | E-085 |
| D-14 | §5 | How the tax invoice is delivered | D | Q-03 (no invoice email or download today — E-085, E-108) |
| D-15 | §6 | Countries offered at sign-up (8); confirmation that sales are offered there | F / D | E-064; Q-17 |
| D-16 | §6 | India billed in INR, others in USD | F | E-086 |

## Contact Us (`/legal/contact`)

| ID | § | Claim | Type | Evidence / question |
|---|---|---|---|---|
| C-01 | §1 | Legal name, type, address, GSTIN | D | Q-01, Q-03 |
| C-02 | §1 | Product name and app label; website | F | E-111 |
| C-03 | §2 | Support email, phone, hours | D | Q-11, Q-27 |
| C-04 | §2 | What to include: sign-up email, Account ID from the app, payment reference/invoice number | F | E-071 `account_id_hint`, E-085 |
| C-05 | §2 | We never ask for card number, UPI PIN, CVV, bank password or login code | D | Policy commitment (no code asks for these — E-030, E-087) |
| C-06 | §3 | Grievance officer name, designation, email, phone, postal address | D | Q-11, Q-01 |
| C-07 | §4 | Complaint ack/resolution times; privacy response time; refund decision time | D / L | Q-11, Q-29; legal ceilings R4a (48 h / 1 month, VERIFIED text), R1d (90 days) |
| C-08 | §4 | Consumer commission; Data Protection Board for privacy complaints | L | R4c, R1c |
| C-09 | §5 | Privacy requests by email; deletion steps page | D / F | Q-11; this branch |

## Pricing (`/legal/pricing`)

| ID | § | Claim | Type | Evidence / question |
|---|---|---|---|---|
| PR-01 | Summary, §1 | India total, pre-GST amount, GST amount, "Price includes 18% GST" | F / D | Computed by `priceFor('IN')` from `lib/gst.ts` (E-086: `PRICE_MINOR.IN`, `GST_TREATMENT='inclusive'` placeholder, rate 18 "CONFIRM"); Q-03 |
| PR-02 | Summary, §1 | Elsewhere: USD total; no Indian GST because treated as export | F / D | `priceFor('US')`, `GST_ON_EXPORTS=false` (E-086); Q-05 |
| PR-03 | §1 | We do not add tax of the customer's country | F / L | E-086 (no foreign tax logic); T16, Q-05 |
| PR-04 | §1 | Bank may charge FX / foreign-transaction fees | F | General (not a claim about our system) |
| PR-05 | Summary | One payment; no subscription, renewal or extra fees from us | F | E-084 (checkout rows: licence, GST, total only) |
| PR-06 | §2 | Includes lifetime licence as defined in Terms; one phone at a time; 14 days offline | F | E-021, E-036; Terms T-21 |
| PR-07 | §2 | Not included: adapter, mobile data | F | E-019 (single digital product) |
| PR-08 | §3 | Country decides price and currency; cannot be changed by the user; contact before paying | F | E-025, E-086 |
| PR-09 | §4 | Buy via emailed link, pay in Razorpay window with the methods Razorpay offers; licence switches on automatically | F | as T-26 |
| PR-10 | §5 | Price change only for new purchases; price paid = checkout price; nothing further to pay | F | E-084, E-019 |

## Delete your account (`/legal/delete-account`, and Privacy §13)

| ID | § | Claim | Type | Evidence / question |
|---|---|---|---|---|
| DA-01 | Summary | Page is for the app with its phone label and Play listing/developer names | F / D | E-111; Q-26 |
| DA-02 | How | Email the privacy address from the sign-in address, subject "Delete my account"; no reason needed | D / M | Q-11, Q-34 |
| DA-03 | How | Lost email access: identity check (e.g. payment reference) before acting | D / M | Q-34 |
| DA-04 | How | No delete button in the app; team carries out each request by hand; uninstalling does not delete the account | F / M | E-066 (no deletion path), T3; server-side account (E-092); Q-34 |
| DA-05 | What happens | Confirm; sign out everywhere; end licence; email when done | F / M | Mechanisms exist: `sign_out_all_devices` (E-021), admin force sign-out (E-040), admin revoke (E-023); Q-34 |
| DA-06 | What happens | A deleted licence cannot be restored; would need a new account and purchase | F | E-093 (cascade deletes the licence row) |
| DA-07 | What happens | Completion time | D | Q-08 |
| DA-08 | What we delete | Phone; name/email/country (unless paid); devices, sessions; licence; activation links; unpaid orders; for non-payers the whole account incl. account ID | F / M | Non-payers: `auth.users` delete cascades (E-093). Payers: `payments` FK is RESTRICT (E-011, E-093), so these are targeted deletes by hand — Q-34, B-06, B-26 |
| DA-09 | What we keep | Payers: payment record and receipt details (name or email fallback, amount, tax, payment ref, invoice no., date) and country; kept 72 months from the due date of the annual return | F / L | E-085, E-086 L137-151; R5a; which fields tax law actually needs — Q-03 |
| DA-10 | What we keep | Security records: hashed email + IP of link requests; period | F / D | E-017, E-034; no FK so they survive (E-093); Q-09 |
| DA-11 | What we keep | Audit log by account ID; cannot be quietly edited; period | F / D | E-015, E-016, E-093; Q-09 |
| DA-12 | What we keep | Backups encrypted, auto-deleted after 90 days; used only to recover; deletion re-applied after a restore | F / M | E-101, E-102; no deletion log exists (B-06) — Q-34 |
| DA-13 | What we keep | Providers' own logs; Razorpay keeps its own payment records | D / F | Q-31; V-07, D-13 |
| DA-14 | Phone data | Vehicle profiles, trips, settings on the phone only; remove by uninstall/clear storage; Google backup managed with Google | F | E-058, E-051, E-052 |
| DA-15 | Refunds | Deletion is not itself a refund reason; ask for a refund first | D | Q-07 |

## Legal index (`/legal`)

| ID | Claim | Type | Evidence / question |
|---|---|---|---|
| L-01 | Product sold by the entity; documents apply to the app and billing.danlite.in | D / F | Q-01; E-065 |
