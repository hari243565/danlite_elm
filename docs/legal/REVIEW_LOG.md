# Red-team review log — /legal/* drafts

**Date:** 30 Sep 2026 · **Branch:** `chore/legal-drafts` · Not legal advice.
Each page was attacked from six points of view. **Fixed** = changed in the drafts in this commit.
**Open** = needs a client decision or product change; linked to its question (Q) or backlog item (B).

## 1. Findings by reviewer

### 1.1 Razorpay onboarding reviewer
| # | Finding | Outcome |
|---|---|---|
| RZ-1 | Required pages: Terms, Privacy, Cancellation & Refunds, Shipping, Contact, Pricing. Shipping and Contact and Pricing did not exist | **Fixed**: `/legal/delivery` (titled as replacing a shipping policy), `/legal/contact`, `/legal/pricing`, plus `/legal` index |
| RZ-2 | Pages carried "DRAFT… must not be published" and `noindex` | **Fixed (mechanism)**: indexable now; the banner goes away only when config is complete and approved (Q-32). Still a draft until then |
| RZ-3 | Contact page must show a legal name, address, phone and email; all unknown | **Open**: placeholders Q-01, Q-11, Q-27 |
| RZ-4 | Refund timeline must be clear | **Fixed**: decision time (Q-29) + Razorpay's own "5–7 working days" basis (V-08) described as "several working days" + 10-working-day follow-up |
| RZ-5 | The site Razorpay reviews may be `danlite.in`, whose refund page is a WooCommerce sample, and `billing.danlite.in/` redirects there | **Open**: A-01, Q-01. Cannot be fixed inside the portal |
| RZ-6 | Pricing must show the price and currency clearly | **Fixed**: computed from `lib/gst.ts`; GST split shown; "confirm" flags for the accountant |

### 1.2 Google Play policy reviewer
| # | Finding | Outcome |
|---|---|---|
| PL-1 | Deletion web resource must be reachable without login and name the app/developer as on the listing | **Fixed**: `/legal/delete-account` (outside `/account/*`, which redirects signed-out users; proven in §3); names via Q-26 placeholders |
| PL-2 | Deletion page must say what is deleted, what is kept, and for how long | **Fixed**: shared deletion text; tax retention period; backups 90 days; placeholders for ledgers |
| PL-3 | Play also needs an **in-app** deletion path | **Open**: B-06. Stated honestly on the page ("no delete button yet") |
| PL-4 | Privacy link must be in the app for all users | **Open**: B-02, B-25 (app shows URLs only to licensed users, as text) |
| PL-5 | Privacy policy must disclose SDKs' collection (Sentry, Google Fonts) | **Fixed**: Privacy §5 and §8 |
| PL-6 | Payments policy: the policy pages (linked from the app) link to Pricing, and describe the sign-up → purchase email | **Open**: Q-35, Q-02. Disclosure is necessary for accuracy; the steering risk is a product decision (T12) |
| PL-7 | Developer/listing entity must match the policy | **Open**: two product names (E-111), Q-26, B-28 |

