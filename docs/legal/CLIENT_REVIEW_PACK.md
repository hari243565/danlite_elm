# Client review pack — Danlite ELM legal pages

**For:** the client, and their lawyer and chartered accountant.
**Status:** DRAFTS, 30 Sep 2026, branch `chore/legal-drafts`. **This is not legal advice.** The
pages were written so that every sentence is true of the system as it is built today. They still
need your answers (the highlighted gaps) and a qualified review before they are published.

**How to read the drafts:** each page is live on the draft branch at `/legal/...`. Anything you
need to supply appears on the page in a **yellow box** like `{{TODO:LEGAL_NAME}} (Q-01)`. All
the answers go into one file, `portal/lib/legal-config.ts`, so nobody has to edit the page text to
fill them in. Prices are not typed anywhere: they come from the same code that charges the
customer.

---

## 1. The pages, in a few lines each

| Page | Address | What it says, in short |
|---|---|---|
| **All policies** | `/legal` | A list of every policy, so Razorpay and Google can find them from one address. |
| **Terms and Conditions** | `/legal/terms` | The contract. A safety box comes first: don't use the app while riding; brake and ABS faults need a mechanic; "no codes" is not a clean bill of health; the clear-codes success message may be shown even when the clear didn't work. It defines the licence as personal, one phone at a time and checked online every 14 days. "Lifetime" means for as long as the service runs, with notice before it closes. It keeps consumer rights, forces no arbitration and caps liability at the price paid where the law allows. |
| **Privacy Policy** | `/legal/privacy` | What is collected and why, who receives it (a table of 9 providers with countries), how long it is kept, security and rights. It discloses the things that might surprise a customer: sign-up triggers a purchase email, Razorpay gets the email and phone, crash reports can carry vehicle diagnostic messages to Sentry in Germany, email records are stored in the US, and tax records survive account deletion. |
| **Cancellation and Refund Policy** | `/legal/refund` | No subscription, so nothing to cancel. Duplicate payments and paid-but-no-licence cases are always refunded. "Not as described" is refunded if reported within a window. The change-of-mind rule is **your choice (see §3)**. Any refund ends the licence. Refunds go to the original payment method, and the bank takes several working days. Statutory rights are kept. |
| **Delivery Policy** | `/legal/delivery` | Nothing is shipped: the licence is delivered to the account, usually within minutes of payment. It explains the 15-minute, single-use email link, how to get a new one, and what to do if it doesn't arrive. It also covers the receipt and where sales are offered. This is the "Shipping policy" Razorpay asks for. |
| **Pricing** | `/legal/pricing` | The rupee price (with the GST split as currently configured) and the US-dollar price (no Indian GST). It's a one-time payment, and it says what is and isn't included. The figures are computed from the checkout code. |
| **Contact Us** | `/legal/contact` | Legal name, address, GSTIN, support email, phone and hours, the grievance officer, and the response times you commit to. |
| **Delete your account** | `/legal/delete-account` | The public page to give Google Play. Deletion today means emailing us; a person carries it out by hand. It says what is deleted, what is kept for tax law and why, backups, what happens to the licence, and how long it takes. The Privacy Policy's section 13 shows the same text, so the two can't disagree. |

## 2. Every placeholder, and what we need from you

41 placeholders are open. `node scripts/check-legal-placeholders.mjs` (run from `portal/`) lists
them with their file and line; `--strict` fails until all are filled **and** the approval flag
is on. "Proposed" is a suggestion, not a decision.

