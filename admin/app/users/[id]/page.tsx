// ══════════════════════════════════════════════════════════════════════════
// /users/[id] — everything the system knows about one customer.
//
// DISPLAY ONLY. There is deliberately not a single button on this page that
// changes anything: no grant licence, no revoke, no force sign-out, no
// refund. Those are a separate later phase.
//
// That is not laziness, it is sequencing. A read that goes wrong shows the
// wrong data; a write that goes wrong takes away something a customer paid
// for. The two deserve separate design, separate review and separate audit
// logging — and audit_log is read-only this phase.
//
// NOTE ON params: a Promise in the installed Next.js 16.3.0, same as
// searchParams. Awaited below.
// ══════════════════════════════════════════════════════════════════════════

import Link from 'next/link';
import type { Metadata } from 'next';
import { callAdminFn, getAdminSession, type UserDetail } from '@/lib/admin-api';
import { C, money, MONO, when } from '@/lib/theme';
import { NOINDEX } from '@/lib/seo';
import { ErrorCard, Section, Shell, StatusPill, Table, tdStyle } from '../../shell';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'User detail — Danlite ELM Admin',
  robots: NOINDEX,
};

function Field({ label, value, mono }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <div style={{ minWidth: 0 }}>
      <div
        style={{
          color: C.muted,
          fontSize: 10.5,
          fontWeight: 700,
          letterSpacing: 0.5,
          textTransform: 'uppercase',
          marginBottom: 5,
        }}
      >
        {label}
      </div>
      <div
        style={{
          fontSize: 13,
          fontFamily: mono ? MONO : undefined,
          wordBreak: 'break-all',
          color: C.text,
        }}
      >
        {value}
      </div>
    </div>
  );
}

