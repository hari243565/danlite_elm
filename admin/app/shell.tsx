// ══════════════════════════════════════════════════════════════════════════
// The chrome every signed-in admin page renders inside: a header with the
// signed-in address and a sign-out button, and four nav links.
//
// Kept as one component rather than repeated per page so the nav cannot drift
// out of sync between screens — and, more practically, so there is exactly
// one place that renders "signed in as X", which is the thing an operator
// glances at to confirm they are looking at the right account.
// ══════════════════════════════════════════════════════════════════════════

import Link from 'next/link';
import { C, FONT, MONO, pageStyle } from '@/lib/theme';
import { SignOutButton } from './sign-out-button';

const NAV = [
  { href: '/', label: 'Overview' },
  { href: '/users', label: 'Users' },
  { href: '/payments', label: 'Payments' },
  { href: '/audit-log', label: 'Audit log' },
] as const;

export function Shell({
  email,
  active,
  children,
}: {
  email: string;
  active: string;
  children: React.ReactNode;
}) {
  return (
    <div style={pageStyle}>
      <header
        style={{
          borderBottom: `1px solid ${C.border}`,
          backgroundColor: C.surface,
          padding: '0 20px',
          position: 'sticky',
          top: 0,
          zIndex: 10,
        }}
      >
        <div
          style={{
            maxWidth: 1280,
            margin: '0 auto',
            display: 'flex',
            alignItems: 'center',
            gap: 20,
            flexWrap: 'wrap',
            minHeight: 58,
          }}
        >
          <span style={{ fontWeight: 800, fontSize: 15, letterSpacing: 0.3 }}>
            Danlite ELM{' '}
            <span style={{ color: C.cyan, fontWeight: 700 }}>Admin</span>
          </span>

          <nav style={{ display: 'flex', gap: 4, flex: 1, flexWrap: 'wrap' }}>
            {NAV.map((n) => {
              const isActive = n.href === active;
              return (
                <Link
                  key={n.href}
                  href={n.href}
                  style={{
                    padding: '7px 13px',
                    borderRadius: 8,
                    fontSize: 13.5,
                    fontWeight: isActive ? 700 : 500,
                    textDecoration: 'none',
                    color: isActive ? C.bg : C.muted,
                    backgroundColor: isActive ? C.cyan : 'transparent',
                    fontFamily: FONT,
                  }}
                >
                  {n.label}
                </Link>
              );
            })}
          </nav>

          <span style={{ color: C.muted, fontSize: 12, fontFamily: MONO }}>{email}</span>
          <SignOutButton />
        </div>
      </header>

      <main style={{ maxWidth: 1280, margin: '0 auto', padding: '26px 20px 64px' }}>
        {children}
      </main>
    </div>
  );
}

/** Standard error card. Used wherever an Edge Function refused or failed —
 *  including a 403, which is what an admin removed from the allowlist mid-
 *  session will see on their very next page load. */
export function ErrorCard({ status, message }: { status: number; message: string }) {
  const isAuth = status === 401 || status === 403;
  return (
    <div
      style={{
        border: `1px solid ${isAuth ? C.red : C.amber}`,
        backgroundColor: `${isAuth ? C.red : C.amber}12`,
        borderRadius: 12,
        padding: 20,
      }}
    >
      <div style={{ color: isAuth ? C.red : C.amber, fontWeight: 800, marginBottom: 6 }}>
        {isAuth ? 'Access denied' : 'Could not load this data'}
      </div>
      <p style={{ color: C.muted, fontSize: 13, lineHeight: 1.6, margin: 0 }}>
        {message}
        {isAuth
          ? ' Your email is checked against the admin allowlist on every request — if it was removed, access ends immediately.'
          : ''}
      </p>
    </div>
  );
}

export function Section({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <section style={{ marginBottom: 26 }}>
      <h2 style={{ fontSize: 14, fontWeight: 800, margin: '0 0 3px', letterSpacing: 0.3 }}>
        {title}
      </h2>
      {subtitle ? (
        <p style={{ color: C.muted, fontSize: 12, margin: '0 0 12px' }}>{subtitle}</p>
      ) : (
        <div style={{ height: 12 }} />
      )}
      {children}
    </section>
  );
}

/** Dense table shell. `overflow-x: auto` on the wrapper is load-bearing:
 *  these tables are wider than a laptop screen and the page body must never
 *  scroll sideways. */
export function Table({
  headers,
  children,
  empty,
  isEmpty,
}: {
  headers: string[];
  children: React.ReactNode;
  empty: string;
  isEmpty: boolean;
}) {
  if (isEmpty) {
    return (
      <div
        style={{
          border: `1px solid ${C.border}`,
          borderRadius: 12,
          padding: 26,
          textAlign: 'center',
          color: C.muted,
          fontSize: 13,
        }}
      >
        {empty}
      </div>
    );
  }

  return (
    <div
      style={{
        border: `1px solid ${C.border}`,
        borderRadius: 12,
        overflowX: 'auto',
        backgroundColor: C.surface,
      }}
    >
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12.5, minWidth: 680 }}>
        <thead>
          <tr>
            {headers.map((h) => (
              <th
                key={h}
                style={{
                  textAlign: 'left',
                  padding: '11px 14px',
                  color: C.muted,
                  fontWeight: 700,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  textTransform: 'uppercase',
                  borderBottom: `1px solid ${C.border}`,
                  whiteSpace: 'nowrap',
                }}
              >
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}

export const tdStyle: React.CSSProperties = {
  padding: '11px 14px',
  borderBottom: `1px solid ${C.border}`,
  color: C.text,
  verticalAlign: 'top',
};

export function StatusPill({ status }: { status: string | null | undefined }) {
  const color = statusColorLocal(status);
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '2px 9px',
        borderRadius: 999,
        border: `1px solid ${color}55`,
        backgroundColor: `${color}18`,
        color,
        fontSize: 11,
        fontWeight: 700,
        whiteSpace: 'nowrap',
      }}
    >
      {status ?? 'none'}
    </span>
  );
}

// Local copy of the mapping so this module has no import cycle with theme.ts
// via the pages. Kept in sync by being three lines long.
function statusColorLocal(status: string | null | undefined): string {
  switch (status) {
    case 'active':
    case 'captured':
      return C.green;
    case 'created':
    case 'authorized':
    case 'partially_refunded':
      return C.amber;
    case 'revoked':
    case 'refunded':
    case 'failed':
      return C.red;
    default:
      return C.muted;
  }
}
