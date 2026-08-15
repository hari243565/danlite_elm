// ══════════════════════════════════════════════════════════════════════════
// /account — what the customer owns, and how to sign out.
//
// The licence status shown here comes from the EXISTING /entitlement Edge
// Function (Phase 3), not from a direct read of the licences table. That is
// deliberate on two counts: there is one authority on entitlement, and every
// load of this page is an independent live test that Phase 3 still works when
// called by something other than the Flutter app.
//
// "Download invoice" is rendered but visibly disabled. It is a real future
// feature with nothing behind it yet, and showing it greyed out with an honest
// label is better than either hiding it (the customer wonders where their
// invoice is) or faking it (the customer clicks and nothing happens).
//
// ══════════════════════════════════════════════════════════════════════════
// PHASE 7 — DEVICES. READ THIS BEFORE ADDING ANYTHING TO THIS PAGE.
// ══════════════════════════════════════════════════════════════════════════
//
// Rendering this page MUST NOT claim, supersede, or revoke a session. It reads
// device rows and nothing more. /claim-session is called by the Android app,
// once per login, and by nothing else — ever.
//
// The reason is not theoretical. A customer finishes paying on this website,
// the page load claims a session for "the web", and their phone is signed out
// the moment their money leaves their account. The app would look broken at
// exactly the point the customer had just paid for it.
//
// The ONLY thing on this page that may change server state is the "Sign out
// all devices" button below, and only when a human presses it and then
// confirms. It is a POST-only Server Action for that reason: a link
// prefetcher, a crawler, or an accidental refresh must not be able to trigger
// it.
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

/**
 * Server Action — revokes every live session for this user.
 *
 * The escape hatch for a lost or replaced phone. Reached only from the
 * confirmation step below, so it takes two deliberate clicks. `redirect()`
 * signals by throwing, so it is called AFTER the try/catch, never inside it.
 */
async function signOutAllDevices() {
  'use server';
  const supabase = await createClient();

  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session?.access_token) redirect('/activate');

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!base) redirect('/account?devices=error');

  let outcome = 'error';
  try {
    const res = await fetch(`${base}/functions/v1/sign-out-devices`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
      cache: 'no-store',
    });
    if (res.ok) {
      const body = (await res.json()) as { signed_out?: number };
      outcome = `ok:${typeof body.signed_out === 'number' ? body.signed_out : 0}`;
    }
  } catch {
    // Leave outcome as 'error'. The page says so plainly rather than claiming
    // a sign-out that may not have happened.
  }

  redirect(`/account?devices=${outcome}`);
}

type Search = Promise<{ [k: string]: string | string[] | undefined }>;

