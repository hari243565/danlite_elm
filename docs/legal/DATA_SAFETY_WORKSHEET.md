# Google Play Data Safety — preparation worksheet

> **Prepared to help the client fill in the Play Console Data safety form. The client (the developer
> account holder) remains responsible for the final answers and for keeping them accurate.**
> Based on commit `71e2783` and live observations on 30 Sep 2026. The build actually submitted must
> be checked against this sheet (the release APK/AAB in the owner's folder predates this commit —
> E-002). Evidence IDs: [SOURCES.md](SOURCES.md).

**Two answer columns are given where the truthful answer depends on fixes in the backlog:**
- **Today** — what an honest form must say for the code as it stands.
- **After fixes** — what it could say once the named backlog item (RISK_REGISTER Part 3) ships.

Definitions used (Play's): *collected* = transmitted off the device by the app (including by SDKs);
*shared* = transferred to a third party, **excluding** service providers processing on the
developer's behalf, legally required transfers, and user-initiated transfers. Whether Razorpay and
Google Fonts are "service providers" or "third parties" is a judgement for the client/lawyer (Q-15).

---

## 1. Data types

| Play category → type | Collected? | Shared? | Purposes (Play labels) | Optional? | Evidence / notes |
|---|---|---|---|---|---|
| **Personal info → Name** | Yes | No (service providers only) | Account management; (invoice) | Required on the signup screen | E-064, E-086 |
| **Personal info → Email address** | Yes | No, if Razorpay counts as a service provider; otherwise **Yes (Razorpay prefill)** | Account management; App functionality (activation/purchase email); Fraud prevention, security | Required | E-033, E-034, E-055 |
| **Personal info → Phone number** | Yes | Same Razorpay question as email | Account management (support contact); passed as payment prefill | Optional | E-033, E-064 |
| **Personal info → Address** | App: No. Portal (web, not the app) collects billing country + postal code for international buyers | — | — | — | E-026 — web checkout is outside the app; not an app data type |
| **Personal info → User IDs** | Yes (account UUID) | No | Account management; App functionality | Required (automatic) | E-036 |
| **Personal info → Other (country)** | Yes | No | App functionality (pricing) | Required | E-064 |
| **Financial info → Purchase history** | Yes — licence status, "purchased via", purchase date are read by the app from the server | No | App functionality; Account management | Automatic | E-036, E-071 |
| **Financial info → Credit/debit card, bank** | **No** — entered on the web in Razorpay's checkout, never in the app | — | — | — | E-030, E-087 |
| **Location → Approximate / Precise** | **No** (permission declared and requested on Android < 12 only for Bluetooth discovery; never read) | — | — | — | E-053, E-054. Note: Sentry may derive city-level location from IP (see IP row) — Play treats IP-derived location as location **only if** used as such; flag for the client |
| **App activity → App interactions / other actions** | Today: **arguably Yes** — Sentry breadcrumbs include navigation/`debugPrint` lines; After B-11: No | No | Analytics? No — **App functionality / crash diagnostics only** | Automatic | E-060, E-061 |
| **App activity → "Other user-generated content"** | No (vehicle profiles, VIN, notes stay on the phone) | — | — | — | E-058 |
| **App info and performance → Crash logs** | **Yes** (Sentry) | No (Sentry = service provider) | App functionality (diagnostics) | Automatic; not user-optional today | E-059, E-062 |
| **App info and performance → Diagnostics** | **Yes** — 5% performance traces + device/OS context + breadcrumbs that today include **raw OBD adapter traffic** | No | App functionality | Automatic | E-059–E-061 |
| **App info and performance → Other** | No | — | — | — | |
| **Device or other IDs** | **Yes** — per-install random fingerprint hash, device model; Sentry's own installation id | No | App functionality (one active device); Fraud prevention/security | Automatic | E-056, E-037 |
| Health & fitness, Messages, Photos/videos, Audio, Files & docs, Calendar, Contacts, Web browsing | No | — | — | — | E-050, E-051 |

**IP address.** Play has no separate "IP address" type; it is typically covered under Device or
other IDs / diagnostics. Today the app's IP reaches Supabase (every API call, stored in
`auth.sessions` — E-098), Sentry (stored with city location unless the project setting is on —
E-038) and **Google Fonts** (runtime font download — E-063). Recommend disclosing under "Device or
other IDs" (security) and in the privacy policy.

**Vehicle diagnostic data.** Not a Play category. Today it leaves the phone only as Sentry
breadcrumbs (T9). If the privacy policy says "stays on your phone", ship B-11 first.

## 2. Security practices

| Question | Answer today | Evidence / caveat |
|---|---|---|
| Is all user data encrypted in transit? | **Yes** — Supabase, Sentry, Google Fonts and the portal are HTTPS; the portal adds `upgrade-insecure-requests` | E-090, E-099. Caveat: the ELM327 **Wi-Fi adapter** link (plain TCP to 192.168.0.10:35000) is local vehicle data, not user data sent off-device |
| Can users request that data be deleted? | **No — not today.** Must become Yes before submission (Play requirement) | T3, E-066 |
| Account-deletion in-app path | **None** | B-06 |
| Account-deletion web link (for the form) | **None**. Proposed: `https://billing.danlite.in/account/delete` (does not exist yet) | B-06 |
| Data deleted vs retained on account deletion (to disclose) | Proposed: account, profile, devices, sessions, licence deleted within 30 days; payment and invoice records kept **8 years** for GST (R5a); security/audit identifiers kept up to [N] months; encrypted backups roll off within 90 days | T3, T4, T5 — needs Q-07/Q-08/Q-09 |
| Committed to Play Families policy? | Not applicable — app should be declared 18+ (not directed at children) | T11, Q-10 |
| Independent security review? | Not evidenced | — |

## 3. Account creation answers

| Form question | Answer |
|---|---|
| Does the app allow account creation? | **Yes** — email OTP (E-055, E-064) |
| Login methods | Username/email + OTP (no password, no OAuth) |
| Can accounts be created outside the app? | No (the portal signs in existing accounts via activation link; it does not create them) — confirm (E-035) |
| Deletion URL | **Required, does not exist yet** |

## 4. Consistency checklist before submitting

- [ ] Privacy policy URL in Play Console = the **final** billing-host policy, not the draft with the DRAFT banner (E-080).
- [ ] Entity named in the store listing appears in the privacy policy (R2b) — entity UNKNOWN (Q-01).
- [ ] Privacy policy link visible **inside the app** to all users, not only licensed ones (E-065).
- [ ] Policy discloses Supabase, Razorpay, Resend (US storage), Sentry (EU), Google Fonts, Hostinger, GitHub backups (DATA_INVENTORY §3).
- [ ] Location permission capped at SDK 30 or justified in the Play permission declaration (T10).
- [ ] Payments-policy position decided (T12) — the Data Safety form does not cover it, but the same review can reject the app.
- [ ] The build uploaded is the one this sheet was checked against.
