// ══════════════════════════════════════════════════════════════════════════
// /users/[id] — everything the system knows about one customer.
//
// Phase 1 shipped this page as display-only, on the reasoning that a read
// that goes wrong shows the wrong data while a write that goes wrong takes
// away something a customer paid for, and the two deserve separate design and
// separate review. That separate review is Phase 2, and this page now carries
// the three actions it authorised: Grant, Revoke and Force Sign-out.
//
// ── THE RULE FOR EVERY ACTION ON THIS PAGE ───────────────────────────────
// No action is reachable in one click, and none is reachable without a typed
// reason. Both are enforced by ConfirmAction, and — this is the part that
// matters — neither is TRUSTED from here. Each Server Action below re-reads
// the session server-side, and each Edge Function re-checks the allowlist,
// and each database function raises on an empty reason. The UI is the
// courteous layer on top of three real ones.
//
// Refunds are still absent, deliberately: money moves in Razorpay's dashboard
// and comes back through razorpay-webhook. Revoking a licence here does not
// refund anything and does not pretend to.
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
import { ConfirmAction, type ActionResult } from '../../confirm-action';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'User detail — Danlite ELM Admin',
  robots: NOINDEX,
};

// ── SERVER ACTIONS ────────────────────────────────────────────────────────
// One per admin action, each a thin forwarder to its Edge Function.
//
// A Server Action is a public POST endpoint — rendering the button on an
// authenticated page is not what protects it, because the request can be sent
// without ever loading the page. So each of these is written as if it were
// called by a stranger:
//   • callAdminFn() re-reads the session cookie and validates the JWT with
//     getUser() before it will send anything, returning 401 if there is none.
//   • The Edge Function then re-checks the caller's email against admin_users.
//   • The database function then insists on a non-empty reason.
// The `userId` argument is caller-supplied and deliberately so — the client is
// allowed to say WHICH customer, never WHO IS ACTING. The actor is taken from
// the verified token inside the Edge Function and cannot be set from here.
//
// Errors are returned as values rather than thrown so the dialog can show the
// real message inline instead of collapsing the page into an error boundary.

async function grantLicence(userId: string, reason: string): Promise<ActionResult> {
  'use server';
  const res = await callAdminFn('admin-grant-licence', {
    target_user_id: userId,
    reason,
  });
  return res.ok ? { ok: true } : { ok: false, error: res.error };
}

async function revokeLicence(userId: string, reason: string): Promise<ActionResult> {
  'use server';
  const res = await callAdminFn('admin-revoke-licence', {
    target_user_id: userId,
    reason,
  });
  return res.ok ? { ok: true } : { ok: false, error: res.error };
}

async function forceSignOut(userId: string, reason: string): Promise<ActionResult> {
  'use server';
  const res = await callAdminFn('admin-force-signout', {
    target_user_id: userId,
    reason,
  });
  return res.ok ? { ok: true } : { ok: false, error: res.error };
}

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

  // Which of the two licence actions applies. Anything that is not exactly
  // 'active' — inactive, revoked, refunded, or a status this build has never
  // heard of — is treated as grantable rather than revocable, because the
  // failure mode that matters is offering "revoke" on a licence that is
  // already gone.
  const isActive = licence?.status === 'active';

  // What the confirmation dialogs name. The email is what an operator
  // recognises; the id is the fallback that is always present.
  const who = profile.email ?? profile.id;

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
        Licence changes and forced sign-outs on this page are recorded in the audit log
        against your email address. Refunds stay in Razorpay&apos;s own dashboard.
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
            }}
          >
            <div
              style={{
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

            {/* CONTEXTUAL, NEVER BOTH. An active licence cannot be granted and
                an inactive one cannot be revoked, so offering the pair and
                failing one of them server-side would be a worse design than
                simply not showing the impossible action. */}
            <div
              style={{
                marginTop: 18,
                paddingTop: 16,
                borderTop: `1px solid ${C.border}`,
                display: 'flex',
                gap: 10,
                alignItems: 'center',
                flexWrap: 'wrap',
              }}
            >
              {isActive ? (
                <ConfirmAction
                  label="Revoke licence"
                  title="Revoke this licence?"
                  tone="danger"
                  confirmLabel="Revoke licence"
                  reasonHint="e.g. Chargeback received; access withdrawn pending resolution"
                  consequence={
                    <>
                      This will immediately revoke <strong>{who}</strong>&apos;s lifetime
                      licence. The app will stop unlocking on their next entitlement check.{' '}
                      <strong>No money is refunded</strong> — this changes access only.
                    </>
                  }
                  action={revokeLicence.bind(null, profile.id)}
                />
              ) : (
                <ConfirmAction
                  label="Grant licence"
                  title="Grant a licence?"
                  tone="primary"
                  confirmLabel="Grant licence"
                  reasonHint="e.g. Goodwill replacement after a failed checkout on 21 Aug"
                  consequence={
                    <>
                      This will grant <strong>{who}</strong> a lifetime licence with no
                      payment attached. It will be recorded with purchase rail{' '}
                      <code style={{ fontFamily: MONO, color: C.amber }}>admin_grant</code>,
                      never as a Razorpay sale.
                    </>
                  }
                  action={grantLicence.bind(null, profile.id)}
                />
              )}
              <span style={{ color: C.muted, fontSize: 11.5 }}>
                {isActive
                  ? 'Currently active. Granting is unavailable while a licence is active.'
                  : `Currently ${licence.status ?? 'unknown'}. Revoking is unavailable until a licence is active.`}
              </span>
            </div>
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
        {/* Always available, unlike Grant/Revoke. Signing out zero sessions is
            harmless and succeeds quietly, whereas hiding the button whenever
            the session list looks empty would take the escape hatch away at
            exactly the moment the data on screen is stale or wrong. */}
        <div
          style={{
            display: 'flex',
            gap: 10,
            alignItems: 'center',
            flexWrap: 'wrap',
            marginBottom: 12,
          }}
        >
          <ConfirmAction
            label="Force sign-out"
            title="Sign this customer out everywhere?"
            tone="danger"
            confirmLabel="Sign out all devices"
            reasonHint="e.g. Customer called: phone lost, needs to sign in on a replacement"
            consequence={
              <>
                This will revoke every live session for <strong>{who}</strong> and clear
                their active device, so the next sign-in on any device wins.{' '}
                <strong>Their licence is not affected</strong> — they keep their access and
                simply have to sign in again.
              </>
            }
            action={forceSignOut.bind(null, profile.id)}
          />
          <span style={{ color: C.muted, fontSize: 11.5 }}>
            Uses the same routine as the customer&apos;s own &ldquo;sign out all
            devices&rdquo; button.
          </span>
        </div>

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