### Client (business owner)
| Placeholder | Question | What we need | Proposed |
|---|---|---|---|
| `LEGAL_NAME`, `ENTITY_TYPE`, `REGISTERED_ADDRESS` | Q-01 | Exact registered name, type (sole proprietorship / LLP / private limited…), full registered address | — |
| `PLAY_LISTING_NAME`, `PLAY_DEVELOPER_NAME` | Q-26 | The app name and developer name exactly as Google Play will show them | One product name everywhere; developer = the legal name |
| `SUPPORT_EMAIL`, `PRIVACY_EMAIL` | Q-11 | Real, monitored addresses (the app today shows `support@danlite.example`, which cannot receive mail) | `support@danlite.in`; `privacy@danlite.in`, or the same address |
| `SUPPORT_PHONE`, `SUPPORT_HOURS` | Q-27 | A number someone answers, and the hours | "Mon–Sat, 10:00–18:00 IST" |
| `GRIEVANCE_OFFICER_NAME`, `_DESIGNATION`, `_EMAIL`, `_PHONE` | Q-11 | A named person | The owner / proprietor |
| `GRIEVANCE_ACK_TIME`, `GRIEVANCE_RESOLUTION_TIME` | Q-11 | What you commit to | "48 hours", "one month" (the E-Commerce Rules standard) |
| `PRIVACY_RESPONSE_TIME` | Q-11 | What you commit to (the law allows up to 90 days) | "30 days" |
| `MIN_AGE` | Q-10 | Minimum age | "18" |
| `SALES_COUNTRIES_CONFIRMED` | Q-17 | Confirm the 8 sign-up countries are where you sell (UK and Germany bring in EU/UK data law) | Consider India only until Q-05/Q-17 are settled; then set to "" |
| `CHANGE_OF_MIND_RULE`, `DEFECT_REPORT_WINDOW`, `REFUND_DECISION_TIME` | Q-29 | Your refund choice (see §3) | Option A: 7 days; 30 days; "5 working days" |
| `SHUTDOWN_NOTICE_PERIOD`, `DISCONTINUATION_REMEDY` | Q-06 | What customers get if the service closes | "90 days"; see the sentences below |
| `LAST_UPDATED` | Q-32 | The date the approved text goes live | Deployment date |

Suggested sentences for `DISCONTINUATION_REMEDY` (choose one; the lawyer should check):
- *Refund, pro rata:* "If we close the service within 24 months of your purchase, we will refund the price you paid."
- *Offline unlock (needs engineering that does not exist today):* "Before we close, we will release a final version of the app that works without our servers."
- *Notice only:* "" (empty): the page then promises only the notice period. This is the weakest option in a consumer dispute.

### Accountant
| Placeholder | Question | What we need | Proposed |
|---|---|---|---|
| `GSTIN` | Q-03 | GSTIN, or confirmation you're not registered (then GST lines must come off the receipt and pricing) | — |
| `GST_TREATMENT_CONFIRMED` | Q-03 | Confirm "₹ price includes 18% GST" as coded in `lib/gst.ts`; set to "" once confirmed | — |
| `EXPORT_TAX_CONFIRMED` | Q-05 | Confirm "no Indian GST on sales outside India" (LUT filed? foreign VAT?); set to "" once confirmed | — |
| `INVOICE_DELIVERY` | Q-03 | How customers get a proper tax invoice (none is emailed or downloadable today) | Until B-08 ships: "Email us with your payment reference and we will send you a tax invoice." |
| `REFUND_TAX_TREATMENT` | Q-03 | GST on refunds; credit notes | "If you receive a refund, we issue a credit note for the tax included in the price." (Only true once credit notes exist.) |

### Lawyer
| Placeholder | Question | What we need | Proposed |
|---|---|---|---|
| `GOVERNING_COURT_CITY` | Q-28 | Court city (non-exclusive for consumers) | City of the registered office |
| `TRANSFER_SAFEGUARDS` | Q-15 | The legal basis for sending data to the US, EU and Japan, only as true (DPAs signed?) | e.g. "Each provider is bound by a contract that requires it to protect your data and use it only on our instructions." **Only once the DPAs are accepted.** |
| `EU_UK_REPRESENTATIVE` | Q-17 | Name/address of an EU and UK representative, or delete the line if UK/Germany are dropped | — |
| `NOTICE_LANGUAGES` | Q-19 | Languages the notice is offered in | "This policy is available in English. To receive it in Hindi or another language listed in the Eighth Schedule to the Constitution, email us." |
| (no placeholder) Q-33 | Q-33 | Check the plain-word lawful bases in Privacy §6, and whether crash reports carrying vehicle data need consent | — |

