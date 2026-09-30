// Pricing. Every figure on this page is computed from lib/gst.ts (the same
// module checkout and the receipt use), so a price or tax change there changes
// this page too. No price is typed here. Traced in docs/legal/CLAIM_LEDGER.md
// (rows PR-nn).

import type { Metadata } from 'next';
import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import { GST_ON_EXPORTS, formatMinor, priceFor } from '@/lib/gst';
import { H3, INDEXABLE, LegalDoc, Price, T, Table, type Section } from '../_components/legal';

export const metadata: Metadata = {
  title: 'Pricing — Danlite ELM',
  description: 'The price of the Danlite ELM lifetime licence in India and elsewhere. One payment, no subscription.',
  robots: INDEXABLE,
};

const IN = priceFor('IN');
const INTL = priceFor('US');
const money = (b: typeof IN, minor: number) => `${b.currency === 'USD' ? 'US' : ''}${b.symbol}${formatMinor(minor)}`;

const summary = (
  <ul>
    <li>
      India: <Price>{money(IN, IN.totalMinor)}</Price> one time. {IN.taxApplies ? IN.note : ''}{' '}
      <T v={cfg.TAX.gstTreatmentConfirmed} />
    </li>
    <li>
      Everywhere else: <Price>{money(INTL, INTL.totalMinor)}</Price> one time.{' '}
      {GST_ON_EXPORTS ? '' : 'No Indian GST is charged.'} <T v={cfg.TAX.exportTreatmentConfirmed} />
    </li>
    <li>
      <strong>One payment. No subscription, no renewal, no extra fees from us.</strong>
    </li>
    <li>The country you choose when you create your account decides which price applies.</li>
  </ul>
);

const breakdown = (b: typeof IN) =>
  b.taxApplies
    ? [
        ['Licence (before GST)', money(b, b.baseMinor)],
        ['GST', money(b, b.taxMinor)],
        ['Total you pay', money(b, b.totalMinor)],
      ]
    : [['Total you pay', money(b, b.totalMinor)]];

const sections: Section[] = [
  {
    id: 'prices',
    title: 'Prices',
    body: (
      <>
        <H3>Customers in India ({IN.currency})</H3>
        <Table head={['Item', 'Amount']} rows={breakdown(IN).map(([k, v]) => [k, <Price key={k}>{v}</Price>])} />
        <p>
          {IN.note} <T v={cfg.TAX.gstTreatmentConfirmed} />
        </p>

        <H3>Customers in every other country ({INTL.currency})</H3>
        <Table
          head={['Item', 'Amount']}
          rows={breakdown(INTL).map(([k, v]) => [k, <Price key={k}>{v}</Price>])}
        />
        <p>
          {GST_ON_EXPORTS
            ? 'Indian GST treatment for customers outside India is still being confirmed.'
            : 'No Indian GST is charged, because a sale to a customer outside India is treated as an export of services.'}{' '}
          <T v={cfg.TAX.exportTreatmentConfirmed} /> We do not add any tax of your own country.
          Your bank may charge a currency-conversion or foreign-transaction fee; that fee is set by
          your bank, not by us.
        </p>
      </>
    ),
  },
  {
    id: 'included',
    title: 'What the price includes',
    body: (
      <>
        <ul>
          <li>
            A lifetime licence for the {cfg.BUSINESS.productName} Android app, as defined in our{' '}
            <Link href="/legal/terms#lifetime">Terms</Link>: no end date and no renewal fee for as
            long as we run the service.
          </li>
          <li>Use of the app on one phone at a time. You can move to a new phone whenever you like.</li>
          <li>Use without internet for up to 14 days between licence checks.</li>
        </ul>
        <p>
          <strong>Not included:</strong> the OBD adapter you plug into your vehicle, which you buy
          separately from someone else, and your mobile data.
        </p>
      </>
    ),
  },
  {
    id: 'which-price',
    title: 'Which price applies to you',
    body: (
      <p>
        The country you choose when you create your account in the app decides your price and
        currency: India is billed in rupees, every other country in US dollars. You cannot change
        the country yourself after sign-up. If you chose the wrong one, contact us before you pay.
      </p>
    ),
  },
  {
    id: 'how-to-pay',
    title: 'How to pay',
    body: (
      <p>
        Create an account in the app, and we will email you a link to our billing website. You pay
        there, in Razorpay’s secure payment window, using the payment methods Razorpay offers you
        at checkout. We never see your card, UPI or bank details. Your licence switches on
        automatically after payment; see the <Link href="/legal/delivery">Delivery Policy</Link>.
        Refunds are covered by our <Link href="/legal/refund">Cancellation and Refund Policy</Link>.
      </p>
    ),
  },
  {
    id: 'changes',
    title: 'Price changes',
    body: (
      <p>
        We may change the price for new purchases. The price you pay is the one shown on the
        checkout page when you pay. A price change never affects a licence you have already bought,
        and there is nothing further to pay for it.
      </p>
    ),
  },
];

export default function PricingPage() {
  return (
    <LegalDoc
      title="Pricing"
      intro={<>What the {cfg.BUSINESS.productName} licence costs and what you get for it.</>}
      summary={summary}
      sections={sections}
    />
  );
}
