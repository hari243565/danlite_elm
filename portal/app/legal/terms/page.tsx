// Terms and Conditions. Every factual sentence here is traced in
// docs/legal/CLAIM_LEDGER.md (rows T-nn). Prices come from lib/gst.ts.

import type { Metadata } from 'next';
import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import { formatMinor, priceFor } from '@/lib/gst';
import {
  Email,
  INDEXABLE,
  LegalDoc,
  Price,
  SafetyBox,
  T,
  type Section,
} from '../_components/legal';

export const metadata: Metadata = {
  title: 'Terms and Conditions — Danlite ELM',
  description:
    'The agreement for the Danlite ELM lifetime licence: what you buy, how the licence works, safety, refunds and your rights.',
  robots: INDEXABLE,
};

const B = cfg.BUSINESS;
const K = cfg.CONTACT;
const IN = priceFor('IN');
const INTL = priceFor('US');

const summary = (
  <ul>
    <li>
      You buy a <strong>one-time licence</strong> for the {B.productName} app. There is no
      subscription.
    </li>
    <li>
      “Lifetime” means <strong>for as long as we run the service</strong>, not forever. The app
      checks your licence with our servers at least every 14 days. See section 5.
    </li>
    <li>
      The licence is for <strong>one person</strong> and works on <strong>one phone at a
      time</strong>. Signing in on another phone signs the first one out.
    </li>
    <li>
      You buy on our website, not in the app, using a link we email you. Payment is handled by
      Razorpay.
    </li>
    <li>
      Any refund, full or partial, ends the licence (except a refund of a duplicate payment). See
      the{' '}
      <Link href="/legal/refund">Cancellation and Refund Policy</Link>.
    </li>
    <li>
      Nothing in these terms takes away your rights under consumer law. You can go to a consumer
      commission where you live.
    </li>
  </ul>
);

const safety = (
  <SafetyBox title="Safety first: read this before you use the app">
    <ul>
      <li>
        <strong>Never use the app while riding or driving.</strong> Set it up while parked. Use the
        HUD screen and performance tests only as a passenger, or on a closed course where that is
        allowed, never on a public road.
      </li>
      <li>
        The app shows information your vehicle reports. It is <strong>not an inspection</strong>{' '}
        and does not replace a qualified mechanic.
      </li>
      <li>
        <strong>Brake and ABS warnings need a professional.</strong> Do not ride or drive a vehicle
        with a brake or ABS fault until a mechanic has checked it.
      </li>
      <li>
        “No fault codes” does <strong>not</strong> mean the vehicle is safe. Some faults are not
        stored as codes, some systems cannot be read, and many adapters cannot reach every system
        (such as ABS).
      </li>
      <li>
        <strong>Clearing codes can hide a fault</strong> and erase evidence a mechanic needs. The
        app may show a success message even if the vehicle did not accept the clear command. Always
        read the codes again to check.
      </li>
    </ul>
  </SafetyBox>
);