### Owner (dashboards and operations)
| Placeholder | Question | What we need |
|---|---|---|
| `AUTH_EMAIL_SENDER` | Q-22 | Who sends the 6-digit login codes (Supabase default or custom SMTP), and from which address |
| `ACTIVATION_SENDER_ADDRESS` | Q-30 | The "from" address of the activation emails (the `ACTIVATION_FROM_EMAIL` secret) |
| `PROVIDER_LOG_RETENTION` | Q-31 | How long Supabase, Hostinger, Resend and Sentry keep logs |
| `HOSTINGER_LOCATION`, `GITHUB_LOCATION` | Q-15 | Server region shown in the Hostinger panel; GitHub's data location for this account |
| `DELETION_COMPLETION_TIME` | Q-08 | Proposed "30 days" |
| `RETENTION_SECURITY_RECORDS`, `RETENTION_AUDIT_LOG` | Q-09 | Proposed "12 months" (security records); "8 years for payment-related entries, 2 years for others" (audit log) |
| (approval) | Q-32 | Flip `APPROVED_FOR_PUBLICATION` to `true` only after sign-off |

## 3. Refund policy: your three realistic options

What every option keeps (because the law or basic fairness requires it): refunds for duplicate
payments, for paid-but-no-licence, and for a licence we wrongly end; a "not as described" route;
and a line saying the policy doesn't reduce statutory rights. Razorpay and consumer rules require
the policy to be **shown before purchase**, and the checkout links to it.

| | **A. Short no-questions window** | **B. Only if it doesn't work as described, or a payment error** | **C. Non-refundable except where the law requires** |
|---|---|---|---|
| Sentence for `CHANGE_OF_MIND_RULE` | "You can ask for a full refund for any reason within 7 days of purchase. You do not need to tell us why." | "We do not give refunds for a change of mind. The cases in sections 2 and 3 are always covered." | "Purchases are final. We do not give refunds for a change of mind, or for any reason other than those in sections 2 and 3 and those the law requires." |
| `DEFECT_REPORT_WINDOW` | 30 days | 30 days | "a reasonable time" |
| For | Clearest for customers and reviewers. Fewest arguments. Chargebacks drop because a refund is easier than a bank dispute. At this price, handling one dispute costs more than refunding. | Protects revenue. Common for software. | Simplest to say. |
| Against | Someone can use the app for a week and then ask for their money back. That exposure is small: the refund switches the licence off automatically, and the price is low. Razorpay may not return its fee on refunded payments (check your plan). | Every "doesn't work" claim needs judging. Customers who are refused tend to raise chargebacks instead, which cost more and can hurt your standing with Razorpay. | A bare "no refunds" cannot override statutory rights, and consumer commissions look at such clauses sceptically. It invites chargebacks and bad reviews, and a reviewer may question it. |

