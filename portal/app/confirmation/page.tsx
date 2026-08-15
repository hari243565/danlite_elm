// ══════════════════════════════════════════════════════════════════════════
// /confirmation — shown after a payment attempt.
//
// ── THE RULE THIS PAGE EXISTS TO OBEY ────────────────────────────────────
// This page NEVER fabricates a success state. It renders "Payment received"
// only when it has read a real row out of public.payments with
// status='captured', belonging to the signed-in user, under the Phase 1 RLS
// policy payments_select_own. It does not trust the order_id in the URL, it
// does not trust Razorpay's browser callback, and it has no write path of any
// kind. The order_id query parameter is used ONLY to pick which of the user's
// own payments to show — an attacker who edits it sees, at most, nothing.
//
// Before Phase 5 this page reported "no completed purchase found yet" for
// everybody, which was the truth at the time. Now that the webhook can
// genuinely capture payments, the same read starts returning rows, and the
// only thing added is patience: a webhook may land a second or two after the
// customer's browser gets here, so the page waits visibly instead of
// reporting a false negative to somebody who has just paid.
// ══════════════════════════════════════════════════════════════════════════

import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { NOINDEX } from '@/lib/seo';
import { C, cardStyle, pageStyle, legalLinkStyle, MONO } from '@/lib/theme';
import { createClient } from '@/lib/supabase/server';
import { formatMinor } from '@/lib/gst';
import StatusPoller from './status-poller';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Order confirmation — Danlite ELM',
  robots: NOINDEX,
};

type CapturedPayment = {
  gateway_payment_id: string;
  gateway_order_id: string | null;
  amount_minor: number;
  currency: string;
  status: string;
  created_at: string;
  gst_invoice_no: string | null;
};

/**
 * The single read both the page and its poller use.
 *
 * RLS (payments_select_own) already restricts this to the caller's own rows.
 * The explicit .eq('user_id', …) is a second, independent statement of intent
 * rather than a reliance on the policy alone — the same belt-and-braces the
 * page has used since Phase 4.
 */
async function readCapturedPayment(orderId: string | null): Promise<CapturedPayment | null> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  let q = supabase
    .from('payments')
    .select(
      'gateway_payment_id, gateway_order_id, amount_minor, currency, status, created_at, gst_invoice_no',
    )
    .eq('user_id', user.id)
    .eq('status', 'captured');

  // Scope to the order the customer just paid for when we know it; otherwise
  // fall back to their most recent capture (someone arriving at /confirmation
  // directly, from a bookmark or the app).
  if (orderId) q = q.eq('gateway_order_id', orderId);

  const { data } = await q.order('created_at', { ascending: false }).limit(1).maybeSingle();

  return (data as CapturedPayment | null) ?? null;
}

export default async function ConfirmationPage({
  searchParams,
}: {
  // Next.js 16: searchParams is a Promise and must be awaited.
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/activate');

  const params = await searchParams;
  const raw = params.order_id;
  const orderId = typeof raw === 'string' && raw.length > 0 ? raw : null;

  const payment = await readCapturedPayment(orderId);

  // The poller's read. Returns a boolean and nothing else: no payment detail
  // crosses this boundary, so the client cannot be handed a receipt it might
  // render before the server has confirmed one exists.
  async function checkPurchase(): Promise<{ done: boolean }> {
    'use server';
    return { done: (await readCapturedPayment(orderId)) !== null };
  }

  return (
    <main style={pageStyle}>
      <div style={{ maxWidth: 440, margin: '0 auto' }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, margin: '0 0 6px' }}>Danlite ELM</h1>
        <p style={{ color: C.muted, fontSize: 13, margin: '0 0 26px' }}>Order confirmation</p>

        <div style={cardStyle}>
          {!payment ? (
            <>
              <StatusPoller check={checkPurchase} />

              <p style={{ margin: '18px 0 0' }}>
                <Link
                  href="/checkout"
                  style={{
                    color: C.cyan,
                    fontSize: 13.5,
                    fontWeight: 600,
                    textDecoration: 'none',
                  }}
                >
                  Back to checkout →
                </Link>
              </p>
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
                    v: `${payment.currency} ${formatMinor(payment.amount_minor)}`,
                  },
                  { k: 'Payment reference', v: payment.gateway_payment_id },
                  { k: 'Invoice number', v: payment.gst_invoice_no ?? 'Pending' },
                  {
                    k: 'Date',
                    v: new Date(payment.created_at).toLocaleString('en-IN'),
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
