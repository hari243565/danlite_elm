// ══════════════════════════════════════════════════════════════════════════
// /confirmation — shown after a successful payment.
//
// ── READ THIS BEFORE FILING A BUG ────────────────────────────────────────
// Right now this page shows "No completed purchase found yet" for EVERY user,
// including you. That is correct. Razorpay is not wired up until Phase 5/6, so
// no row in public.payments can possibly have status='captured'. The page is
// reporting the true state of the database.
//
// The conditional logic below is real and finished. It was NOT stubbed out
// with sample data to make the page look complete in a screenshot — a
// confirmation page that shows a fake purchase is the single most dangerous
// page in a billing system to fake, because "it worked when we tested it" is
// exactly what you would say afterwards.
//
// When Phase 5/6 lands and a captured payment exists, this page will start
// showing it with no change to this file.
// ══════════════════════════════════════════════════════════════════════════

import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { NOINDEX } from '@/lib/seo';
import { C, cardStyle, pageStyle, legalLinkStyle, MONO } from '@/lib/theme';
import { createClient } from '@/lib/supabase/server';
import { formatMinor } from '@/lib/gst';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Order confirmation — Danlite ELM',
  robots: NOINDEX,
};

export default async function ConfirmationPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect('/activate');

  // RLS (payments_select_own) already restricts this to the caller's own rows;
  // the explicit user_id filter is a second, independent statement of intent
  // rather than a reliance on the policy alone.
  const { data: payment } = await supabase
    .from('payments')
    .select('gateway_payment_id, amount_minor, currency, status, created_at, gst_invoice_no')
    .eq('user_id', user.id)
    .eq('status', 'captured')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  return (
    <main style={pageStyle}>
      <div style={{ maxWidth: 440, margin: '0 auto' }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, margin: '0 0 6px' }}>Danlite ELM</h1>
        <p style={{ color: C.muted, fontSize: 13, margin: '0 0 26px' }}>Order confirmation</p>

        <div style={cardStyle}>
          {!payment ? (
            <>
              <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 6px', color: C.amber }}>
                No completed purchase found yet
              </h2>
              <p style={{ color: C.muted, fontSize: 13, lineHeight: 1.6, margin: '0 0 20px' }}>
                We could not find a completed payment on your account. If you have just paid,
                give it a moment and refresh — confirmations can take a few seconds to arrive
                from the payment provider.
              </p>
              <Link
                href="/checkout"
                style={{
                  color: C.cyan,
                  fontSize: 13.5,
                  fontWeight: 600,
                  textDecoration: 'none',
                }}
              >
                Go to checkout →
              </Link>
            </>
          ) : (
            <>
              <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 6px', color: C.green }}>
                Payment received
              </h2>
              <p style={{ color: C.muted, fontSize: 13, lineHeight: 1.6, margin: '0 0 20px' }}>
                Your lifetime licence is active. Open the Danlite ELM app and sign in with the
                same account — the full version unlocks automatically.
              </p>

              <div
                style={{
                  border: `1px solid ${C.border}`,
                  backgroundColor: C.card,
                  borderRadius: 8,
                  padding: '4px 14px',
                }}
              >
                {[
                  {
                    k: 'Amount',
                    v: `${payment.currency} ${formatMinor(payment.amount_minor as number)}`,
                  },
                  { k: 'Payment reference', v: payment.gateway_payment_id as string },
                  { k: 'Invoice number', v: (payment.gst_invoice_no as string) ?? 'Pending' },
                  {
                    k: 'Date',
                    v: new Date(payment.created_at as string).toLocaleString('en-IN'),
                  },
                ].map((row, i) => (
                  <div
                    key={row.k}
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      gap: 16,
                      padding: '11px 0',
                      borderTop: i === 0 ? 'none' : `1px solid ${C.border}`,
                      fontSize: 13,
                    }}
                  >
                    <span style={{ color: C.muted }}>{row.k}</span>
                    <span
                      style={{
                        color: C.text,
                        fontFamily: MONO,
                        fontSize: 12.5,
                        textAlign: 'right',
                        wordBreak: 'break-all',
                      }}
                    >
                      {row.v}
                    </span>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>

        <p style={{ textAlign: 'center', marginTop: 20 }}>
          <Link href="/account" style={{ color: C.cyan, fontSize: 13, textDecoration: 'none' }}>
            View your account
          </Link>
        </p>

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
