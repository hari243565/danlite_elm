// Delivery Policy (Razorpay's "Shipping policy" requirement, for a digital
// product). Every factual sentence here is traced in docs/legal/CLAIM_LEDGER.md
// (rows D-nn).

import type { Metadata } from 'next';
import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import { Email, INDEXABLE, LegalDoc, T, type Section } from '../_components/legal';

export const metadata: Metadata = {
  title: 'Delivery Policy — Danlite ELM',
  description:
    'How the Danlite ELM licence is delivered: digitally, to your account, with no physical shipping.',
  robots: INDEXABLE,
};

const K = cfg.CONTACT;

const summary = (
  <ul>
    <li>
      <strong>Nothing is shipped.</strong> You buy a digital licence, and it is delivered to your
      account.
    </li>
    <li>
      Your licence usually switches on <strong>within a few minutes</strong> of Razorpay confirming
      your payment. Open the app, signed in to the same account, and tap Refresh.
    </li>
    <li>
      The link we email you to buy <strong>works once and expires after 15 minutes</strong>. You
      can ask for a new one at any time.
    </li>
    <li>
      No email? Check your spam folder, then ask for a new link. If you still have a problem,
      contact us.
    </li>
  </ul>
);

const sections: Section[] = [
  {
    id: 'what',
    title: 'What you receive',
    body: (
      <>
        <p>
          You receive a <strong>licence</strong> to use the {cfg.BUSINESS.productName} Android app
          on your account (see our <Link href="/legal/terms#licence">Terms</Link>). It is digital.
          There are no physical goods, no discs and no shipping charges. We do not supply OBD
          adapters; you buy those separately from someone else.
        </p>
        <p>
          You install the app itself from Google Play or wherever we make it available. It is not
          sent by email.
        </p>
      </>
    ),
  },
  {
    id: 'how',
    title: 'How delivery works',
    body: (
      <ol>
        <li>
          <strong>Create an account in the app.</strong> We then email you a link to our billing
          website automatically.
        </li>
        <li>
          <strong>Open the link</strong> on any phone or computer. It signs you in to
          billing.danlite.in and takes you to the checkout page.
        </li>
        <li>
          <strong>Pay</strong> in Razorpay’s payment window. When the payment succeeds you see a
          receipt. Please save or screenshot it.
        </li>
        <li>
          <strong>Your licence switches on automatically</strong> when Razorpay confirms the
          payment to us. This usually takes a few minutes.
        </li>
        <li>
          <strong>Open the app</strong>, signed in with the same email address. If it still shows
          “No active licence yet”, tap <strong>Refresh</strong>. The phone needs an internet
          connection for this first check.
        </li>
      </ol>
    ),
  },
  {
    id: 'links',
    title: 'The emailed link',
    body: (
      <>
        <p>
          Each link works <strong>once</strong> and <strong>expires 15 minutes</strong> after it is
          sent. This protects your account if someone else sees the email.
        </p>
        <p>To get a new link:</p>
        <ul>
          <li>
            go to <Link href="/activate">billing.danlite.in/activate</Link> and enter the email
            address you signed up with; or
          </li>
          <li>in the app, on the “No active licence yet” screen, tap “Email me a new link”.</li>
        </ul>
        <p>
          To prevent abuse, you can request up to 3 links an hour for the same email address. If
          you reach the limit, wait an hour.
        </p>
      </>
    ),
  },
  {
    id: 'not-arrived',
    title: 'If the email or licence does not arrive',
    body: (
      <ol>
        <li>
          Check your spam or junk folder. Our emails come from <T v={K.activationSender} />.
        </li>
        <li>Make sure you are looking in the inbox of the email address you signed up with.</li>
        <li>Ask for a new link as described above. An older link will not work once expired.</li>
        <li>
          If you have paid but the app still shows no licence after you tap Refresh, email{' '}
          <Email v={K.supportEmail} /> with the payment reference from your receipt. If we cannot
          get your licence working within a reasonable time, we refund you. See the{' '}
          <Link href="/legal/refund#always">Refund Policy</Link>.
        </li>
      </ol>
    ),
  },
  {
    id: 'receipt',
    title: 'Receipt and invoice',
    body: (
      <>
        <p>
          After a successful payment, the billing website shows a receipt with the amount, tax,
          payment reference, invoice number and date.
        </p>
        <p>
          <T v={cfg.TAX.invoiceDelivery} />
        </p>
      </>
    ),
  },
  {
    id: 'where',
    title: 'Where we sell',
    body: (
      <>
        <p>
          When you create an account, the app lets you choose one of these countries:{' '}
          {cfg.SIGNUP_COUNTRIES.join(', ')}. <T v={cfg.SALES_COUNTRIES_CONFIRMED} />
        </p>
        <p>
          India is billed in Indian rupees. Every other country is billed in US dollars. See our{' '}
          <Link href="/legal/pricing">Pricing page</Link>.
        </p>
      </>
    ),
  },
];

export default function DeliveryPolicy() {
  return (
    <LegalDoc
      title="Delivery Policy"
      intro={
        <>
          How you receive what you buy. {cfg.BUSINESS.productName} is a digital product, so this
          page replaces a shipping policy.
        </>
      }
      summary={summary}
      sections={sections}
    />
  );
}
