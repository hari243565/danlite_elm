// Delete your account. The stable public URL to give Google Play as the
// account-deletion web resource: /legal/delete-account. It deliberately
// lives under /legal and not /account/delete, because proxy.ts sends every
// signed-out visitor to /account/* to /activate, and Play requires this page
// to be reachable without signing in.
//
// It describes ONLY today's mechanism (an emailed request, carried out by
// hand). The text is shared with the Privacy Policy through
// ../_components/deletion.tsx. Traced in docs/legal/CLAIM_LEDGER.md (DA-nn).

import type { Metadata } from 'next';
import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import { Email, INDEXABLE, LegalDoc, T, type Section } from '../_components/legal';
import { DeletionDetails, DeletionHowTo } from '../_components/deletion';

export const metadata: Metadata = {
  title: 'Delete your account — Danlite ELM',
  description:
    'How to ask for your Danlite ELM account and its data to be deleted, what is deleted, what is kept and why.',
  robots: INDEXABLE,
};

const B = cfg.BUSINESS;

const summary = (
  <ul>
    <li>
      This page is for the <strong>{B.productName}</strong> app, shown on your phone as “
      {B.appLabel}” and on Google Play as <T v={B.playListingName} /> by{' '}
      <T v={B.playDeveloperName} />.
    </li>
    <li>
      To delete your account, email <Email v={cfg.CONTACT.privacyEmail} /> from the email address
      you sign in with. Subject: “Delete my account”.
    </li>
    <li>
      Deleting your account <strong>permanently ends your licence</strong>. It cannot be restored.
    </li>
    <li>
      If you have paid, we must keep your payment record and receipt details for tax law. Everything
      else linked to your account is deleted.
    </li>
    <li>
      We complete deletion within <T v={cfg.PRIVACY.deletionCompletionTime} /> of confirming your
      request.
    </li>
  </ul>
);

const sections: Section[] = [
  { id: 'how', title: 'How to ask', body: <DeletionHowTo /> },
  { id: 'what-happens', title: 'What deletion does', body: <DeletionDetails /> },
  {
    id: 'more',
    title: 'More information',
    body: (
      <p>
        Our <Link href="/legal/privacy">Privacy Policy</Link> explains all the data we hold and
        your other rights. If you have a complaint about how we handled your request, see our{' '}
        <Link href="/legal/contact#grievance">grievance officer</Link>.
      </p>
    ),
  },
];

export default function DeleteAccountPage() {
  return (
    <LegalDoc
      title="Delete your account"
      intro={
        <>
          How to have your {B.productName} account and the data linked to it deleted. You do not
          need the app or a login to use this page.
        </>
      }
      summary={summary}
      sections={sections}
    />
  );
}
