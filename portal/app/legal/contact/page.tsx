// Contact Us. Every factual sentence here is traced in
// docs/legal/CLAIM_LEDGER.md (rows C-nn). All business details come from
// lib/legal-config.ts.

import type { Metadata } from 'next';
import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import { Email, INDEXABLE, LegalDoc, T, Table, Tel, type Section } from '../_components/legal';

export const metadata: Metadata = {
  title: 'Contact Us — Danlite ELM',
  description:
    'How to contact Danlite ELM for support, refunds, privacy requests and complaints, including our grievance officer.',
  robots: INDEXABLE,
};

const B = cfg.BUSINESS;
const K = cfg.CONTACT;

const summary = (
  <ul>
    <li>
      Support and refunds: <Email v={K.supportEmail} />, phone <Tel v={K.supportPhone} />
    </li>
    <li>
      Privacy requests and account deletion: <Email v={K.privacyEmail} />
    </li>
    <li>
      Complaints: our grievance officer, <T v={K.grievanceOfficerName} />
    </li>
    <li>
      We acknowledge complaints within <T v={K.grievanceAckTime} /> and aim to resolve them within{' '}
      <T v={K.grievanceResolutionTime} />.
    </li>
  </ul>
);

const sections: Section[] = [
  {
    id: 'business',
    title: 'Who we are',
    body: (
      <Table
        rows={[
          ['Legal name', <T key="n" v={B.legalName} />],
          ['Type of business', <T key="t" v={B.entityType} />],
          ['Registered address', <T key="a" v={B.registeredAddress} />],
          ['GSTIN', <T key="g" v={B.gstin} />],
          ['Product', `${B.productName} (Android app shown as “${B.appLabel}”)`],
          ['Website', 'billing.danlite.in'],
        ]}
      />
    ),
  },
  {
    id: 'support',
    title: 'Customer support',
    body: (
      <>
        <Table
            rows={[
            ['Email', <Email key="e" v={K.supportEmail} />],
            ['Phone', <Tel key="p" v={K.supportPhone} />],
            ['Hours', <T key="h" v={K.supportHours} />],
          ]}
        />
        <p>To help us find your account quickly, please include:</p>
        <ul>
          <li>the email address you signed up with (write from it if you can);</li>
          <li>the Account ID from the Account screen in the app, if you can see it;</li>
          <li>for payment questions, the payment reference or invoice number from your receipt.</li>
        </ul>
        <p>
          Never send us your card number, UPI PIN, CVV, bank password or the 6-digit login code. We
          will never ask for them.
        </p>
      </>
    ),
  },
  {
    id: 'grievance',
    title: 'Grievance officer',
    body: (
      <>
        <p>
          If you have a complaint about the product, a purchase, a refund or how we handle your
          personal data, you can contact our grievance officer directly:
        </p>
        <Table
            rows={[
            ['Name', <T key="n" v={K.grievanceOfficerName} />],
            ['Designation', <T key="d" v={K.grievanceOfficerDesignation} />],
            ['Email', <Email key="e" v={K.grievanceOfficerEmail} />],
            ['Phone', <Tel key="p" v={K.grievanceOfficerPhone} />],
            [
              'Post',
              <span key="a">
                <T v={B.legalName} />, <T v={B.registeredAddress} />
              </span>,
            ],
          ]}
        />
      </>
    ),
  },
  {
    id: 'response-times',
    title: 'How quickly we respond',
    body: (
      <>
        <Table
          head={['Type of request', 'What we commit to']}
          rows={[
            [
              'Complaint',
              <span key="c">
                We acknowledge it within <T v={K.grievanceAckTime} /> and aim to resolve it within{' '}
                <T v={K.grievanceResolutionTime} />.
              </span>,
            ],
            [
              'Privacy request (summary of your data, correction, deletion, withdrawal of consent, nomination)',
              <span key="p">
                We reply within <T v={K.privacyResponseTime} />.
              </span>,
            ],
            [
              'Refund request',
              <span key="r">
                We decide within <T v={cfg.REFUND.decisionTime} /> (see the{' '}
                <Link href="/legal/refund#timeline">Refund Policy</Link>).
              </span>,
            ],
          ]}
        />
        <p>
          If you are not satisfied with how we handled a complaint, you can approach a consumer
          commission. For privacy complaints you can also go to the Data Protection Board of India.
        </p>
      </>
    ),
  },
  {
    id: 'privacy-and-deletion',
    title: 'Privacy requests and account deletion',
    body: (
      <p>
        Email <Email v={K.privacyEmail} />. To delete your account, follow the steps on{' '}
        <Link href="/legal/delete-account">Delete your account</Link>. Details of your rights are in
        our <Link href="/legal/privacy#your-rights">Privacy Policy</Link>.
      </p>
    ),
  },
];

export default function ContactPage() {
  return (
    <LegalDoc
      title="Contact Us"
      intro={<>How to reach the business behind {B.productName}, and what to expect when you do.</>}
      summaryTitle="Quick contacts"
      summary={summary}
      sections={sections}
    />
  );
}