export default async function UserDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const session = await getAdminSession();
  if (!session) return null;

  const { id } = await params;
  const result = await callAdminFn<UserDetail>('admin-user-detail', { user_id: id });

  if (!result.ok) {
    return (
      <Shell email={session.email} active="/users">
        <Link
          href="/users"
          style={{ color: C.muted, fontSize: 12.5, textDecoration: 'none', display: 'inline-block', marginBottom: 14 }}
        >
          ← Back to users
        </Link>
        <ErrorCard status={result.status} message={result.error} />
      </Shell>
    );
  }

  const { profile, licence, payments, orders, devices, sessions, summary } = result.data;

  return (
    <Shell email={session.email} active="/users">
      <Link
        href="/users"
        style={{ color: C.muted, fontSize: 12.5, textDecoration: 'none', display: 'inline-block', marginBottom: 14 }}
      >
        ← Back to users
      </Link>

      <div
        style={{
          display: 'flex',
          alignItems: 'baseline',
          gap: 12,
          flexWrap: 'wrap',
          marginBottom: 4,
        }}
      >
        <h1 style={{ fontSize: 19, fontWeight: 800, margin: 0 }}>{profile.email ?? '(no email)'}</h1>
        <StatusPill status={licence?.status} />
        {profile.deleted_at ? (
          <span style={{ color: C.red, fontSize: 11.5, fontWeight: 700 }}>
            SOFT-DELETED {when(profile.deleted_at)}
          </span>
        ) : null}
      </div>
      <p style={{ color: C.muted, fontSize: 12, margin: '0 0 22px' }}>
        Read-only view. This phase ships no actions — licence changes and forced sign-outs
        are a later phase, and refunds stay in Razorpay&apos;s own dashboard.
      </p>

      <Section title="Profile">
        <div
          style={{
            backgroundColor: C.surface,
            border: `1px solid ${C.border}`,
            borderRadius: 12,
            padding: 18,
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))',
            gap: 18,
          }}
        >
          <Field label="User ID" value={profile.id} mono />
          <Field label="Email" value={profile.email ?? '—'} />
          <Field label="Phone" value={profile.phone ?? '—'} mono />
          <Field label="Country" value={profile.country_code ?? '—'} />
          <Field label="Signup platform" value={profile.signup_platform ?? '—'} />
          <Field label="Signed up" value={when(profile.created_at)} />
          <Field label="Captured total" value={money(summary.captured_minor)} mono />
          <Field
            label="Refunded total"
            value={
              <span style={{ color: summary.refunded_minor > 0 ? C.red : C.text }}>
                {money(summary.refunded_minor)}
              </span>
            }
            mono
          />
        </div>
      </Section>

      <Section title="Licence">
        {licence ? (
          <div
            style={{
              backgroundColor: C.surface,
              border: `1px solid ${C.border}`,
              borderRadius: 12,
              padding: 18,
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))',
              gap: 18,
            }}
          >
            <Field label="Status" value={<StatusPill status={licence.status} />} />
            <Field label="Product" value={licence.product_code ?? '—'} mono />
            <Field label="Purchase rail" value={licence.purchase_rail ?? '—'} />
            <Field label="Purchased" value={when(licence.purchased_at)} />
            <Field label="Active device" value={licence.active_device_id ?? '—'} mono />
            <Field label="Active session" value={licence.active_session_id ?? '—'} mono />
            <Field label="Revoked at" value={when(licence.revoked_at)} />
            <Field label="Revoke reason" value={licence.revoke_reason ?? '—'} />
          </div>
        ) : (
          <div
            style={{
              border: `1px solid ${C.border}`,
              borderRadius: 12,
              padding: 22,
              color: C.muted,
              fontSize: 13,
            }}
          >
            No licence row for this user.
          </div>
        )}
      </Section>

      <Section
        title="Payments"
        subtitle={`${summary.payment_count} payment row${summary.payment_count === 1 ? '' : 's'}. Refund history shown as recorded by the gateway webhook.`}
      >
        <Table
          headers={['Invoice', 'Amount', 'Status', 'Payment ID', 'Order ID', 'When']}
          isEmpty={payments.length === 0}
          empty="No payments for this user."
        >
          {payments.map((p) => (
            <tr key={p.id}>
              <td style={{ ...tdStyle, fontFamily: MONO }}>{p.gst_invoice_no ?? '—'}</td>
              <td style={{ ...tdStyle, fontFamily: MONO, fontWeight: 700 }}>
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
      </Section>

      <Section title="Orders" subtitle="Order rows created at checkout, whether or not they were paid.">
        <Table
          headers={['Order ID', 'Amount', 'Status', 'Created']}
          isEmpty={orders.length === 0}
          empty="No orders for this user."
        >
          {orders.map((o) => (
            <tr key={o.id}>
              <td style={{ ...tdStyle, fontFamily: MONO, fontSize: 11.5 }}>
                {o.gateway_order_id ?? '—'}
              </td>
              <td style={{ ...tdStyle, fontFamily: MONO }}>
                {money(o.amount_minor, o.currency ?? 'INR')}
              </td>
              <td style={tdStyle}>
                <StatusPill status={o.status} />
              </td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(o.created_at)}
              </td>
            </tr>
          ))}
        </Table>
      </Section>

      <Section title="Devices" subtitle={`${summary.device_count} registered device${summary.device_count === 1 ? '' : 's'}.`}>
        <Table
          headers={['Platform', 'Model', 'Fingerprint', 'Last seen', 'Registered']}
          isEmpty={devices.length === 0}
          empty="No devices registered."
        >
          {devices.map((d) => (
            <tr key={d.id}>
              <td style={tdStyle}>{d.platform ?? '—'}</td>
              <td style={tdStyle}>{d.model ?? '—'}</td>
              <td style={{ ...tdStyle, fontFamily: MONO, color: C.muted, fontSize: 11 }}>
                {d.fingerprint ?? '—'}
              </td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(d.last_seen_at)}
              </td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(d.created_at)}
              </td>
            </tr>
          ))}
        </Table>
      </Section>

      <Section
        title="Sessions"
        subtitle={`${summary.active_session_count} active, most recent 50 shown. Single-session enforcement means only one should be unrevoked.`}
      >
        <Table
          headers={['Session ID', 'Device', 'Issued', 'Last seen', 'Revoked', 'Reason']}
          isEmpty={sessions.length === 0}
          empty="No sessions recorded."
        >
          {sessions.map((s) => (
            <tr key={s.id}>
              <td style={{ ...tdStyle, fontFamily: MONO, fontSize: 11 }}>{s.id}</td>
              <td style={{ ...tdStyle, fontFamily: MONO, fontSize: 11, color: C.muted }}>
                {s.device_id ?? '—'}
              </td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(s.issued_at)}
              </td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(s.last_seen_at)}
              </td>
              <td style={{ ...tdStyle, whiteSpace: 'nowrap' }}>
                {s.revoked_at ? (
                  <span style={{ color: C.red }}>{when(s.revoked_at)}</span>
                ) : (
                  <span style={{ color: C.green, fontWeight: 700 }}>active</span>
                )}
              </td>
              <td style={{ ...tdStyle, color: C.muted }}>{s.revoke_reason ?? '—'}</td>
            </tr>
          ))}
        </Table>
      </Section>
    </Shell>
  );
}
