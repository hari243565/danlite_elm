# Danlite ELM — Compliance risk register

**Status:** findings as of 30 Sep 2026, commit `71e2783`. Not legal advice. Evidence IDs refer to
[SOURCES.md](SOURCES.md); data IDs (`D-nn`) to [DATA_INVENTORY.md](DATA_INVENTORY.md); questions
(`Q-nn`) to [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md). Nothing in the product was changed.

**Severity scale**
- **Critical** — blocks Razorpay live keys, Play publication, or lawful operation, or is a statement to customers that is untrue in a way a regulator/store would act on.
- **High** — likely to cause a store rejection, a consumer complaint that would succeed, or a regulatory finding once real customers exist.
- **Medium** — real gap, moderate exposure or easy to fix before it matters.
- **Low** — hygiene.

**Fix types:** W = wording only · C = code · Cfg = configuration/dashboard · OD = owner decision · L = lawyer · A = accountant.

---

## Part 1 — Outcomes for T1 to T20

### T1 — Stale in-app privacy claims · **CONFIRMED** · Critical
**What.** Signup and login show "Your email is used only to secure your account." (E-071, `app_strings.dart` L551; Hindi L1174; the 21 other languages show the English text — E-072). Reality: the email also receives an automatic purchase/activation email the moment the account is created (E-018, E-034: "Open this link to complete your purchase"), is sent to Razorpay as checkout prefill (E-033), is printed on the receipt as "Billed to" when no name exists (E-086), and is searchable by admins (E-042). The same screen also collects name, phone and country (E-064) and the app sends device model and a device fingerprint (E-056).

**Every claim-making string found, tested against reality**

| Key / place | Languages | Claim | Verdict | Evidence |
|---|---|---|---|---|
| `auth_privacy_note` | en, hi (+English fallback) | email used only to secure account | **False** | E-018, E-033, E-034, E-086 |
| `auth_phone_note` | en, hi | "For support only. We never send codes or messages to this number." | **Risky**: Danlite code sends nothing, but the number is passed to Razorpay as `contact` prefill; whether Razorpay then SMSes the customer is UNKNOWN (Q-12) | E-033, E-071 |
| `auth_signup_subtitle` | en, hi | "Your account keeps your licence safe." | OK (marketing) | E-071 |
| `account_logout_confirm_body` | en, hi | "You will need your email **or phone**…" | **Stale** — email-only auth | E-071 |
| `send-activation` GENERIC_OK (server text shown on portal) | en | "If that email **or mobile number** matches…" | Stale | E-034 |
| `paywall_resend_sent` | en, hi | link stops working after 15 min | True (TTL 15 min) | E-034 |
| `activate_body` | en, hi | works offline up to 14 days | True | E-036 |
| `session_superseded_body` | en, hi | signed out because used on another device | True | E-021 |
| About screen | English only, hard-coded | "23 Indian Languages — Full UI in Hindi, Tamil, Telugu, and 20 more" | **Overstated** — auth/paywall/account/legal copy exists only in en+hi; ABS/clear-codes only en+hi | E-069, E-072 |
| About screen | English only | "Works with all ELM327 OBD2 adapters" | **Contradicted** by the app's own ABS copy ("many adapters … cannot read ABS") | E-069, E-071 |
| About screen / `legalText` | en + 10 languages | "original application… informational purposes only… consult a qualified mechanic" | Partly OK; "original" sits uneasily with manual-sourced tables (T15) | E-069, E-070 |
| Portal draft privacy | en | SMS OTP provider, "consent given at signup", "we mark it for erasure immediately", no analytics | **Three false statements**: no SMS rail (email-only since 25 Aug 2026 per migration comment E-024), no consent captured (E-092), no erasure marking exists (E-066) | E-081 |
| Portal draft terms/refund | en | sign-in "by email address or mobile number"; refund "use the mobile number on your account" | Stale | E-082, E-083 |

**Why it matters.** DPDP s.5/Rule 3 (notice must be accurate and itemised); Play User Data policy ("comprehensively disclose"; Data Safety must be accurate — R2b); a misleading privacy statement is also an unfair trade practice risk under CPA 2019.
**Fix.** W (replace with a short layered notice) + C (ship it in all 23 languages or at least the 10 "full coverage" languages) · **Who:** developer + lawyer approves text.

### T2 — No consent capture · **CONFIRMED** · Critical
**What.** `consent_records` exists (E-014) but has **0 rows** (E-092) and no code writes it (search, E-066 note). Signup: no checkbox, no link to Terms or Privacy (E-064). Checkout: the sentence "By paying you accept the Terms and Refund policy" with links, **no checkbox and no record** (E-084); Privacy is only in the footer. The linked pages carry a live banner saying they are drafts "not yet approved for publication" (E-080).
**Why.** Clickwrap evidence is what makes the Terms enforceable; E-Commerce Rules require explicit purchase consent (R4b, unverified detail); DPDP s.6(10) puts the burden of proving consent on the fiduciary. A customer can currently argue they accepted a draft.
**Fix.** C (clickwrap at signup and at checkout, write `consent_records` with document version hashes, time, IP, UA) + L (final texts) · **Who:** developer, lawyer.