### 1.3 Data protection officer (DPDP; GDPR for UK/EU users)
| # | Finding | Outcome |
|---|---|---|
| DP-1 | Draft 0.1 said consent is "given at signup". No consent is captured | **Fixed**: removed. Bases stated in plain words; no claim of recorded consent. Mapping to Q-33 |
| DP-2 | Draft 0.1 named an SMS OTP provider; auth is email-only | **Fixed**: removed |
| DP-3 | Draft 0.1 said deletion "marks it for erasure immediately" | **Fixed**: replaced with the real manual process |
| DP-4 | Draft 0.1 said vehicle data "not transmitted to us" without mentioning Sentry | **Fixed**: disclosed in the summary box and §5 |
| DP-5 | Itemised notice, purposes, recipients, retention, rights, complaint to the Board | **Fixed**: all present; periods are placeholders where UNKNOWN |
| DP-6 | Cross-border transfers need a safeguard statement, true only if DPAs exist | **Open**: `TRANSFER_SAFEGUARDS` (Q-15); countries stated as verified |
| DP-7 | Sign-in IP/user-agent in `auth.sessions` undisclosed | **Fixed**: Privacy §2 |
| DP-8 | Withdrawal of consent "as easy as giving it": no mechanism | **Open**: by email only; Q-33, Q-34, B-04 |
| DP-9 | Retention "until deleted" is not acceptable | **Fixed**: table with the real periods or criteria; placeholders for undecided ones; honest line on manual deletion (Q-34) |
| DP-10 | EU/UK: Art 27 representative, extra rights, complaint to local authority | **Fixed** text + **Open** representative (Q-17) |
| DP-11 | Notice language (DPDP s.5(3)) | **Open**: Q-19 |
| DP-12 | "Staff can see… changes are logged": reads are not logged | **Fixed** wording (claims only that changes are logged). B-15 open |

### 1.4 Consumer-forum lawyer suing over a denied refund
| # | Finding | Outcome |
|---|---|---|
| CL-1 | 0.1 refund test "not yet activated on a device" is unverifiable (the device is recorded at sign-up, before payment) | **Fixed**: removed; options in CLIENT_REVIEW_PACK §3 |
| CL-2 | "Duplicate refunds leave your licence active": the system revokes it | **Fixed**: honest wording (E-106); B-23 |
| CL-3 | "The app's descriptions already say many adapters can't read ABS": the About screen says "Works with all ELM327 OBD2 adapters" | **Fixed**: refund page no longer relies on the app's descriptions; it points to the Terms. **Open**: the app's About screen (B-28) |
| CL-4 | Exclusive jurisdiction and arbitration against consumers | **Fixed**: non-exclusive court city, consumer commission preserved, "not required to go to arbitration" |
| CL-5 | "Lifetime" undefined (0.1) | **Fixed**: defined; notice and remedy are placeholders (Q-06) |
| CL-6 | Blanket liability exclusion | **Fixed**: non-excludable liability preserved; foreseeable loss accepted; cap at price where lawful |
| CL-7 | Terms accepted by nothing but using the product (no clickwrap) | **Open**: B-04, B-20 |
| CL-8 | Checkout says "permanently", which conflicts with the lifetime definition | **Open**: B-22 (checkout out of scope) |
| CL-9 | A general indemnity against a consumer would be struck down | **Fixed**: no indemnity clause (deliberate) |
| CL-10 | Chargeback clause: restoring the licence if the dispute is resolved for us | **Fixed** (fairness) |

### 1.5 Security researcher looking for over-promises
| # | Finding | Outcome |
|---|---|---|
| SR-1 | "Backups are encrypted before they leave our systems": the dump is made and encrypted on GitHub's runner | **Fixed**: "encrypted before they are stored" |
| SR-2 | "Data travels over HTTPS": the Wi-Fi adapter link is plain TCP on the local network | **Fixed**: "data sent to us and our providers" |
| SR-3 | "Regulated payment company" (Razorpay) unverified | **Fixed**: "payment company" |
| SR-4 | Absolutes ("never", "100%", "bank-grade") | **Checked**: none about security. "We never see your card, UPI or bank details" is structurally true (E-030, E-087). "No system is completely secure" included |
| SR-5 | Breach notification promised with no runbook | **Open**: Q-34, A-26 |
| SR-6 | Sentry IP storage unknown | **Fixed**: "may record" |

### 1.6 Non-technical rider on a phone
| # | Finding | Outcome |
|---|---|---|
| NR-1 | Needs the surprises first | **Fixed**: summary box on every page; safety box at the top of the Terms |
| NR-2 | Jargon (hash, IP, fiduciary) | **Fixed**: explained inline ("scrambled (hashed)", "internet (IP) address"); legal terms named once |
| NR-3 | Long tables on a small screen | **Fixed**: tables scroll inside their own box; contents list collapses to one column below 520 px |
| NR-4 | "What do I do if the email never comes?" | **Fixed**: Delivery §4, step by step |
| NR-5 | App calls pages "Terms of Service" / "Refund Policy" | **Fixed**: each page says it is the same document; B-25 |