const sections: Section[] = [
  {
    id: 'who-we-are',
    title: 'Who we are and what these terms cover',
    body: (
      <>
        <p>
          These terms are an agreement between you and <T v={B.legalName} /> (
          <T v={B.entityType} />), <T v={B.registeredAddress} /> (“we”, “us”). They cover the{' '}
          {B.productName} Android app (shown on your phone as “{B.appLabel}” and on Google Play as{' '}
          <T v={B.playListingName} />), the licence you buy for it, and our billing website
          billing.danlite.in.
        </p>
        <p>
          Our <Link href="/legal/privacy">Privacy Policy</Link>,{' '}
          <Link href="/legal/refund">Cancellation and Refund Policy</Link> and{' '}
          <Link href="/legal/delivery">Delivery Policy</Link> are part of these terms.
        </p>
      </>
    ),
  },
  {
    id: 'acceptance',
    title: 'Accepting these terms, and who can use the app',
    body: (
      <>
        <p>
          By creating an account or buying a licence you agree to these terms. If you do not agree,
          do not create an account or buy.
        </p>
        <p>
          You must be at least <T v={cfg.TERMS.minimumAge} /> to create an account or buy a
          licence.
        </p>
      </>
    ),
  },
  {
    id: 'account',
    title: 'Your account',
    body: (
      <>
        <p>
          You create your account in the app with your email address. Each time you log in we email
          you a one-time code. There is no password. Anyone who can read your email can log in to
          your account, so keep your email account secure.
        </p>
        <p>
          The country you choose when you sign up sets your price and currency. You cannot change
          it yourself. If you chose the wrong country, contact us before you buy.
        </p>
        <p>
          Tell us promptly at <Email v={K.supportEmail} /> if you think someone else has used your
          account. You can sign out every device from your account page on billing.danlite.in.
        </p>
      </>
    ),
  },
  {
    id: 'licence',
    title: 'What you are buying: the licence',
    body: (
      <>
        <p>
          You buy a <strong>licence</strong>: permission to use the app. You do not buy the app
          itself. The licence is:
        </p>
        <ul>
          <li>
            <strong>Personal.</strong> It is for you, including use on vehicles in your own
            workshop. It is not for sharing.
          </li>
          <li>
            <strong>Not transferable.</strong> You cannot sell, give or lend it to someone else.
          </li>
          <li>
            <strong>One phone at a time.</strong> Your account can be signed in on one phone at a
            time. If you sign in on another phone, the first phone is signed out without warning.
            You can move to a new phone as often as you like.
          </li>
          <li>
            <strong>Checked online at least every 14 days.</strong> The app works without internet
            for up to 14 days after it last checked your licence. After that it needs to connect
            once before it works again.
          </li>
          <li>
            <strong>Tied to your account.</strong> If your account is deleted, the licence ends
            and cannot be restored.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: 'lifetime',
    title: 'What “lifetime” means',
    body: (
      <>
        <p>
          “Lifetime licence” means the licence has <strong>no end date and no renewal fee</strong>{' '}
          for as long as we operate the {B.productName} service. It does not mean the service will
          run forever, and it is not tied to the life of your phone or your vehicle.
        </p>
        <p>
          The app needs our licence servers. If they stop, the app stops working within 14 days,
          because it can no longer check your licence.
        </p>
        <p>
          If we decide to close the service, we will email you at least{' '}
          <T v={cfg.TERMS.shutdownNoticePeriod} /> before it closes.{' '}
          <T v={cfg.TERMS.discontinuationRemedy} />
        </p>
        <p>
          We do not promise that the app will keep supporting every Android version, phone,
          adapter or vehicle in the future.
        </p>
      </>
    ),
  },
  {
    id: 'price-and-payment',
    title: 'Price, tax and how you buy',
    body: (
      <>
        <p>
          The price is a single payment of{' '}
          <Price>
            {IN.symbol}
            {formatMinor(IN.totalMinor)}
          </Price>{' '}
          ({IN.currency}) if your account country is India, or{' '}
          <Price>
            US{INTL.symbol}
            {formatMinor(INTL.totalMinor)}
          </Price>{' '}
          ({INTL.currency}) for every other country. See our{' '}
          <Link href="/legal/pricing">Pricing page</Link> for how tax applies.
        </p>
        <p>How a purchase works:</p>
        <ol>
          <li>You create an account in the app.</li>
          <li>
            We email you a link to our billing website. The app does not take payments.
          </li>
          <li>
            You pay on the website in Razorpay’s secure payment window. We never see your card,
            UPI or bank details.
          </li>
          <li>
            When Razorpay confirms the payment, your licence is switched on automatically. See the{' '}
            <Link href="/legal/delivery">Delivery Policy</Link>.
          </li>
        </ol>
        <p>
          A price change applies only to new purchases. It never affects a licence you have
          already bought.
        </p>
      </>
    ),
  },
  {
    id: 'refunds',
    title: 'Cancellations and refunds',
    body: (
      <p>
        Refunds are covered by our{' '}
        <Link href="/legal/refund">Cancellation and Refund Policy</Link>. Any refund, full or
        partial, ends the licence it paid for. If we refund a duplicate payment, your one licence
        stays yours: we switch it back on.
      </p>
    ),
  },
  {
    id: 'acceptable-use',
    title: 'What you must not do',
    body: (
      <ul>
        <li>Share your account or licence, or let other people use it.</li>
        <li>Resell, rent or sublicense the app or licence.</li>
        <li>
          Copy, modify, decompile or reverse-engineer the app, or try to get around, disable or
          fake the licence check, except where the law expressly allows it.
        </li>
        <li>Interfere with our servers or try to access other customers’ data.</li>
        <li>
          Use the app to hide a fault from a buyer, inspector, insurer or mechanic, or to
          tamper with safety or emissions systems.
        </li>
        <li>Use the app in a way that breaks the law or road-safety rules.</li>
      </ul>
    ),
  },
  {
    id: 'diagnostics',
    title: 'Diagnostics and safety',
    body: (
      <>
        <p>
          The safety box at the top of these terms is part of this section. In addition:
        </p>
        <ul>
          <li>
            The app reads what your vehicle’s control units report. Readings can be incomplete,
            delayed or wrong if a sensor, control unit, wiring or adapter is faulty.
          </li>
          <li>
            Fault-code descriptions are general reference text. They may not match your exact model
            and may be incomplete. A code tells you where to look, not what to replace.
          </li>
          <li>
            Performance figures (such as 0–100 times or power estimates) are estimates from
            sensor data, not certified measurements.
          </li>
          <li>
            You are responsible for any work you carry out on a vehicle and for deciding whether it
            is safe to use.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: 'adapters-vehicles',
    title: 'Adapters and vehicles',
    body: (
      <>
        <p>
          The app needs an ELM327-compatible OBD adapter, which you buy separately from someone
          else. Adapters vary a lot in quality. Many low-cost adapters cannot read some systems,
          such as ABS, and some do not work at all. We do not make, sell or guarantee any adapter.
        </p>
        <p>
          Which data the app can read depends on your vehicle’s make, model, year and control
          units. We do not guarantee that every feature will work with every vehicle.
        </p>
      </>
    ),
  },
  {
    id: 'brands',
    title: 'Vehicle and equipment brands',
    body: (
      <p>
        {B.productName} is an independent product. It is not made, endorsed or sponsored by any
        vehicle or equipment maker. We use manufacturer and adapter names (such as Honda, Royal
        Enfield or Bosch) only to say which vehicles or equipment the app works with. Those names
        belong to their owners.
      </p>
    ),
  },
  {
    id: 'availability',
    title: 'Availability and updates',
    body: (
      <>
        <p>
          We try to keep the online parts of the service (login, licence checks and the billing
          website) available, but they may sometimes be unavailable, for example during maintenance
          or a provider outage. The 14-day offline period is designed to cover short outages.
        </p>
        <p>
          We may update the app to fix faults, add or change features, or keep it secure. We may
          remove a feature if a vehicle maker, adapter, Android or the law makes it unworkable. We
          will not remove the core diagnostic features you paid for without telling you.
        </p>
        <p>
          During a technical problem we may temporarily let the app work for everyone. That does
          not give anyone a licence they have not bought.
        </p>
      </>
    ),
  },
  {
    id: 'suspension',
    title: 'Suspending or ending a licence',
    body: (
      <>
        <p>We may suspend or end a licence if:</p>
        <ul>
          <li>it was bought with a stolen or fraudulent payment;</li>
          <li>the payment is refunded, reversed or charged back through your bank;</li>
          <li>you break section 8 (for example by sharing or bypassing the licence).</li>
        </ul>
        <p>
          Where practical, we will email you first, tell you why, and give you a chance to respond.
          If we end a licence and it turns out you were not at fault, we will restore it or refund
          what you paid.
        </p>
        <p>
          You can stop using the app at any time and ask us to{' '}
          <Link href="/legal/delete-account">delete your account</Link>.
        </p>
      </>
    ),
  },
  {
    id: 'ip',
    title: 'Ownership',
    body: (
      <p>
        We (or our licensors) own the app, its content and the {B.productName} name. Apart from the
        licence in section 4, these terms give you no rights in them.
      </p>
    ),
  },
  {
    id: 'liability',
    title: 'Our responsibility to you',
    body: (
      <>
        <p>
          Nothing in these terms limits or excludes any liability that the law does not allow us
          to limit or exclude, or any right you have as a consumer under applicable law.
        </p>
        <p>Subject to that:</p>
        <ul>
          <li>
            We are responsible for loss you suffer that was a foreseeable result of our breaking
            these terms or of our failing to use reasonable care.
          </li>
          <li>
            We are not responsible for loss caused by relying on a reading without the checks in
            the safety box, by a faulty adapter or vehicle, or by using the app while riding or
            driving.
          </li>
          <li>
            Our total responsibility to you under these terms is limited to the amount you paid for
            your licence.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: 'law',
    title: 'Governing law and complaints',
    body: (
      <>
        <p>
          These terms are governed by the laws of India. If you have a problem, please contact us
          first (see <Link href="/legal/contact">Contact Us</Link>); most problems are solved that
          way.
        </p>
        <p>
          The courts at <T v={cfg.TERMS.courtCity} /> can hear disputes about these terms. This
          does not stop you from going to a consumer commission, or any other court or body, where
          the law allows you to. You are not required to go to arbitration.
        </p>
        <p>
          If you live outside India, you also keep any rights that the consumer law of your country
          gives you and that cannot be excluded.
        </p>
      </>
    ),
  },
  {
    id: 'changes',
    title: 'Changes to these terms',
    body: (
      <p>
        We may change these terms, for example when the law or the app changes. We will update the
        version and date at the top. If a change is significant, we will email you before it takes
        effect. A change never reduces what you already paid for in a way that the law does not
        allow.
      </p>
    ),
  },
  {
    id: 'general',
    title: 'General',
    body: (
      <ul>
        <li>
          <strong>Notices.</strong> We will send notices to the email address on your account. You
          can send notices to <Email v={K.supportEmail} /> or by post to <T v={B.legalName} />,{' '}
          <T v={B.registeredAddress} />.
        </li>
        <li>
          <strong>Whole agreement.</strong> These terms and the policies they link to are the whole
          agreement between us about the app and the licence.
        </li>
        <li>
          <strong>If part is invalid.</strong> If a court finds part of these terms invalid, the
          rest still applies.
        </li>
        <li>
          <strong>Transfer.</strong> You cannot transfer your rights under these terms. We may
          transfer ours to a business that takes over the service, and will tell you if we do;
          your rights will not be reduced as a result.
        </li>
        <li>
          <strong>Events outside our control.</strong> We are not responsible for delays or
          failures caused by events we cannot reasonably control, such as a major provider or
          network outage. This does not affect your refund rights.
        </li>
      </ul>
    ),
  },
  {
    id: 'contact',
    title: 'Contact',
    body: (
      <p>
        Email <Email v={K.supportEmail} />. All the ways to reach us, including our grievance
        officer, are on our <Link href="/legal/contact">Contact page</Link>.
      </p>
    ),
  },
];

export default function Terms() {
  return (
    <LegalDoc
      title="Terms and Conditions"
      intro={
        <>
          The agreement for the {B.productName} app and its licence. The safety points and the
          short version come first; the full terms follow. The app calls this page “Terms of
          Service”; it is the same document.
        </>
      }
      summary={summary}
      afterSummary={safety}
      sections={sections}
    />
  );
}
