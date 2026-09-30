// /legal — an index of every policy, so a reviewer (Razorpay, Google Play) or
// a customer can find them all from one address.

import type { Metadata } from 'next';
import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import { INDEXABLE, LEGAL_PAGES, T, legalStyles as s } from './_components/legal';

export const metadata: Metadata = {
  title: 'Policies — Danlite ELM',
  description: 'Terms, privacy, refunds, delivery, pricing, contact and account deletion for Danlite ELM.',
  robots: INDEXABLE,
};

export default function LegalIndex() {
  return (
    <article className={s.doc}>
      <h1 className={s.h1}>{cfg.BUSINESS.productName} policies</h1>
      <p className={s.meta}>
        Version {cfg.LEGAL_VERSION} · Last updated <T v={cfg.LAST_UPDATED} />
      </p>
      <p>
        {cfg.BUSINESS.productName} is sold by <T v={cfg.BUSINESS.legalName} />. These documents
        apply to the Android app and to billing.danlite.in.
      </p>
      <ul>
        {LEGAL_PAGES.filter((p) => p.href !== '/legal').map((p) => (
          <li key={p.href}>
            <Link href={p.href}>{p.label}</Link>
          </li>
        ))}
      </ul>
    </article>
  );
}