**Recommendation: A, with 7 days** (48 hours if you're worried about abuse). A clear, fair
window usually *reduces* disputes and chargebacks.

**Why the old draft's rule was dropped:** version 0.1 offered "a refund within 24 hours if the
licence has not been activated on a device". The system **cannot tell** whether a licence was
used. The app records the phone when the customer signs up, which is *before* they pay, and
nothing records a first use after payment. A rule we can't check would be applied inconsistently,
and an inconsistent refund rule is what loses a consumer case.

**Things that are true today whichever option you pick** (all written honestly into the page):
- Any refund, even a partial one, ends the whole licence automatically (E-019, E-020).
- Refunding a **duplicate** payment also switches off the customer's only licence. Someone has to
  switch it back on by hand (E-106). The page says so. Backlog B-23 fixes it.
- There are no credit notes yet (T6), so the tax sentence stays with your accountant.

## 4. The honest gaps: what a good policy would promise but the product can't do yet

For each gap, the draft says what is true instead of hiding it. Each has a backlog item in
[RISK_REGISTER.md](RISK_REGISTER.md) Part 3.

| # | A good policy would say… | Today | What the draft says instead | Fix |
|---|---|---|---|---|
| 1 | "You agreed to these terms when you signed up." | No checkbox and no record of consent anywhere (0 consent records) | Terms say that creating an account or paying means agreement. That's weak evidence until a checkbox and record exist. It doesn't claim consent was recorded. | B-04, B-20 |
| 2 | "Delete your account in the app." (Play requires this) | No in-app or automatic deletion. A normal delete fails for anyone who has paid, because of the payment-record link | "Email us; a person does it by hand." The rows to delete for payers must be removed one by one | B-06, B-26 |
| 3 | "We keep X for N months, then delete it automatically." | Nothing expires; there is no scheduler | Periods are placeholders, plus "where automatic deletion isn't in place, we delete by hand" | B-07, B-26 |
| 4 | "Your vehicle data never leaves your phone." | Crash reports can carry recent adapter messages to Sentry | Disclosed plainly (Privacy §5). Once B-11 ships, the sentence can be shortened | B-11 |
| 5 | "No third parties see your phone's IP." | The app downloads its font from Google at first run | Disclosed (Privacy §5, §8) | B-12 |
| 6 | "You'll receive a GST invoice." | Receipt on screen only, missing required GST fields; no email, no download; no credit notes | Delivery §5 and Refund §11 are placeholders for the accountant | B-08 |
| 7 | "Refunding a duplicate won't affect your licence." | It does, automatically | Said honestly: we switch it back on by hand | B-23 |
| 8 | "We handle chargebacks automatically." | Dispute events are ignored | "We may end the licence", by hand | B-10 |
| 9 | "The app tells you whether clearing codes worked." | It always says "cleared" | Safety box: "may show success even if not; read the codes again" | B-14 |
| 10 | Product claims that match the Terms | About screen says "Works with all ELM327 OBD2 adapters", "HUD for night driving", "Full UI in 23 languages" | Terms say adapters vary and many can't read ABS; never use while riding. **The app still contradicts this** | B-28, B-14 |
| 11 | "Lifetime." | The app stops within 14 days if the servers stop, and the free database plan can pause | "Lifetime" defined as while we run the service, with notice | Q-06, Q-21 |
| 12 | "You must be 18+" (checked) | No age question | "The app doesn't currently ask your age" | B-04 |
| 13 | Privacy link inside the app for everyone | Only on the Account screen, only for licensed users, and not tappable | Pages exist at stable URLs; the app must link to them | B-02, B-25 |
| 14 | Working support contact in the app | The app shows `support@danlite.example` | The Contact page will show the real address, but **the app will still show the placeholder** until an app update | B-03 |
| 15 | "Here's who viewed your data." | Staff views are not logged; only staff actions are | The Privacy Policy mentions staff access and says actions are logged. It makes no claim about views | B-15 |
| 16 | "We'll notify you of a breach within X hours." | No breach procedure exists | "We will tell you and report it as the law requires" | A-26, B-26 |
| 17 | Notice in the customer's language | English only on the web; privacy lines in the app only in English and Hindi | Placeholder `NOTICE_LANGUAGES` | Q-19 |
| 18 | "Sign in with email" consistently | Public `/activate` page still says "email or mobile number"; so do some app texts | Terms say email only | B-24 |
| 19 | The in-app notice matches the policy | App says "Your email is used only to secure your account", which is false | The policy discloses the real uses; **the app contradicts it** until B-01 ships | B-01 |
| 20 | "We'll never contact your phone number." | The app promises this, but the number is passed to Razorpay, which may text receipts | The policy says the number goes to Razorpay | Q-12 |
| 21 | Checkout copy consistent with "lifetime" | Checkout says "Unlocks the full app … permanently" | The Terms define lifetime; the checkout text should change | B-22 |
| 22 | Customer can find their receipt later | The receipt page isn't linked from the account page | Delivery Policy says "save or screenshot it" | B-27 |
| 23 | One refund policy online | danlite.in (which billing.danlite.in's home page redirects to) shows a WooCommerce **sample** refund page | Can't be fixed from this portal. Replace or remove that page before Razorpay reviews either site | A-01, Q-01 |

## 5. Additions beyond the brief

| Addition | Harm it prevents | Needs your decision? |
|---|---|---|
| A `/legal` index page listing every policy | Reviewers missing a page; one address to give Razorpay | No |
| Deletion page at `/legal/delete-account`, not `/account/delete` | `/account/*` redirects signed-out visitors, so Play's reviewer would never see the page | No |
| Deletion text written once and shown on both the Privacy Policy and the deletion page | The two documents drifting apart | No |
| Draft banner that turns off only when every placeholder is filled **and** approval is recorded | Publishing unapproved text just because the blanks were filled | Q-32 |
| Placeholder checker that maps each gap to its open question and fails in strict mode | Forgetting a gap; a gap nobody owns | No |
| Duplicate-refund behaviour found and disclosed (it switches off the licence) | Promising "your licence stays active", which the system breaks | Q-29, B-23 |
| Dropped the 0.1 "not activated on a device" refund test | A refund rule the business can't verify or apply fairly | Q-29 |
| "Never share your login code, card PIN or CVV; we will never ask" | Phishing using a brand whose emails customers are trained to click (DMARC is `p=none`) | No |
| Acceptable-use ban on using the app to hide faults from a buyer, inspector or mechanic | The app's clear-codes feature being used to deceive a vehicle buyer | No |
| Terms reserve the right to switch on the app for everyone during an outage, without granting licences | Customers claiming a free licence after the emergency bypass (used once already) | No |
| "Performance figures are estimates" and HUD/test features limited to passengers or closed courses | Injury or liability claims from on-road speed tests the app invites | Q-18 |
| Name-consistency notes: the app's "Terms of Service" and "Refund Policy" are the same documents | Play and Razorpay reviewers, and customers, seeing mismatched names | B-25 |
| Exact recommended changes for checkout consent (B-20) and activation-email footer (B-21) | Terms nobody was shown before paying | Q-02 (email) |
| Q-35: should the policy footer link to Pricing, given the Play payments policy? | A Play reviewer treating the policy pages as a route to outside payment | Yes |
| Q-34: list of promises that someone must carry out by hand until automated | Policies that become false because nobody is doing what they promise | Yes |
| New evidence E-104–E-114, V-07, V-08 in SOURCES.md | Unsupported statements | No |

## 6. Order of work to publish

1. Get the answers above (client, accountant, lawyer, owner).
2. Fill `portal/lib/legal-config.ts`. Run `node scripts/check-legal-placeholders.mjs --strict`
   until the only remaining failure is the approval flag.
3. Lawyer and CA review the rendered pages (print them from the browser; the layout prints cleanly).
4. Set `APPROVED_FOR_PUBLICATION = true`, set `LAST_UPDATED`, add a line to `CHANGELOG`. Strict
   check passes.
5. Review and merge the branch.
6. **Redeploy the portal on Hostinger by hand.** A git push does not rebuild it. Afterwards,
   compare the `main-app-*.js` chunk names, because the ETag doesn't change reliably.
7. Check each URL live: `/legal`, `/legal/terms`, `/legal/privacy`, `/legal/refund`,
   `/legal/delivery`, `/legal/pricing`, `/legal/contact`, `/legal/delete-account`. Each should
   return 200, show no yellow boxes or banner, have no `X-Robots-Tag` header, and `robots.txt`
   should show `Allow: /legal`.
8. Give Razorpay the URLs (Website details: Terms, Privacy, Cancellation and Refunds, Shipping =
   Delivery, Contact, Pricing), and make sure danlite.in no longer shows the sample refund page.
9. In Play Console, enter the privacy policy URL `https://billing.danlite.in/legal/privacy` and the
   account-deletion URL `https://billing.danlite.in/legal/delete-account`. This is only after the
   in-app deletion path (B-06) and the app-side links (B-02, B-25) ship. Play requires both.
