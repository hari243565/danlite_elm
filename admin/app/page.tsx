// ══════════════════════════════════════════════════════════════════════════
// / — Overview. Aggregate numbers, recent signups, recent payments.
//
// Every figure here comes from admin-overview, which re-checked the caller's
// email against public.admin_users before answering. This page holds no
// service-role key and cannot read a table directly.
// ══════════════════════════════════════════════════════════════════════════

import Link from 'next/link';
import { callAdminFn, getAdminSession, type Overview } from '@/lib/admin-api';
import { C, money, MONO, when } from '@/lib/theme';
import { ErrorCard, Section, Shell, StatusPill, Table, tdStyle } from './shell';

// An admin dashboard must never be prerendered or cached — every load reads
// live money and live customer counts.
export const dynamic = 'force-dynamic';

function Stat({
  label,
  value,
  hint,
  accent,
}: {
  label: string;
  value: string;
  hint?: string;
  accent?: string;
}) {
  return (
    <div
      style={{
        backgroundColor: C.surface,
        border: `1px solid ${C.border}`,
        borderRadius: 12,
        padding: '16px 18px',
        minWidth: 0,
      }}
    >
      <div
        style={{
          color: C.muted,
          fontSize: 10.5,
          fontWeight: 700,
          letterSpacing: 0.6,
          textTransform: 'uppercase',
          marginBottom: 7,
        }}
      >
        {label}
      </div>
      <div
        style={{
          fontSize: 25,
          fontWeight: 800,
          color: accent ?? C.text,
          fontFamily: MONO,
          lineHeight: 1.1,
        }}
      >
        {value}
      </div>
      {hint ? (
        <div style={{ color: C.muted, fontSize: 11, marginTop: 6 }}>{hint}</div>
      ) : null}
    </div>
  );
}

export default async function OverviewPage() {
  const session = await getAdminSession();
  if (!session) return null; // proxy.ts redirects to /login before this renders

  const result = await callAdminFn<Overview>('admin-overview');

  if (!result.ok) {
    return (
      <Shell email={session.email} active="/">
        <ErrorCard status={result.status} message={result.error} />
      </Shell>
    );
  }

  const { totals, razorpay, recent_signups, recent_payments, generated_at } = result.data;

  return (
    <Shell email={session.email} active="/">
      {/* ── THE BANNER ────────────────────────────────────────────────────
          The single most important thing on this page: is the system taking
          real money? Same treatment as the Mission Control dashboard has
          used since Phase 5 — amber for test, red for live. Renders a
          boolean only; RAZORPAY_KEY_ID never leaves the Edge Function. */}
      <div
        style={{
          border: `2px solid ${razorpay.isTest ? C.amber : C.red}`,
          borderRadius: 10,
          padding: '14px 17px',
          marginBottom: 22,
          backgroundColor: `${razorpay.isTest ? C.amber : C.red}14`,
        }}
      >
        <div
          style={{
            color: razorpay.isTest ? C.amber : C.red,
            fontSize: 15,
            fontWeight: 800,
            letterSpacing: 0.4,
            marginBottom: 6,
          }}
        >
          {razorpay.isTest
            ? 'TEST MODE — not accepting real payments'
            : 'LIVE MODE — REAL PAYMENTS ARE BEING ACCEPTED'}
        </div>
        <p style={{ color: C.muted, fontSize: 11.5, lineHeight: 1.6, margin: 0 }}>
          Derived server-side from whether RAZORPAY_KEY_ID begins with{' '}
          <code style={{ color: C.text }}>rzp_test_</code> ({razorpay.source}). Only this
          boolean crosses the wire; the key itself never reaches this page. An unset key
          reads as LIVE deliberately — believing you are in test mode when you are not is
          the failure that costs money.
        </p>
      </div>

      <Section title="Totals" subtitle={`Live as of ${when(generated_at)} IST.`}>
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(178px, 1fr))',
            gap: 12,
          }}
        >
          <Stat label="Users" value={String(totals.users)} hint="excludes soft-deleted" />
          <Stat
            label="Active licences"
            value={String(totals.licences_active)}
            hint={`${totals.licences_total} licence rows in total`}
            accent={C.green}
          />
          <Stat
            label="Captured payments"
            value={money(totals.captured_minor_inr)}
            hint={`${totals.captured_payments_count} captured payment${
              totals.captured_payments_count === 1 ? '' : 's'
            }`}
            accent={C.cyan}
          />
          <Stat label="Devices" value={String(totals.devices)} hint="registered across all users" />
        </div>

        {totals.captured_minor_non_inr > 0 ? (
          <p style={{ color: C.amber, fontSize: 11.5, marginTop: 10, lineHeight: 1.6 }}>
            Note: {totals.captured_minor_non_inr} minor units of non-INR captured payments
            exist and are deliberately excluded from the rupee total above rather than
            added to it.
          </p>
        ) : null}
      </Section>

      <Section title="Recent signups" subtitle="Last 10 accounts created.">
        <Table
          headers={['Email', 'Phone', 'Country', 'Platform', 'Signed up']}
          isEmpty={recent_signups.length === 0}
          empty="No signups yet."
        >
          {recent_signups.map((u) => (
            <tr key={u.id}>
              <td style={tdStyle}>
                <Link href={`/users/${u.id}`} style={{ color: C.cyan, textDecoration: 'none' }}>
                  {u.email ?? '—'}
                </Link>
              </td>
              <td style={{ ...tdStyle, fontFamily: MONO, color: C.muted }}>{u.phone ?? '—'}</td>
              <td style={tdStyle}>{u.country_code ?? '—'}</td>
              <td style={{ ...tdStyle, color: C.muted }}>{u.signup_platform ?? '—'}</td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(u.created_at)}
              </td>
            </tr>
          ))}
        </Table>
      </Section>

      <Section title="Recent payments" subtitle="Last 10 payment rows, newest first.">
        <Table
          headers={['Invoice', 'Amount', 'Status', 'Gateway ref', 'When']}
          isEmpty={recent_payments.length === 0}
          empty="No payments yet."
        >
          {recent_payments.map((p) => (
            <tr key={p.id}>
              <td style={{ ...tdStyle, fontFamily: MONO }}>{p.gst_invoice_no ?? '—'}</td>
              <td style={{ ...tdStyle, fontFamily: MONO, fontWeight: 700 }}>
                {money(p.amount_minor, p.currency ?? 'INR')}
              </td>
              <td style={tdStyle}>
                <StatusPill status={p.status} />
              </td>
              <td style={{ ...tdStyle, fontFamily: MONO, color: C.muted, fontSize: 11.5 }}>
                {p.gateway_payment_id ?? p.gateway_order_id ?? '—'}
              </td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(p.created_at)}
              </td>
            </tr>
          ))}
        </Table>
      </Section>
    </Shell>
  );
}