### T3 — Account deletion · **CONFIRMED missing** · Critical (Play blocker)
**What exists.** Nothing user-facing: no in-app path, no web link. `profiles.deleted_at` is displayed in admin screens but **never written** by any code (E-066); the migration comment promising "a scheduled job performs hard deletion" describes a job that does not exist (E-010, E-096: pg_cron not installed).
**What a manual delete would do today** (E-093): deleting `auth.users` cascades to profiles, licences, orders, devices, sessions, activation_tokens, consent_records, intl_order_attempts; sets `audit_log.actor_user_id` null. It **fails outright for any customer with a payment** because `payments.user_id` is `ON DELETE RESTRICT` (E-011). It leaves behind: `audit_log.user_id` + free-text `reason`; hashed identifiers + IPs in `activation_requests`; Razorpay's own records and order notes containing the user id (E-033); Resend logs (US); Sentry events; 90 days of encrypted backups (E-101); Supabase function logs; data on the phone.

**What deletion must do end-to-end (design, not built)**
1. Confirm identity (fresh OTP) and show a **licence-loss warning**: "Deleting your account permanently ends your lifetime licence. It cannot be restored and is not refunded." (Q-07 decides refund interplay.)
2. Record the request (new `deletion_requests` row: user id, requested_at, channel) — this record itself must survive.
3. Revoke sessions (`sign_out_all_devices`), revoke licence.
4. **Detach and keep tax records**: copy name/email/amount/invoice no. into an immutable invoice snapshot (needed anyway — T6), then change `payments.user_id` to nullable/`SET NULL` or point it at a tombstone so the auth user can be deleted.
5. Delete `auth.users` → cascades (list above). Delete `activation_requests` rows matching the user's hashed email (possible: same pepper, E-034).
6. Pseudonymise `audit_log` for that user via the documented trigger-disable procedure only if the lawyer says the free-text reasons are personal data; otherwise keep (security/legal basis, disclose).
7. Ask Razorpay/Resend/Sentry deletion via their tools where available; disclose what they keep independently.
8. Backups roll off within 90 days; keep a deletion log so a restore re-applies deletions.
9. Web link: the public request page `/legal/delete-account` (drafted 30 Sep 2026; must stay outside `/account/*`, which `proxy.ts` redirects when signed out) — the URL for the Play Data Safety form; a self-service flow behind sign-in can be added later.
**Fix.** C (medium–large) + OD (Q-07, Q-08) + L · **Who:** developer, owner, lawyer.

### T4 — Append-only stores holding personal data · **PARTLY CONFIRMED, one claim REFUTED** · High
| Store | Personal data actually held | Retention enforced | Erasable today? | Evidence |
|---|---|---|---|---|
| `audit_log` | subject user id (no FK), `actor_email` (admin addresses, 9 rows), free-text `reason`, payment/order ids, AVS verdicts; `ip` column **never populated** (0/14) | none | **No** — triggers block UPDATE/DELETE/TRUNCATE for every role incl. owner | E-015, E-016, E-092, E-097 |
| `webhook_events` | **Refuted:** stores **no payload** — only Razorpay event id and type | none | Yes (service_role has DELETE) | E-013, E-097 |
| `payments.raw_payload` (the real payload copy) | Redacted: method name, fee, tax, notes (`order_id`, `user_id`) — no card/VPA/contact | none | No DELETE grant; RESTRICT FK | E-030, E-097 |
| `activation_requests` | peppered hash of email/phone + **IP** (17/17 rows) | none | Not "insert-only even for service_role": service_role holds **TRUNCATE** (E-095); owner can DELETE (no trigger) | E-017, E-095 |
| `admin_otp_requests` | peppered hash + **IP** (12/12) | none | same as above | E-022, E-095 |
| `intl_order_attempts` | user id, IP, device hash | none (0 rows) | Cascades on user delete; service_role cannot DELETE/TRUNCATE | E-026, E-027 |

**Honest policy wording (draft for the lawyer):** "Some security and audit records are kept in a
form that cannot be edited, so that nobody — including us — can quietly alter the record of what
happened to your account or payment. These records hold identifiers (such as an internal account
number and payment reference), not your card details. We delete them after [N] months under a
documented procedure; where the law requires us to keep them longer (for example tax records for
up to eight years) we keep them for that period."

**Mechanisms to reconcile (proposals, not built):**
- A `SECURITY DEFINER` purge function per ledger (owned by `postgres`, `search_path` pinned, callable by nobody but a scheduler), deleting rows older than the retention period; schedule via pg_cron (not installed — E-096) or a GitHub Action. Revoke the stray TRUNCATE grants at the same time.
- For `audit_log`: keep the append-only trigger; implement retention as a **reviewed quarterly procedure** (disable trigger → delete rows older than N → re-enable), which the migration already anticipates (E-016), and write an `audit_log` row recording the purge itself. Alternative: monthly partitions so old partitions are dropped rather than rows deleted.
- On erasure, pseudonymise rather than delete where the row is evidence (replace free text with a hash).
**Fix.** C + OD (retention periods, Q-09) + L.

