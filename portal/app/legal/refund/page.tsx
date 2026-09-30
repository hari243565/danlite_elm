// Cancellation and Refund Policy. Every factual sentence here is traced in
// docs/legal/CLAIM_LEDGER.md (rows R-nn). The client has not chosen the
// refund model yet: the change-of-mind rule, the defect window and the
// decision time are config placeholders (Q-29), with the options set out in
// docs/legal/CLIENT_REVIEW_PACK.md. Everything else holds for every option.

import type { Metadata } from 'next';
import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import { Email, INDEXABLE, LegalDoc, T, type Section } from '../_components/legal';

export const metadata: Metadata = {
  title: 'Cancellation and Refund Policy — Danlite ELM',
  description:
    'When you can cancel or get a refund for the Danlite ELM licence, how to ask, and how long it takes.',
  robots: INDEXABLE,
};

const K = cfg.CONTACT;
const R = cfg.REFUND;

const summary = (
  <ul>
    <li>
      The licence is a <strong>one-time purchase</strong>. There is no subscription, so there is
      nothing to cancel later and you will never be charged again.
    </li>
    <li>
      We always refund <strong>duplicate payments</strong>, and payments where you were charged but
      we cannot give you a working licence.
    </li>
    <li>
      If the app <strong>does not work as described</strong>, tell us within{' '}
      <T v={R.defectReportWindow} /> of buying.
    </li>
    <li>
      Change of mind: <T v={R.changeOfMindRule} />
    </li>
    <li>
      <strong>Any refund, full or partial, ends the licence</strong> (except a refund of a duplicate
      payment).
    </li>
    <li>
      Refunds go back to the <strong>original payment method</strong>. After we send the refund,
      your bank or card issuer may take several working days to show it.
    </li>
    <li>This policy does not reduce your rights under consumer law.</li>
  </ul>
);

