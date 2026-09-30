# Open questions for the owner, client, accountant and lawyer

Each question has a **proposed default** (what to do if nobody answers), the reasoning, and the
consequence of each choice. Evidence IDs: [SOURCES.md](SOURCES.md); risks: [RISK_REGISTER.md](RISK_REGISTER.md).

| ID | Question | Who answers | Proposed default | Reasoning | Consequence of each choice |
|---|---|---|---|---|---|
| Q-01 | What is the **legal entity** selling the licence (name, registered address, PAN/GSTIN), and is `danlite.in` (WordPress shop) or `billing.danlite.in` "the website" for Razorpay and Play? | Client | The same entity that owns danlite.in; billing.danlite.in is the product website and carries its own complete policy set | Razorpay checks the website you register; Play needs the listing entity named in the policy (R2b, R3) | Registering danlite.in → its sample refund page (E-091) must be replaced first. Registering billing.danlite.in → needs Contact, Pricing, Shipping pages (A-03) |
| Q-02 | **Play payments model** (T12): Play Billing, alternative/user-choice billing, strict web-only separation, or off-Play distribution? | Owner + lawyer | Remove the automatic signup→checkout email and the in-app "Email me a new link" button **before** Play review, and get a lawyer's view on Play Billing vs alternative billing | Play policy names sign-up flows and in-app buttons as prohibited steering (R7a); consumption-only exception not verified (R7b) | Play Billing: policy-safe, Google fee, Google becomes merchant of record for Play sales. Alternative billing: keep Razorpay, extra Play UI + fee. Separation: cheapest, residual rejection risk, worse conversion. Off-Play: no Play policy, loses store reach |
| Q-03 | Is the business **GST-registered**? GSTIN? Inclusive or exclusive pricing? SAC code? Invoice format and numbering? | Accountant | Inclusive ₹129 (as coded), SAC per accountant, add all Rule 46 fields | Receipt lacks mandatory fields (T6) | Not registered (below threshold): must not show "GST" lines at all. Registered: invoice must carry GSTIN etc.; exclusive pricing changes the price customers pay |
| Q-04 | Were the 7 existing invoice numbers (`INV/2026-27/000001…7`) **test-mode** payments? Should the series restart for live? | Accountant + owner | Treat them as test; accountant decides whether to reset the sequence before the first live sale | E-097 | Keep: gap/test entries in the FY series need explanation. Reset: requires a migration and a clean cut-over date |
| Q-05 | **Exports**: is an LUT filed (ARN)? Is the product OIDAR for foreign consumers? Foreign VAT/GST registrations? Merchant of record? | Accountant | Do not open the international rail until answered | R5b/c, T16 | LUT: zero-rated with endorsement. No LUT: IGST paid and refunded. Foreign VAT: registration in each country, or use a merchant of record |
| Q-06 | What does **"lifetime"** mean — life of the product? minimum support period? What happens to licences if the service shuts down? | Owner + lawyer | "For as long as we operate the service, with at least [24] months' notice before shutdown and a final offline-unlock build" | App stops within 14 days without the server (E-036); Supabase Free can pause (E-102) | Vague "lifetime": consumer-forum risk. Defined period: clear but less marketable. Offline-unlock promise: requires engineering |
| Q-07 | On **account deletion**, is the licence simply forfeited, or refunded/transferable? | Owner + lawyer | Forfeited with a clear warning; no refund outside the refund window | Deletion destroys the licence (cascade, E-093) | Refund: cost + abuse; forfeiture: must be conspicuous to be fair |
| Q-08 | **Deletion service level**: how fast, who executes, and which data is kept (tax records 8 years; audit identifiers N months)? | Owner + lawyer | 30 days; automated; keep invoice snapshot 8 years | Play + DPDP (T3) | Longer SLAs are allowed but must be stated |
| Q-09 | **Retention periods** for ledgers, audit log, sessions, logs, backups | Owner + lawyer | As in DATA_INVENTORY §4 "Recommendation" | DPDP Rule 6 ≥ 1 year for security logs; GDPR storage limitation | Shorter: less evidence for disputes. Longer: must be justified and disclosed |
| Q-10 | **Age**: 18+ only? Play target audience? | Owner | 18+ only, self-declaration checkbox, Play audience 18+ | DPDP child consent burden (R1f) | Allowing under-18s requires verifiable parental consent — impractical here |
| Q-11 | **Support and grievance**: real support address; who answers; named grievance officer (name, designation, address); can you commit to 48 h acknowledgement / 1 month resolution / 90 days privacy? | Client | A monitored `support@` on danlite.in, the owner as grievance officer, those three timelines | E-066 shows a non-working address; R4a, R1d | Without it: E-Commerce Rules breach, Razorpay Contact-page failure, unanswered refunds become chargebacks |
| Q-12 | Does Razorpay send **SMS/email receipts** to the customer's prefilled phone/email? Is that enabled on this account? | Owner (Razorpay dashboard) | Assume yes; change `auth_phone_note` accordingly or stop prefilling phone | E-033; conflicts with "we never send… messages to this number" (E-071) | If enabled and unchanged: the in-app promise is false |
| Q-13 | Who are the **two admins**, under what confidentiality terms, and should admin reads be logged? | Owner | Named individuals with written confidentiality; log reads | T17 | No logging: cannot answer "who looked at my data" requests |
| Q-14 | Who holds the **age private key** for backups; where; is there a second copy? | Owner | Owner only, offline, with a sealed second copy | T5 | Lost key = no restore; shared key = wider access to all customer data |
| Q-15 | Are **DPAs** in place (Supabase, Resend, Sentry, Hostinger, GitHub, Cloudflare R2 when used)? Is Razorpay a processor or independent? Is Google Fonts acceptable? | Lawyer + owner | Accept each vendor's standard DPA; treat Razorpay as independent for payment data; bundle fonts | DPDP s.8(2); GDPR Art 28 (A-22) | Missing DPAs: fiduciary liable for processor failures without contractual cover |
| Q-16 | **Provenance of the service-manual data**: was the Classic 350 manual a dealer-confidential document? Permission from Royal Enfield/Honda? | Client + lawyer | Paraphrase descriptions, cite as reference, add non-affiliation notice, remove verbatim remedies if not licensed | E-070, T15 | Verbatim copying without permission: copyright/confidentiality claims |
| Q-17 | Keep **GB and DE** (and other non-India countries) in the signup list? | Owner + lawyer | Keep only IN until GDPR/UK GDPR and foreign-tax questions are settled | A-10, T16 | Keep: Art 27 representatives, EU-grade notice, VAT. Drop: simpler, smaller market |
| Q-18 | Should the **clear-codes** message stay unconditional? | Owner + lawyer | Show the real outcome | T14, E-068 | Unconditional: consumer-law and safety exposure if a rider relies on a false "cleared" |
| Q-19 | Which **languages** must the privacy notice and consent screens ship in? | Owner + lawyer | At least the 10 "full coverage" languages; English fallback visible as such | A-11 | English-only: DPDP s.5(3) defect from 2027 |
| Q-20 | **Chargebacks**: revoke on dispute opened, on dispute lost, or never? | Owner | Revoke on dispute lost; log dispute opened | A-07 | Revoke early: angers legitimate customers; never: free licences via chargeback |
| Q-21 | Supabase **plan**: stay on Free? | Owner | Move to Pro before live sales | A-14 (pausing, no backups) | Free: pausing risk to a "lifetime" product |
| Q-22 | Which **Supabase Auth email sender** is configured (default or custom SMTP), and where are those logs? | Owner (dashboard) | Custom SMTP via Resend on `mail.danlite.in` | Evidence gap | Default sender: rate limits and an undisclosed processor path |
| Q-23 | Sentry settings: is **"Prevent Storing of IP Addresses"** on for both projects? Event retention? | Owner (dashboard) | Turn it on; 30-day retention | E-038, E-102 | Off: Sentry holds IP + city for every error |
| Q-24 | Where is the **admin portal** hosted and on what domain? | Owner | — | Evidence gap | Needed for the processor list and security headers |
| Q-25 | Which build will be submitted to Play, and is any build already published? | Owner | A new build after the S-sized fixes | E-002 | Data Safety must match the submitted build |