### T5 — Backups · **CONFIRMED, with a correction** · Medium
**What.** Correction to the brief: the project is on the Supabase **Free** plan (E-102) and the Free plan has **no automatic daily backups** (V-01), so Supabase-side customer-accessible backups do not exist. (Platform-internal copies are UNKNOWN.) The only backups are the nightly GitHub Actions dumps: whole database incl. the `auth` schema (E-102), age-encrypted with a public key (private key offline with the owner), stored as artifacts with 90-day retention; 39 artifacts exist now (E-101). Repo is private with 1 collaborator (E-101). Who holds the private key: the owner (UNKNOWN whether anyone else — Q-14). A move to Cloudflare R2 with 30-day pruning is planned (E-102) — that would add Cloudflare as a processor.
**Policy sentence (draft):** "Encrypted backups of our database are kept for up to 90 days and are then automatically deleted. If you delete your account, your data may remain in these encrypted backups until they expire; we do not restore them except to recover from a failure, and if we do, we re-apply your deletion."
**Fix.** W + C (deletion log to re-apply after restore) + Cfg.

### T6 — Tax records, erasure and invoices · **CONFIRMED gaps** · High (Critical before live sales)
**Receipt as built** (E-085): Billed to, Amount, GST line, Payment reference, Invoice number, Date. INTL shows "Nil — zero-rated export of service".
**Gaps against a GST tax invoice (Rule 46) and R5:** no supplier legal name, address, **GSTIN**; no SAC code; no place of supply / recipient state; no invoice date distinct from payment timestamp; no export endorsement ("SUPPLY MEANT FOR EXPORT UNDER BOND OR LETTER OF UNDERTAKING WITHOUT PAYMENT OF INTEGRATED TAX" — R5c), no LUT reference; no stored invoice snapshot (the page re-renders from the current profile, so a later name change rewrites the "Billed to" line); "Download invoice" disabled (E-085); **no invoice or receipt email is sent by Danlite** (Razorpay's own payment email, if enabled, is not a GST invoice). GST registration status and whether GST is even applicable (turnover threshold) are UNKNOWN (Q-03).
**Credit notes:** none. A refund flips `payments.status` to `refunded` and revokes the licence (E-019); no credit note document or number is created.
**Test-era invoice numbers:** 7 numbers in `INV/2026-27/…` have been consumed, all INR, one refunded (E-097). Whether those were Razorpay **test-mode** payments is UNKNOWN (Q-04). If they were test payments, the live series will start at 000008, leaving a gap in the FY 2026-27 series that the accountant must explain or reset.
**Records accuracy:** `activate_licence_from_payment` stamps every purchase `razorpay_in` (E-019, E-096), so a future international sale would be recorded as domestic in `licences.purchase_rail`.
**Retention vs erasure:** GST s.36 requires keeping invoices/payment records ~8 years (R5a). That lawfully limits erasure of the invoice, but not of the login account, device, or session data — which today cannot be separated because of the RESTRICT FK (T3).
**Fix.** C (invoice snapshot, PDF/email, credit notes, rail fix) + A (format, GSTIN, SAC, LUT, test numbers) · **Who:** accountant decides, developer builds.

### T7 — Third parties and flows · **DONE** — see DATA_INVENTORY §3
Findings beyond the brief: Resend stores account data and logs **in the US** even though mail leaves from Tokyo (V-03, E-100); Sentry is **EU/Frankfurt** (V-02, E-062); Supabase is Mumbai behind Cloudflare (E-099); Google Fonts receives phone IPs (E-063); the Supabase Auth OTP email sender is UNKNOWN. Cross-border transfers therefore exist to the US (Resend, possibly Supabase/Sentry staff access), EU, Japan. DPAs: none evidenced (Q-15). Severity **High** (DPDP s.8(2) requires a valid contract with processors; GDPR Art 28 for EU users).

### T8 — Device data and backup flags · **CONFIRMED** · Medium
Fingerprint = SHA-256 of a random per-install 256-bit secret; no hardware ids; not salted, but the input is random so the hash is not linkable to the handset (E-056). `devices` holds fingerprint, platform, model, last_seen; `public.sessions` holds **no IP/UA** (E-012). However **`auth.sessions` (Supabase Auth) stores IP and user agent for every session** (E-092, E-098) — undisclosed today. Entitlement token contains user id, licence status, session id, device id, times, signature (E-036). **`android:allowBackup` is not set, so Android's default (backup on) applies** (E-051, E-052): plain SharedPreferences (vehicle profiles incl. VIN, trips, settings) can be copied to the user's Google backup; the secure-storage files are copied as ciphertext whose Keystore key is not backed up, so they become unreadable after restore (the app already handles that — E-055). Security: acceptable for tokens; Data Safety: Google's backup is not "collection by the developer", but the privacy policy should say local data may be included in the user's own device backup. Recommendation: add `dataExtractionRules`/`fullBackupContent` excluding secure-storage files (C, small).

### T9 — On-phone storage and "your vehicle data stays on your phone" · **REFUTED as an absolute statement** · High
Storage map: DATA_INVENTORY §1.5. Vehicle profile data (make/model/year/VIN) is **not** sent to Danlite servers (E-058). But: (1) **every OBD command/response line is `debugPrint`ed** (E-061) and **sentry_flutter turns every `debugPrint` into a breadcrumb in release builds** (E-060), with Sentry enabled in the shipped `.env` (E-062) — so the last 100 wire lines (fault-code responses, sensor values) travel to Sentry (EU) with any error report; (2) Android Auto Backup may copy the profiles to Google (T8); (3) the user can export trips to the clipboard. The draft privacy policy's sentence "Fault codes, live sensor readings, freeze-frame data and any vehicle identifiers stay on your device and are not transmitted to us" (E-081) is **not safe to publish as written**. Either change the code (disable print breadcrumbs or stop printing wire lines in release — C, small) and then the sentence becomes true for Danlite, or disclose Sentry.

### T10 — Permissions · **CONFIRMED with two issues** · Medium
Manifest vs runtime (E-051–E-053): Bluetooth connect/scan requested on Android 12+; **location (when in use) requested only on Android < 12**, and no code reads location (no location plugin, `logPoint` never receives coordinates — E-054). Issues: (a) `ACCESS_FINE/COARSE_LOCATION` have **no `maxSdkVersion="30"`**, so they are declared on Android 12+ too even though never requested there — Play's Data Safety/permission review may ask why; (b) `BLUETOOTH_ADVERTISE`, `CHANGE_WIFI_STATE` and `WAKE_LOCK` are declared but no usage was found in Dart/Kotlin (plugins may use WAKE_LOCK — UNKNOWN). No camera, microphone, storage, contacts, notifications or background location. The manifest comment says location is also for "Trip Logging" — untrue today. **Fix:** C (cap location at SDK 30, remove unused permissions after testing).

### T11 — Age · **CONFIRMED: no age gate** · Medium
No age question, no date of birth, no statement in the app (E-064). DPDP treats under-18s as children needing verifiable parental consent (R1f). Honest wording: "Danlite ELM is for adults (18+). By creating an account you confirm you are 18 or older." Enforcement today: none; a self-declaration checkbox at signup is the proportionate step (C, small). Play target audience must be set to 18+ consistently (Q-10).

### T12 — Purchase-related in-app copy vs Play Payments policy · **CONFIRMED exposure** · Critical (business-model risk)
**Inventory of purchase-related copy and flows in the app**
| Place | Text / behaviour | Languages | Evidence |
|---|---|---|---|
| Signup flow (any language) | Creating an account **automatically triggers an email** "Activate your Danlite ELM licence … Continue to checkout" — confirmed firing in production (11 tokens minted within 5 min of signup) | email in English | E-018, E-034, E-103 |
| `paywall_title` / `paywall_body` | "No active licence yet… If your purchase has just gone through…" | en, hi (+fallback) | E-071 |
| `paywall_resend_cta` | Button "**Email me a new link**" → sends the checkout email again | en, hi | E-067, E-071 |
| `paywall_resend_sent/throttled/failed/no_email` | link status messages | en, hi | E-071 |
| `paywall_support_*` + `kPaywallSupportContact` | "Contact support…" + placeholder address | en, hi | E-066 |
| `account_status_active`, `account_purchased_via` | "Lifetime Licence · Active", "Purchased via {rail}" | en, hi | E-071 |
| Account screen legal URLs | billing-host URLs as selectable text | — | E-065 |
**Assessment.** The code carefully avoids prices, URLs and "buy" wording inside the app (comments at `app_strings.dart` L588-600). But Play's Payments policy prohibits leading users out through "buttons, links, messaging … or other calls to action" **and** through "in-app user interface flows, including account creation or sign-up flows" (R7a). Here, in-app account creation directly causes a checkout email, and an in-app button re-sends it. A reviewer can reasonably read that as steering to an outside payment for in-app features. The "consumption-only" argument could not be verified from the policy text (R7b).
**Options (owner decision Q-02):**
1. Play Billing for the licence (policy-safe; Google fee; Razorpay rail only for web/non-Play).
2. Enrol in Play's alternative/user-choice billing for India if eligible (R7c) — Razorpay as the alternative inside the app, with Play's required disclosures and reduced fee.
3. Strict separation: remove the automatic signup→checkout email and the "Email me a new link" button; the app only says "sign in with the account you used when you bought"; purchase happens only on the website, discovered outside the app. Residual risk remains if the app is useless without buying.
4. Distribute outside Play (direct APK/other stores) — removes the policy, adds sideloading friction and security-warning UX.
**Fix.** OD + L (Play policy) · **Who:** owner.

### T13 — What a purchase grants (facts for the Terms) · **DOCUMENTED** · Medium
- Product `LIFETIME_V1`, one-time, ₹129 (INR, GST-inclusive placeholder) or US$1.29 (E-086); country chosen at signup fixes the price and cannot be changed by the user (E-025).
- One active app session per account, **last login wins** (another device is signed out without asking) (E-021); portal "Sign out all devices" (E-087). No device-count limit other than "one at a time".
- Offline: token valid 14 days; after that the app blocks until it reconnects (E-036, E-071).
- Refund (any amount, even partial) → **whole licence revoked** automatically (E-019, E-020). Admin revoke → revoked, reason recorded (E-023). A later purchase re-activates.
- **Chargebacks/disputes: no handling** — `payment.dispute.*` events are ignored (E-031); a charged-back customer keeps the licence unless an admin revokes.
- Account deletion: not possible today; if built, the licence is destroyed (cascade — E-093).
- Service discontinuation: nothing in code; the app needs the server at least every 14 days, so **if the backend stops, every licence stops working within 14 days** (E-036). Supabase Free projects can be **paused after 7 days of low activity** (E-102). "Lifetime" must be defined accordingly (Q-06).
- Activation link: 15-minute validity, single use; resend limits 3/hour per identifier, 10/hour per IP (E-034); app enforces a cooldown after each attempt (E-067).
- Emergency paywall bypass exists and has been used once in production (E-036, E-097): when on, everyone is licensed for 14 days.

### T14 — Honesty of diagnostic UI copy · **CONFIRMED** · High
| String | Problem | Evidence |
|---|---|---|
| `noFaultCodesDesc` "Your vehicle has no stored DTCs. Great news! 🎉" (11 languages) | No stored codes ≠ healthy vehicle; pending codes, non-OBD systems, unreachable modules and adapter limits are all invisible | E-071 |
| `clearSucceeded` "Codes cleared successfully ✓" shown **unconditionally** | Deliberate owner decision (E-068); true outcome (refused, unconfirmed, link failure) is hidden; a rider may believe a braking/engine fault is gone | E-068 |
| `clearWarning` "…erase all stored DTCs and turn off the Check Engine light" | Absolute; the light returns if the fault persists | E-071 |
| About: "Works with all ELM327 adapters" | Contradicted by in-app ABS text | E-069 |
| About: "HUD Mode — for night driving"; performance tests (0-100, quarter mile, "Run Dyno Test (Full Acceleration)") | Encourages use while driving / speed tests on public roads, while the same screen says "Do not operate the device while driving" | E-069, E-071 |
Existing disclaimers: About `legalText` ("informational purposes only… consult a qualified mechanic… Do not operate the device while driving"); ABS copy is careful and honest (absNoModuleDesc, absRawUnverifiedNote, blink-code notes — E-071). **Terms must** state: no-code result is not a clean bill of health; a clear-codes confirmation does not verify the erase; performance/HUD features are for closed-course/passenger use; the user is responsible for safe operation. Better: C — show the real clear outcome and soften "Great news". **Fix.** W + C + OD (the owner chose the unconditional message; lawyer should weigh consumer-law exposure).

### T15 — Brands and sourced data · **CONFIRMED exposure** · Medium (legal question unresolved)
Manufacturer names appear as text (Honda, Royal Enfield, Bajaj, Yamaha, Suzuki, KTM, Hero, Bosch; adapter brands OBDLink, Vgate, PLX) — no manufacturer logos found (E-070). Royal Enfield ABS tables were transcribed from "**owner's photographs of the Classic 350 service manual**" and a "**publicly hosted**" Bullet EFI manual (E-070); Honda blink-code table from "Honda service manual" (E-071 `blinkRefSource`). Exposure: copyright in manual text (descriptions/remedies copied verbatim), possible confidentiality if the manual was a dealer-only document, and trademark/false-affiliation if names are used in marketing. Suggested wording (for the lawyer): "Danlite ELM is an independent product and is not affiliated with, endorsed by or sponsored by any vehicle or equipment manufacturer. Manufacturer names are used only to identify compatible vehicles. Fault-code descriptions are provided for reference and may be incomplete." Also reconsider the claim "OBD Danlite is an original application" (E-069). **Fix.** L + W · **Who:** lawyer, client (provenance of the manual — Q-16).

### T16 — Foreign consumer tax · **RECORDED** · Medium
Selling a digital licence to consumers in the US, UK, UAE, Canada, Australia, Singapore and Germany (the eight signup countries — E-064) can trigger local VAT/GST/sales-tax registration obligations independent of Indian GST (e.g. EU VAT OSS, UK VAT, Australian GST on imported digital services, Singapore OVR, Canadian GST/HST, some US states), often with zero or low thresholds for non-resident digital sellers. The code treats all non-India sales as tax-free exports (E-086). A merchant-of-record (Play Billing, Paddle, FastSpring, Lemon Squeezy etc.) would collect and remit those taxes and become the seller of record, removing most of this burden (and changing who appears on the invoice). **Fix.** A (Q-05) · **Who:** accountant.

### T17 — Admin access to personal data · **CONFIRMED** · Medium
Two allow-listed admins (E-092). Admins see name, email, phone, country, licence, payments, orders, **device fingerprints**, sessions, audit entries incl. subject emails (E-041, E-042). **Reads are not logged — only actions are** (E-042, E-064). Admins are themselves `auth.users` and so also get customer rows and activation emails (E-043). Admin login is by email OTP (MFA not observed). **Fix.** C (log admin reads of a customer record; hide fingerprints) + OD (who the two admins are and under what confidentiality terms — Q-13).

### T18 — Support and grievance · **CONFIRMED broken** · Critical
The support address shown in the app is `support@danlite.example` (E-066) — `.example` is a reserved domain that can never receive mail. Draft policies say `[CONFIRM: support email]`, `[CONFIRM: privacy contact email]`, grievance officer `[CONFIRM]` (E-081–E-083). No acknowledgement/resolution timelines are promised anywhere live. Who answers the mailbox: UNKNOWN (Q-11). Obligations: E-Commerce Rule 4(5) 48 h acknowledgement / 1 month resolution (R4a); DPDP Rule 14 ≤ 90 days (from May 2027); Razorpay requires a Contact page (R3). **Fix.** OD + Cfg + W.

### T19 — Cookies and storage on the portal · **CONFIRMED essential-only** · Low
Portal cookies are Supabase auth cookies only (httpOnly, secure, lax — E-087); no analytics or tracking script found; fonts are self-hosted at build; Razorpay Checkout.js loads only on checkout; reCAPTCHA only if configured (E-087). No Set-Cookie on public legal pages (E-090). A consent banner is not needed for strictly necessary cookies under Indian law or the EU ePrivacy exemption, but the policy should list them. **Caveat:** the portal's root redirects to **danlite.in**, which runs WooCommerce order-attribution/sourcebuster tracking (E-091) — a separate site whose cookie practice is out of scope but reachable from the billing host. If reCAPTCHA is ever enabled, Google cookies/signals must be disclosed.

### T20 — Logs · **CONFIRMED issues** · Medium
- App: OBD wire lines and other `debugPrint`s go to logcat and (release) Sentry breadcrumbs (E-060, E-061). No email/phone printed by app code (E-055 `_log` deliberately omits messages).
- Edge Functions: emails of non-admin accounts that hit admin endpoints (E-039) and acting admin emails (E-040) go to Supabase function logs; `create-order` logs Razorpay error bodies (E-033 L441) which echo request fields (amount/currency/notes — user id).
- Sentry: IP + city stored unless the project setting is on — status UNKNOWN (E-038, E-102).
- Hostinger/Supabase platform logs: IPs, retention UNKNOWN.
**Fix.** C (drop wire prints in release; hash emails in admin guard log) + Cfg (Sentry IP setting, scrubbing) · retention to disclose.

---

## Part 2 — Additions beyond the brief

| ID | What | Evidence | Harm prevented | Severity | Owner decision? |
|---|---|---|---|---|---|
| A-01 | **danlite.in refund page is WooCommerce's unedited sample** ("This is a sample page"… 30-day physical returns, "Downloadable software products" non-returnable). The billing portal's root redirects there. A Razorpay website check or a customer will find a policy that contradicts the app's 24-hour draft. | E-088, E-091 | Razorpay onboarding rejection; consumer relying on the wrong policy | Critical | Yes (which site is "the website" for Razorpay — Q-01) |
| A-02 | **Live legal pages say "DRAFT… must not be published as-is"** and are the documents a customer "accepts" at checkout; they are also `noindex`. | E-080, E-084, E-090 | Unenforceable terms; Razorpay/Play reviewers see drafts | Critical | No (finish them) |
| A-03 | **Razorpay required pages missing on the billing host:** no Contact page, no Shipping/Delivery policy (for a digital good, a one-paragraph "delivery by activation, instant" page), no standalone Pricing page. | E-088, R3 | Live-key blocker | Critical | Q-01 |
| A-04 | **Privacy policy not reachable in-app before purchase**: legal URLs exist only on the Account screen, behind the paywall; not tappable. New and unlicensed users never see it. | E-065 | Play User Data policy (link "within the app") | High | No |
| A-05 | **OBD traffic reaches Sentry via breadcrumbs** (see T9). | E-060–E-062 | False privacy statement; unnecessary data export | High | No |
| A-06 | **App downloads fonts from Google at runtime** → phone IP to Google on first run; undisclosed third party; also a network dependency in garages. | E-063 | Data Safety accuracy; offline UX | Medium | No (bundle fonts) |
| A-07 | **Chargebacks/disputes ignored**; a disputed payment keeps its licence; terms promise revocation for disputed payments. | E-031, E-082 | Revenue loss; terms not matched by system | Medium | Yes (policy) |
| A-08 | **International purchases would be recorded as `razorpay_in`.** | E-019, E-096 | Wrong records for tax/export evidence | High (before INTL goes live) | No |
| A-09 | **Emergency paywall bypass** has been armed once; while on, non-payers get 14-day valid tokens. Terms should reserve the right; revenue records should note it. | E-036, E-097 | Disputes about "free" licences | Low | Yes |
| A-10 | **GDPR/UK GDPR territorial scope**: signup offers GB and DE, and prices in USD for "international". Offering to EU/UK residents triggers GDPR Art 3(2) and likely an **Art 27 EU representative** and **UK representative** (unless exemption applies), EU-grade notice (lawful basis per purpose), and Art 28 contracts. | E-064 | Regulatory exposure in EU/UK | High | Yes (Q-17: drop GB/DE or comply) |
| A-11 | **Notice language**: DPDP s.5(3) lets a Data Principal get the notice in English or any Eighth-Schedule language; the app is marketed in 23 languages but privacy/consent copy exists only in en+hi. | E-072 | DPDP notice defect from May 2027 | Medium | Yes (which languages) |
| A-12 | **Supabase Auth stores IP + user agent** per session (`auth.sessions`), and `auth.audit_log_entries` exists (0 rows today). Undisclosed. | E-092, E-098 | Data Safety/privacy accuracy | Medium | No |
| A-13 | **"Append-only" ledgers are not append-only**: service_role holds TRUNCATE on `activation_requests` and `admin_otp_requests` (the same hole closed for `intl_order_attempts`). | E-095, E-027 | Security control weaker than documented | Low | No |
| A-14 | **Free-plan dependency**: no Supabase backups, project can be paused after 7 idle days, no SLA; a "lifetime" licence that stops working within 14 days of a backend outage. | E-102, V-01, E-036 | Consumer claims on "lifetime" | High | Yes (Q-06) |
| A-15 | **Safety/liability**: HUD "for night driving" and on-road performance tests (0-100, quarter mile, full-acceleration dyno) conflict with "Do not operate while driving". | E-069, E-071 | Personal-injury claims; store policy on dangerous activities | High | Yes |
| A-16 | **DMARC `p=none` on danlite.in**; customers are trained to click emailed links → phishing risk using the brand. | E-100 | Account takeover / fraud | Medium | Cfg |
| A-17 | **No security headers** on billing host beyond `upgrade-insecure-requests` (no HSTS, no frame-ancestors) — checkout page can be framed. | E-090 | Clickjacking; reviewer security questionnaires | Medium | Cfg/C |
| A-18 | **Phone lookup on the public resend endpoint** (`send-activation` Path B) matches `profiles.phone`, which is no longer unique; the copy also invites phone input though auth is email-only. | E-034, E-024 | Wrong-recipient edge cases; stale copy | Low | No |
| A-19 | **Admins are customers**: admin logins create auth users, profiles, licences and trigger activation emails. | E-043, E-018 | Data minimisation; confusing records | Low | No |
| A-20 | **Shipped build predates latest code**: APK/AAB dated 22 Sep; Play submission from these files would not include the 30 Sep ABS changes; Data Safety must match the submitted build. | E-002 | Data Safety mismatch | Low | Yes (which build) |
| A-21 | **No invoice/receipt email and no downloadable invoice**; E-Commerce and GST expect the customer to receive an invoice. | E-085 | Consumer complaint; GST non-compliance | High | Q-03 |
| A-22 | **Processor contracts (DPAs) not evidenced** for Supabase, Resend, Sentry, Hostinger, GitHub; DPDP s.8(2) requires a valid contract. | V-06 | DPDP non-compliance | High | Q-15 |
| A-23 | **Hindi-only DTC descriptions and partial translations** mean non-English/Hindi users read safety-relevant copy in English. | E-072 | Consumer misunderstanding | Low | Yes |
| A-24 | **Owner's personal email is committed to source** (admin seed migration) and appears in the runbook partially. Private repo, but it will travel with any code handover. | E-022 | Personal-data exposure on repo sharing | Low | Yes |
| A-25 | **`profiles.email` never re-syncs** after an auth email change; invoices and admin tools would show a stale address. | E-025 | Wrong invoice recipient | Low | No |
| A-26 | **Documents that should exist but do not**: Record of processing (this folder is the draft), breach-response runbook (DPDP 72-hour Board report — confirm), retention & deletion procedure, DPA register, grievance log, consent-version register, invoice/credit-note procedure, admin access policy/NDA. | — | Accountability evidence | Medium | Yes |

---

## Part 3 — Follow-up build backlog (proposed; nothing built)

| # | Item | Resolves | Size |
|---|---|---|---|
| B-01 | Replace every stale in-app claim (T1 table), in all shipped languages; publish a short layered notice at signup with a tappable link to the full policy | T1, A-04, A-11 | S |
| B-02 | Make legal links tappable (url_launcher already in the dependency tree) and visible on login, signup and paywall screens, not only behind the paywall | A-04, R2a | S |
| B-03 | Real support/grievance address in app and portal; Contact page on billing host | T18, A-03 | S |
| B-04 | Consent capture: signup checkbox (Terms + Privacy + 18+), checkout checkbox; write `consent_records` with document version and hash | T2, T11 | M |
| B-05 | Publish final Privacy, Terms, Refund, Shipping/Delivery, Pricing, Contact pages; remove DRAFT banner; replace or remove the danlite.in sample refund page | A-01–A-03 | S (code) + L |
| B-06 | Account deletion: in-app flow + web page `/account/delete`, licence-loss warning, `deletion_requests` table, detach payments (FK change + invoice snapshot), cascade, ledger clean-up, deletion log for restores | T3 | L |
| B-07 | Retention jobs: `SECURITY DEFINER` purge functions + scheduler for activation tokens/requests, admin OTP ledger, intl ledger, sessions, webhook events; revoke stray TRUNCATE grants; documented audit_log purge procedure | T4, A-13 | M |
| B-08 | GST-compliant invoice: immutable snapshot at payment, supplier details/GSTIN/SAC/place of supply, export endorsement + LUT reference, PDF download and email; credit note on refund | T6, A-21 | M |
| B-09 | Fix `purchase_rail` for international payments | A-08 | S |
| B-10 | Dispute/chargeback webhook handling (log + revoke per policy) | A-07 | S |
| B-11 | Disable Sentry print breadcrumbs or stop printing OBD wire lines in release; hash emails in admin-guard logs; enable Sentry "Prevent storing IP" (Cfg) | T9, T20, A-05 | S |
| B-12 | Bundle Nunito font; set `GoogleFonts.config.allowRuntimeFetching = false` | A-06 | S |
| B-13 | Manifest: `maxSdkVersion="30"` on location permissions; remove unused permissions; add backup/data-extraction rules excluding secure storage | T8, T10 | S |
| B-14 | Honest diagnostic copy: soften "Great news", show real clear-codes outcome (needs owner reversal of decision), driving-safety warnings on HUD/performance screens | T14, A-15 | S |
| B-15 | Admin: log reads of customer records; hide fingerprints; consider MFA | T17 | M |
| B-16 | Play payments decision implementation (Play Billing / alternative billing / remove signup→checkout email and resend button) | T12 | L (Play Billing) / S (removal) |
| B-17 | Security headers on billing host (HSTS, frame-ancestors, referrer policy); DMARC to quarantine after monitoring | A-16, A-17 | S |
| B-18 | Profile email sync from auth; drop phone path in public resend endpoint | A-18, A-25 | S |
| B-19 | Move admin seed email out of committed migrations for future projects | A-24 | S |
| B-20 | **Checkout consent (recommended change, not made — checkout is out of scope for the legal-drafting task).** In `portal/app/checkout/page.tsx` L288-300 replace "By paying you accept the Terms and Refund policy." with an unticked checkbox that must be ticked before the pay button enables: "I have read and agree to the [Terms and Conditions] and the [Cancellation and Refund Policy], and I have read the [Privacy Policy]." Link all three to `/legal/terms`, `/legal/refund`, `/legal/privacy`. Pass the ticked state to `pay-button.tsx` and record it with B-04 (`consent_records`: document version `LEGAL_VERSION`, time, IP, user agent). | T2, E-110 | S (+M with B-04) |
| B-21 | **Activation email footer (recommended change, not made).** In `supabase/functions/send-activation/index.ts` add to both the text body (L183-191) and `activationHtml` (L209-229): the seller's legal name, and "Before you pay, please read our Terms (https://billing.danlite.in/legal/terms), Refund Policy (…/legal/refund) and Privacy Policy (…/legal/privacy)." Read the names from one place so they match `portal/lib/legal-config.ts`. | E-109, T2 | S |
| B-22 | Checkout product copy: replace "Unlocks the full app on your Android device, permanently." with "One payment. No subscription. A lifetime licence as defined in our Terms." | E-110, Terms §5 | S |
| B-23 | Refund handling: do not revoke the licence when the refunded payment is a duplicate (another captured payment remains for the same licence); decide and implement partial-refund behaviour (Q-29) | E-106, E-020 | S |
| B-24 | Email-only copy everywhere: `/activate` page and form ("email address or mobile number"), `send-activation` generic reply, app `account_logout_confirm_body` | E-112, E-034, E-071 | S |
| B-25 | App legal links: add `/legal/delete-account` and `/legal/contact` next to the three existing links; make them tappable and visible before purchase (with B-02); consider relabelling "Terms of Service" → "Terms and Conditions" and "Refund Policy" → "Cancellation and Refund Policy" (pages already say both names are the same document) | E-113, R2a, R2c | S |
| B-26 | Written runbook for the manual commitments in the draft policies until automation ships: deletion for payers (RESTRICT FK), ledger purges at the end of each retention period, re-granting a licence after a duplicate refund, re-applying deletions after a restore, breach notification, under-age account deletion | Q-34, T3, T4 | S |
| B-27 | Link the receipt (`/confirmation`) from the account page and show purchase history, so customers can find their receipt again (Delivery Policy tells them to save it) | E-108 | S |
| B-28 | Unify the product name across Play listing, app label, portal and emails ("OBD Danlite" vs "Danlite ELM"); fix About-screen claims that contradict the Terms ("Works with all ELM327 OBD2 adapters", "Full UI in … 20 more" languages, "HUD … for night driving") — extends B-14 | E-111, E-069, Q-26 | S |
