// ══════════════════════════════════════════════════════════════════════════
// /activate — the single entry point to the billing portal.
//
// Two modes:
//   ?t=<token>  the customer clicked the link in their email. Forwarded to
//               /api/activate, which redeems the token, sets the session
//               cookie, and redirects to /account or /checkout depending on
//               what the EXISTING /entitlement function says.
//   no token    the "I didn't get the email" form.
//
// Cookies cannot be written from a Server Component, so the redemption itself
// lives in the route handler — see app/api/activate/route.ts.
// ══════════════════════════════════════════════════════════════════════════

import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { NOINDEX } from '@/lib/seo';
import { C, cardStyle, pageStyle, legalLinkStyle } from '@/lib/theme';
import RequestForm from './request-form';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Activate your licence — Danlite ELM',
  robots: NOINDEX,
};

export default async function ActivatePage({
  searchParams,
}: {
  // In Next.js 16 searchParams is a Promise and must be awaited.
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
}) {
  const params = await searchParams;

  const token = typeof params.t === 'string' ? params.t : null;
  if (token) {
    // Hand off to the route handler, which can set cookies. The redirect it
    // performs also strips the single-use token out of the address bar.
    redirect(`/api/activate?t=${encodeURIComponent(token)}`);
  }

  const failed = params.e === '1';
  const functionsBase = process.env.NEXT_PUBLIC_SUPABASE_URL ?? null;

  return (
    <main style={pageStyle}>
      <div style={{ maxWidth: 440, margin: '0 auto' }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, margin: '0 0 6px' }}>Danlite ELM</h1>
        <p style={{ color: C.muted, fontSize: 13, margin: '0 0 26px' }}>
          Licence activation
        </p>

        <div style={cardStyle}>
          {failed && (
            // Deliberately non-specific. The server does not tell us whether
            // the token expired, was already used, or never existed, and
            // neither do we.
            <p
              style={{
                margin: '0 0 20px',
                padding: '12px 14px',
                borderRadius: 8,
                border: `1px solid ${C.amber}`,
                color: C.amber,
                fontSize: 13,
                lineHeight: 1.6,
              }}
            >
              This link is invalid or has expired. Activation links last 15 minutes and can
              only be used once. Request a new one below.
            </p>
          )}

          <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 6px' }}>
            {failed ? 'Request a new link' : 'Get your activation link'}
          </h2>
          <p style={{ color: C.muted, fontSize: 13, lineHeight: 1.6, margin: '0 0 20px' }}>
            Enter the email address or mobile number you used to sign up in the app. We will
            send you a secure link to complete your purchase.
          </p>

          <RequestForm functionsBase={functionsBase} />
        </div>

        <footer style={{ marginTop: 22, display: 'flex', gap: 16, justifyContent: 'center' }}>
          <Link href="/legal/privacy" style={legalLinkStyle}>
            Privacy
          </Link>
          <Link href="/legal/terms" style={legalLinkStyle}>
            Terms
          </Link>
          <Link href="/legal/refund" style={legalLinkStyle}>
            Refunds
          </Link>
        </footer>
      </div>
    </main>
  );
}
