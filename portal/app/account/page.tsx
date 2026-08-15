// ══════════════════════════════════════════════════════════════════════════
// /account — what the customer owns, and how to sign out.
//
// The licence status shown here comes from the EXISTING /entitlement Edge
// Function (Phase 3), not from a direct read of the licences table. That is
// deliberate on two counts: there is one authority on entitlement, and every
// load of this page is an independent live test that Phase 3 still works when
// called by something other than the Flutter app.
//
// "Manage devices" and "Download invoice" are rendered but visibly disabled.
// They are real future features with nothing behind them yet, and showing them
// greyed out with an honest label is better than either hiding them (the
// customer wonders where their invoice is) or faking them (the customer clicks
// and nothing happens).
// ══════════════════════════════════════════════════════════════════════════

import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { NOINDEX } from '@/lib/seo';
import { C, cardStyle, pageStyle, legalLinkStyle, MONO, buttonStyle } from '@/lib/theme';
import { createClient } from '@/lib/supabase/server';
import { fetchEntitlement } from '@/lib/entitlement';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Your account — Danlite ELM',
  robots: NOINDEX,
};

/** Server Action. Unlike a page, an action may write cookies — so it can clear them. */
async function signOut() {
  'use server';
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect('/activate');
}

export default async function AccountPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect('/activate');

  const { data: profile } = await supabase
    .from('profiles')
    .select('email, phone, country_code')
    .eq('id', user.id)
    .maybeSingle();

  // The access token is only used to authenticate to /entitlement. It is never
  // rendered into the page.
  const {
    data: { session },
  } = await supabase.auth.getSession();

  const outcome = session?.access_token
    ? await fetchEntitlement(session.access_token)
    : ({ ok: false, reason: 'no_session_token' } as const);

  const licence = outcome.ok ? outcome.entitlement.lic : null;
  const isActive = licence === 'active';

  const statusColour = isActive ? C.green : licence ? C.amber : C.red;
  const statusLabel = isActive
    ? 'Active — lifetime licence'
    : licence === 'inactive'
      ? 'Not purchased yet'
      : licence
        ? `Licence ${licence}`
        : 'Could not be checked';

  return (
    <main style={pageStyle}>
      <div style={{ maxWidth: 440, margin: '0 auto' }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, margin: '0 0 6px' }}>Danlite ELM</h1>
        <p style={{ color: C.muted, fontSize: 13, margin: '0 0 26px' }}>Your account</p>

        {/* ── Licence status ───────────────────────────────────────────── */}
        <div style={{ ...cardStyle, marginBottom: 18 }}>
          <h2 style={{ fontSize: 13, fontWeight: 700, margin: '0 0 10px', color: C.muted }}>
            LICENCE
          </h2>
          <p style={{ color: statusColour, fontSize: 16, fontWeight: 700, margin: '0 0 6px' }}>
            {statusLabel}
          </p>

          {!outcome.ok && (
            <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: '0 0 12px' }}>
              We could not reach the licence service just now. This does not affect your
              licence — the app keeps working offline for up to 14 days.
            </p>
          )}

          {licence === 'inactive' && (
            <Link
              href="/checkout"
              style={{
                display: 'inline-block',
                marginTop: 8,
                color: C.cyan,
                fontSize: 13.5,
                fontWeight: 600,
                textDecoration: 'none',
              }}
            >
              Complete your purchase →
            </Link>
          )}
        </div>

        {/* ── Account details ──────────────────────────────────────────── */}
        <div style={{ ...cardStyle, marginBottom: 18 }}>
          <h2 style={{ fontSize: 13, fontWeight: 700, margin: '0 0 12px', color: C.muted }}>
            DETAILS
          </h2>
          {[
            { k: 'Email', v: profile?.email ?? user.email ?? '—' },
            { k: 'Mobile', v: profile?.phone ?? '—' },
            { k: 'Country', v: profile?.country_code ?? '—' },
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

        {/* ── Not yet available ────────────────────────────────────────── */}
        <div style={{ ...cardStyle, marginBottom: 18, opacity: 0.55 }}>
          <h2 style={{ fontSize: 13, fontWeight: 700, margin: '0 0 12px', color: C.muted }}>
            AVAILABLE AFTER YOUR FIRST PURCHASE
          </h2>
          {['Manage devices', 'Download invoice'].map((label, i) => (
            <div
              key={label}
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                gap: 16,
                padding: '12px 0',
                borderTop: i === 0 ? 'none' : `1px solid ${C.border}`,
                fontSize: 13.5,
              }}
            >
              <span style={{ color: C.muted }}>{label}</span>
              <span
                style={{
                  fontSize: 11,
                  color: C.muted,
                  border: `1px solid ${C.border}`,
                  borderRadius: 999,
                  padding: '3px 10px',
                  whiteSpace: 'nowrap',
                }}
              >
                Not yet available
              </span>
            </div>
          ))}
        </div>

        {/* ── Sign out ─────────────────────────────────────────────────── */}
        <form action={signOut}>
          <button
            type="submit"
            style={{
              ...buttonStyle,
              backgroundColor: 'transparent',
              color: C.muted,
              border: `1px solid ${C.border}`,
              fontWeight: 600,
            }}
          >
            Log out
          </button>
        </form>

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