export default async function AccountPage({ searchParams }: { searchParams: Search }) {
  const sp = await searchParams;
  const devicesParam = typeof sp.devices === 'string' ? sp.devices : null;

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

  // ── Active device (Phase 7) ─────────────────────────────────────────────
  //
  // Read with the USER's own client, not the service role. RLS already limits
  // `licences`, `devices` and `sessions` to own rows, so the weakest possible
  // credential is sufficient here — and a page that only ever holds the
  // caller's own authority cannot leak somebody else's device by accident.
  //
  // Three plain SELECTs. Nothing here writes, and nothing here calls
  // /claim-session.
  const { data: licenceRow } = await supabase
    .from('licences')
    .select('active_session_id, active_device_id')
    .eq('user_id', user.id)
    .maybeSingle();

  const { data: activeDevice } = licenceRow?.active_device_id
    ? await supabase
        .from('devices')
        .select('platform, model, last_seen_at')
        .eq('id', licenceRow.active_device_id)
        .maybeSingle()
    : { data: null };

  const { data: activeSession } = licenceRow?.active_session_id
    ? await supabase
        .from('sessions')
        .select('issued_at, last_seen_at')
        .eq('id', licenceRow.active_session_id)
        .maybeSingle()
    : { data: null };

  const fmt = (iso: string | null | undefined) =>
    iso
      ? new Date(iso).toLocaleString('en-IN', {
          dateStyle: 'medium',
          timeStyle: 'short',
          timeZone: 'Asia/Kolkata',
        })
      : '—';

  const signedOutCount = devicesParam?.startsWith('ok:')
    ? Number(devicesParam.slice(3))
    : null;

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

        {/* ── Devices (Phase 7) ────────────────────────────────────────── */}
        <div style={{ ...cardStyle, marginBottom: 18 }}>
          <h2 style={{ fontSize: 13, fontWeight: 700, margin: '0 0 12px', color: C.muted }}>
            DEVICES
          </h2>

          <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: '0 0 14px' }}>
            Danlite ELM runs on one phone at a time. Signing in on a new phone
            signs the old one out automatically — you do not need to do anything
            here first.
          </p>

          {signedOutCount !== null && (
            <p style={{ color: C.green, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 14px' }}>
              Signed out of {signedOutCount} {signedOutCount === 1 ? 'device' : 'devices'}. Sign
              in again on the phone you want to use.
            </p>
          )}
          {devicesParam === 'error' && (
            <p style={{ color: C.amber, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 14px' }}>
              We could not complete that just now. Nothing was changed — please try again.
            </p>
          )}

          {activeDevice ? (
            <>
              {[
                { k: 'Device', v: activeDevice.model ?? 'Unknown model' },
                { k: 'Platform', v: activeDevice.platform ?? '—' },
                { k: 'Signed in', v: fmt(activeSession?.issued_at) },
                { k: 'Last seen', v: fmt(activeSession?.last_seen_at ?? activeDevice.last_seen_at) },
              ].map((row, i) => (
                <div
                  key={row.k}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    gap: 16,
                    padding: '11px 0',
                    borderTop: i === 0 ? `1px solid ${C.border}` : `1px solid ${C.border}`,
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

              {/* Two deliberate steps. Step one is a plain link, so it changes
                  nothing; step two is the POST that does. */}
              {devicesParam === 'confirm' ? (
                <div
                  style={{
                    marginTop: 16,
                    paddingTop: 14,
                    borderTop: `1px solid ${C.border}`,
                  }}
                >
                  <p style={{ color: C.text, fontSize: 13, lineHeight: 1.6, margin: '0 0 12px' }}>
                    Sign out of all devices? You will need to sign in again on the phone you
                    want to use.
                  </p>
                  <div style={{ display: 'flex', gap: 10 }}>
                    <form action={signOutAllDevices} style={{ flex: 1 }}>
                      <button
                        type="submit"
                        style={{
                          ...buttonStyle,
                          backgroundColor: 'transparent',
                          color: C.red,
                          border: `1px solid ${C.red}`,
                          fontWeight: 600,
                        }}
                      >
                        Yes, sign out everywhere
                      </button>
                    </form>
                    <Link
                      href="/account"
                      style={{
                        ...buttonStyle,
                        flex: 1,
                        backgroundColor: 'transparent',
                        color: C.muted,
                        border: `1px solid ${C.border}`,
                        fontWeight: 600,
                        textDecoration: 'none',
                        textAlign: 'center',
                      }}
                    >
                      Cancel
                    </Link>
                  </div>
                </div>
              ) : (
                <Link
                  href="/account?devices=confirm"
                  style={{
                    display: 'inline-block',
                    marginTop: 14,
                    color: C.cyan,
                    fontSize: 13.5,
                    fontWeight: 600,
                    textDecoration: 'none',
                  }}
                >
                  Sign out all devices →
                </Link>
              )}
            </>
          ) : (
            <p style={{ color: C.muted, fontSize: 13, lineHeight: 1.6, margin: 0 }}>
              No device is signed in right now. Sign in on the Danlite ELM app and it will
              appear here.
            </p>
          )}
        </div>

        {/* ── Not yet available ────────────────────────────────────────── */}
        <div style={{ ...cardStyle, marginBottom: 18, opacity: 0.55 }}>
          <h2 style={{ fontSize: 13, fontWeight: 700, margin: '0 0 12px', color: C.muted }}>
            AVAILABLE AFTER YOUR FIRST PURCHASE
          </h2>
          {['Download invoice'].map((label, i) => (
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