const sections: Section[] = [
  {
    id: 'cancelling',
    title: 'Cancelling',
    body: (
      <>
        <p>
          <strong>Before you pay:</strong> you can stop at any point. Close the checkout page or the
          Razorpay payment window and nothing is charged. Creating an account does not commit you to
          buying.
        </p>
        <p>
          <strong>After you pay:</strong> the licence is a one-time purchase with no renewal, so
          there is no subscription to cancel. If you want your money back, the rest of this policy
          explains when that is possible.
        </p>
      </>
    ),
  },
  {
    id: 'always',
    title: 'When we always refund',
    body: (
      <ul>
        <li>
          <strong>Duplicate payment.</strong> If you were charged more than once for the same
          licence, we refund the extra payment in full. At present our system ends the licence
          automatically whenever any refund is made, so after refunding a duplicate we switch your
          licence back on by hand. For a short time the app may show “No active licence”.
        </li>
        <li>
          <strong>Charged, but no working licence.</strong> If you paid and the licence did not
          switch on, we will fix it. If we cannot fix it within a reasonable time, we refund you in
          full.
        </li>
        <li>
          <strong>We ended your licence and you were not at fault.</strong> We restore it, or refund
          what you paid.
        </li>
      </ul>
    ),
  },
  {
    id: 'not-as-described',
    title: 'If the app does not work as described',
    body: (
      <>
        <p>
          If the app does not do what we describe, tell us within{' '}
          <T v={R.defectReportWindow} /> of buying. We will try to fix the problem. If we cannot fix
          it within a reasonable time, we refund you in full.
        </p>
        <p>
          What the app can read depends on your vehicle and on your adapter. Many adapters cannot
          read some systems, such as ABS. A limit explained in our Terms is not a fault. Before you buy, check our{' '}
          <Link href="/legal/terms#adapters-vehicles">notes on adapters and vehicles</Link>. If you
          are unsure, contact us before you buy.
        </p>
      </>
    ),
  },
  {
    id: 'change-of-mind',
    title: 'Change of mind',
    body: (
      <p>
        <T v={R.changeOfMindRule} />
      </p>
    ),
  },
  {
    id: 'not-covered',
    title: 'What this policy does not cover',
    body: (
      <>
        <ul>
          <li>
            What your vehicle reports. The app shows the data your vehicle provides. Seeing fewer,
            more or different fault codes than you expected is not a fault in the app.
          </li>
          <li>
            A licence we ended because it was bought fraudulently, charged back, or used in breach
            of our <Link href="/legal/terms#acceptable-use">Terms</Link>.
          </li>
        </ul>
        <p>
          None of this limits a right you have under consumer law (see{' '}
          <a href="#your-rights">section 13</a>).
        </p>
      </>
    ),
  },
  {
    id: 'how-to-ask',
    title: 'How to ask for a refund',
    body: (
      <>
        <p>
          Email <Email v={K.supportEmail} /> from the email address on your account, with:
        </p>
        <ul>
          <li>the payment reference or invoice number from your receipt;</li>
          <li>a short description of the problem, if it is not a change-of-mind request.</li>
        </ul>
        <p>
          If you can, include the Account ID from the Account screen in the app. You can also call
          us; see our <Link href="/legal/contact">Contact page</Link>.
        </p>
      </>
    ),
  },
  {
    id: 'timeline',
    title: 'What happens next, and how long it takes',
    body: (
      <ol>
        <li>We confirm we have your request.</li>
        <li>
          We tell you our decision within <T v={R.decisionTime} />. If we say no, we explain why and
          how to take it further.
        </li>
        <li>
          If we approve it, we send the refund through Razorpay to the original payment method. We
          cannot refund to a different card, account or UPI ID.
        </li>
        <li>
          Your bank or card issuer then usually takes several working days to show the refund. That
          part is outside our control. If it has not arrived after 10 working days, contact us and
          we will give you the refund reference to show your bank.
        </li>
      </ol>
    ),
  },
  {
    id: 'licence-effect',
    title: 'What a refund does to your licence',
    body: (
      <p>
        When a refund is made, <strong>the licence it paid for ends</strong>. At present this
        happens for <strong>any</strong> refund, including a partial one. Before we send a partial
        refund, we will tell you it will end your licence, so you can choose. If we refund a
        duplicate payment, we switch your one licence back on afterwards (see section 2).
      </p>
    ),
  },
  {
    id: 'failed-payments',
    title: 'Failed or pending payments',
    body: (
      <p>
        If money left your account but the payment failed or the page showed an error, do not pay
        again straight away. Email us with the details and the time of the attempt. We will check
        with Razorpay and either switch on your licence or make sure the money is returned.
      </p>
    ),
  },
  {
    id: 'chargebacks',
    title: 'Chargebacks and payment disputes',
    body: (
      <p>
        Please contact us before you dispute a payment with your bank. It is usually faster for
        you. If a payment is disputed, reversed or charged back, we may end the licence it paid
        for. If the dispute is decided in our favour, we will restore the licence.
      </p>
    ),
  },
  {
    id: 'tax',
    title: 'Tax on refunds',
    body: (
      <p>
        <T v={R.taxTreatment} />
      </p>
    ),
  },
  {
    id: 'international',
    title: 'Customers outside India',
    body: (
      <p>
        Refunds are made in the currency you paid (US dollars). The amount that reaches you in your
        own currency may differ from what you paid, because of exchange rates or your bank’s fees.
        We cannot control this.
      </p>
    ),
  },
  {
    id: 'your-rights',
    title: 'Your legal rights',
    body: (
      <p>
        This policy adds to your rights under the Consumer Protection Act, 2019 and other laws that
        apply to you. It does not take them away. If the law gives you a wider right to a refund,
        that right applies. If you are not happy with our decision, you can use our grievance
        process (see our <Link href="/legal/contact">Contact page</Link>) or approach a consumer
        commission.
      </p>
    ),
  },
];

export default function RefundPolicy() {
  return (
    <LegalDoc
      title="Cancellation and Refund Policy"
      intro={
        <>
          For the one-time {cfg.BUSINESS.productName} licence. Please read this before you buy. The
          app calls this page “Refund Policy”; it is the same document.
        </>
      }
      summary={summary}
      sections={sections}
    />
  );
}
