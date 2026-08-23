// ══════════════════════════════════════════════════════════════════════════
// /payments — payment history across every customer.
//
// NO REFUND BUTTON, BY DESIGN. Refunds are issued in Razorpay's own
// dashboard. This page displays refund state that already exists in the
// `payments` table — written there by razorpay-webhook, which this phase
// does not touch — and offers no way to start one.
// ══════════════════════════════════════════════════════════════════════════

import Link from 'next/link';
import type { Metadata } from 'next';
import { callAdminFn, getAdminSession, type PaymentList } from '@/lib/admin-api';
import { C, FONT, inputStyle, money, MONO, when } from '@/lib/theme';
import { NOINDEX } from '@/lib/seo';
import { ErrorCard, Section, Shell, StatusPill, Table, tdStyle } from '../shell';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Payments — Danlite ELM Admin',
  robots: NOINDEX,
};

const STATUSES = [
  '',
  'created',
  'authorized',
  'captured',
  'failed',
  'refunded',
  'partially_refunded',
];

export default async function PaymentsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const session = await getAdminSession();
  if (!session) return null;

  const sp = await searchParams;
  const search = typeof sp.q === 'string' ? sp.q : '';
  const status = typeof sp.status === 'string' ? sp.status : '';
  const page = Math.max(0, Number(typeof sp.page === 'string' ? sp.page : 0) || 0);

  const result = await callAdminFn<PaymentList>('admin-list-payments', {
    search,
    status: status || undefined,
    page,
  });

  if (!result.ok) {
    return (
      <Shell email={session.email} active="/payments">
        <ErrorCard status={result.status} message={result.error} />
      </Shell>
    );
  }

  const { payments, total, has_more, page_size } = result.data;
  const from = total === 0 ? 0 : page * page_size + 1;
  const to = page * page_size + payments.length;

  const pageHref = (p: number) => {
    const qs = new URLSearchParams();
    if (search) qs.set('q', search);
    if (status) qs.set('status', status);
    if (p > 0) qs.set('page', String(p));
    const s = qs.toString();
    return s ? `/payments?${s}` : '/payments';
  };

  return (
    <Shell email={session.email} active="/payments">
      <Section
        title="Payments"
        subtitle={
          total === 0
            ? 'No matching payments.'
            : `Showing ${from}–${to} of ${total} payment${total === 1 ? '' : 's'}.`
        }
      >
        <form
          method="get"
          style={{ display: 'flex', gap: 9, marginBottom: 14, flexWrap: 'wrap' }}
        >
          <input
            type="search"
            name="q"
            defaultValue={search}
            placeholder="Invoice no, payment id, order id, or payer email…"
            style={{ ...inputStyle, flex: '1 1 300px', width: 'auto', fontSize: 13.5 }}
          />
          <select
            name="status"
            defaultValue={status}
            style={{
              ...inputStyle,
              width: 'auto',
              flex: '0 0 auto',
              fontSize: 13.5,
              cursor: 'pointer',
            }}
          >
            {STATUSES.map((s) => (
              <option key={s || 'any'} value={s}>
                {s === '' ? 'Any status' : s}
              </option>
            ))}
          </select>
          <button
            type="submit"
            style={{
              padding: '12px 20px',
              borderRadius: 8,
              border: 'none',
              backgroundColor: C.cyan,
              color: C.bg,
              fontWeight: 700,
              fontSize: 13.5,
              fontFamily: FONT,
              cursor: 'pointer',
            }}
          >
            Search
          </button>
          {search || status ? (
            <Link
              href="/payments"
              style={{
                padding: '12px 16px',
                borderRadius: 8,
                border: `1px solid ${C.border}`,
                color: C.muted,
                fontSize: 13.5,
                textDecoration: 'none',
              }}
            >
              Clear
            </Link>
          ) : null}
        </form>

        <Table
          headers={['Invoice', 'Payer', 'Amount', 'Status', 'Payment ID', 'Order ID', 'When']}
          isEmpty={payments.length === 0}
          empty={search || status ? 'No payments match that search.' : 'No payments recorded yet.'}
        >
          {payments.map((p) => (
            <tr key={p.id}>
              <td style={{ ...tdStyle, fontFamily: MONO, fontWeight: 600 }}>
                {p.gst_invoice_no ?? '—'}
              </td>
              <td style={tdStyle}>
                {p.user_id ? (
                  <Link href={`/users/${p.user_id}`} style={{ color: C.cyan, textDecoration: 'none' }}>
                    {p.email ?? p.user_id}
                  </Link>
                ) : (
                  '—'
                )}
              </td>
              <td style={{ ...tdStyle, fontFamily: MONO, fontWeight: 700, whiteSpace: 'nowrap' }}>
                {money(p.amount_minor, p.currency ?? 'INR')}
              </td>
              <td style={tdStyle}>
                <StatusPill status={p.status} />
              </td>
              <td style={{ ...tdStyle, fontFamily: MONO, color: C.muted, fontSize: 11.5 }}>
                {p.gateway_payment_id ?? '—'}
              </td>
              <td style={{ ...tdStyle, fontFamily: MONO, color: C.muted, fontSize: 11.5 }}>
                {p.gateway_order_id ?? '—'}
              </td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(p.created_at)}
              </td>
            </tr>
          ))}
        </Table>

        {(page > 0 || has_more) && (
          <div style={{ display: 'flex', gap: 9, marginTop: 14, alignItems: 'center' }}>
            {page > 0 ? (
              <Link
                href={pageHref(page - 1)}
                style={{
                  padding: '8px 14px',
                  borderRadius: 8,
                  border: `1px solid ${C.border}`,
                  color: C.text,
                  fontSize: 12.5,
                  textDecoration: 'none',
                }}
              >
                ← Previous
              </Link>
            ) : null}
            {has_more ? (
              <Link
                href={pageHref(page + 1)}
                style={{
                  padding: '8px 14px',
                  borderRadius: 8,
                  border: `1px solid ${C.border}`,
                  color: C.text,
                  fontSize: 12.5,
                  textDecoration: 'none',
                }}
              >
                Next →
              </Link>
            ) : null}
            <span style={{ color: C.muted, fontSize: 12 }}>Page {page + 1}</span>
          </div>
        )}
      </Section>
    </Shell>
  );
}