## 2. Found while proofreading the rendered pages
| # | Finding | Fix |
|---|---|---|
| PF-1 | Deletion list said the phone number is kept for payers | Phone always deleted; name/email/country kept only for payers |
| PF-2 | Account ID described as a "random number" (it is a UUID) | "random code" |
| PF-3 | In-app Account screen offered as self-service to everyone; it is behind the paywall | "Once you have a licence, …" |
| PF-4 | Terms summary said any refund ends the licence, with no duplicate exception | Exception added (Terms summary, §7; Refund summary) |
| PF-5 | Contact tables had empty duplicate header keys (React warning, poor accessibility) | Label/value tables now use row headers |
| PF-6 | Placeholder checker would flag the example token in a config comment | Comment rewritten |

## 3. Verification (step 7 of the brief)

Run on 30 Sep 2026 in the worktree `danlite_elm_legal/portal`, dependencies from the unchanged
lockfile (`npm ci`; `package.json` and `package-lock.json` SHA-256 identical before and after).

| Check | Result |
|---|---|
| `npm run build` (`next build --webpack`) | exit 0; 16 routes, all `/legal/*` prerendered static |
| `npx tsc --noEmit` | exit 0 (after the build generates Next's route types; before a first build `app/layout.tsx` — untouched — reports the generated `LayoutProps` type as missing) |
| `npx eslint` | exit 0 |
| Smoke test (`next start`, baseline build of commit `7851c2c` on :3101 vs this branch on :3102, identical dummy env) | **ALL PASS** |
| – Non-legal routes: `/`, `/checkout`, `/account`, `/confirmation`, `/activate`, `/activate?e=1`, `/api/activate`, `/api/activate?t=abc`, `/does-not-exist`, `/legalese`, `/account/delete` | status, `Location`, `X-Robots-Tag` and meta robots **identical** to baseline; all still `X-Robots-Tag: noindex, nofollow` (e.g. `/checkout` → 307 `/activate`) |
| – `/robots.txt` | baseline `Disallow: /`; now `Allow: /legal` + `Disallow: /`; header unchanged |
| – All 8 `/legal` routes | 200; **no** `X-Robots-Tag`; meta robots `index, follow`; no `Set-Cookie` (also with a stale session cookie sent); no third-party `<script src>`; `<html lang="en">`; every required heading present; no leftover `[CONFIRM]` |
| – Prices | expected from `lib/gst.ts`: ₹129.00 total, ₹109.32 + ₹19.68 GST, US$1.29; all shown on Pricing, totals on Terms; no other money figure on any legal page |
| – Internal links and anchors | every `/legal…` link and `#anchor` resolves (200 and target id present) |
| – Placeholders | DRAFT banner shown; highlighted `<mark>` boxes rendered |
| `node scripts/check-legal-placeholders.mjs` | 41 unresolved tokens, all in `lib/legal-config.ts`, **every one mapped** to an OPEN_QUESTIONS item; none in page text |
| `… --strict` | exit 1 (as intended: unresolved tokens + `APPROVED_FOR_PUBLICATION = false`) |

**Scope proof.** Changed or added: `portal/app/legal/**`, `portal/lib/legal-config.ts`,
`portal/scripts/check-legal-placeholders.mjs`, `portal/app/robots.ts` (one `allow` line),
`portal/proxy.ts` (the robots header skipped for `/legal` and `/legal/*` only), `docs/legal/**`.
Checkout, pay-button, activate, account, confirmation, API routes, `gst.ts`, `package.json`,
lockfiles, `supabase/` and the Flutter app are untouched.
