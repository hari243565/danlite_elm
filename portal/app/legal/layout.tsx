// Shared shell for the three legal pages.
//
// The DRAFT banner lives here rather than in each page so that all three
// carry an identical, unmissable warning and none can quietly lose it during
// an edit. These documents are starting points for a real legal review, not
// legal advice and not approved copy.

import Link from 'next/link';
import { C, pageStyle, legalLinkStyle } from '@/lib/theme';

export default function LegalLayout({ children }: { children: React.ReactNode }) {
  return (
    <main style={pageStyle}>
      <div style={{ maxWidth: 680, margin: '0 auto' }}>
        <div
          style={{
            border: `2px solid ${C.amber}`,
            backgroundColor: 'rgba(255,138,0,0.08)',
            borderRadius: 10,
            padding: '14px 18px',
            marginBottom: 28,
          }}
        >
          <p
            style={{
              margin: 0,
              color: C.amber,
              fontSize: 14,
              fontWeight: 700,
              lineHeight: 1.5,
              letterSpacing: 0.2,
            }}
          >
            DRAFT — for client and legal review. Not yet approved for publication.
          </p>
          <p style={{ margin: '8px 0 0', color: C.amber, fontSize: 12.5, lineHeight: 1.6 }}>
            This text was drafted as a starting point for a qualified reviewer. It is not legal
            advice, it has not been checked by a lawyer, and it must not be published as-is.
            Anything marked <strong>[CONFIRM]</strong> is an assumption that needs a decision.
          </p>
        </div>

        {children}

        <footer
          style={{
            marginTop: 36,
            paddingTop: 18,
            borderTop: `1px solid ${C.border}`,
            display: 'flex',
            gap: 16,
            justifyContent: 'center',
          }}
        >
          <Link href="/legal/privacy" style={legalLinkStyle}>
            Privacy
          </Link>
          <Link href="/legal/terms" style={legalLinkStyle}>
            Terms
          </Link>
          <Link href="/legal/refund" style={legalLinkStyle}>
            Refunds
          </Link>
          <Link href="/account" style={legalLinkStyle}>
            Account
          </Link>
        </footer>
      </div>
    </main>
  );
}