## UNKNOWN items and who resolves them

| # | UNKNOWN | Resolves |
|---|---|---|
| 1 | Legal entity, address, GSTIN | Client (Q-01, Q-03) |
| 2 | Supabase Auth OTP email sender | Owner (Q-22) |
| 3 | Razorpay live vs test keys; test status of 7 invoices | Owner/accountant (Q-04) |
| 4 | Razorpay receipts/SMS to customers | Owner (Q-12) |
| 5 | Sentry IP setting and retention | Owner (Q-23) |
| 6 | Hostinger access-log retention | Owner (Hostinger panel) |
| 7 | Supabase platform log retention; `auth.sessions`/`flow_state` pruning | Owner (Supabase docs/support) |
| 8 | Resend log retention | Owner (Resend dashboard) |
| 9 | Admin portal host | Owner (Q-24) |
| 10 | Private backup key custody | Owner (Q-14) |
| 11 | DPAs / vendor terms and processing locations (V-06) | Lawyer/owner (Q-15) |
| 12 | Whether plugins use WAKE_LOCK | Developer (test after removal) |
| 13 | Origin of `ensure_rls` / `rls_auto_enable` (platform vs drift) | Developer |
| 14 | Published Play build / listing entity | Owner (Q-25) |
| 15 | INTL checkout billing-field required/optional status in the UI | Developer |
| 16 | DPDP Gazette text (only transcriptions read), R1g cross-border, R4b/R4c, R7b consumption-only | Lawyer |
| 17 | Supabase staff access location / platform-internal backups | Owner (Supabase DPA) |
