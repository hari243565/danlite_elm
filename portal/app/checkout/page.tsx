// ══════════════════════════════════════════════════════════════════════════
// /checkout — the price and the Pay button. Requires a session.
//
// THE PRICE IS DECIDED SERVER-SIDE, FROM THE DATABASE. country_code is read
// out of public.profiles as the signed-in user, never taken from a query
// string, a form field, or a browser locale. Phase 1 went as far as adding a
// trigger (protect_profile_fields) that silently reverts any client attempt to
// change country_code, precisely because country selects the price: a
// client-editable country would be a 99% discount.
// ══════════════════════════════════════════════════════════════════════════

import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { NOINDEX } from '@/lib/seo';
import { C, cardStyle, pageStyle, legalLinkStyle, MONO } from '@/lib/theme';
import { createClient } from '@/lib/supabase/server';
import { priceFor, formatMinor, GST_TREATMENT } from '@/lib/gst';
import PayButton from './pay-button';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Checkout — Danlite ELM',
  robots: NOINDEX,
};

export default async function CheckoutPage() {
  const supabase = await createClient();

  // getUser() revalidates the JWT against the auth server. getSession() alone
  // would trust whatever is in the cookie, which is not good enough to gate a
  // page that shows a price.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect('/activate');

  const { data: profile } = await supabase
    .from('profiles')
    .select('country_code, email, phone')
    .eq('id', user.id)
    .maybeSingle();

  // Absent profile falls back to 'IN'. Deliberately the same default as the
  // profiles table itself, so the two cannot disagree.
  const country = profile?.country_code ?? 'IN';
  const price = priceFor(country);

  const rows: Array<{ label: string; value: string; strong?: boolean }> = [
    {
      label: price.taxApplies ? 'Licence (excl. GST)' : 'Lifetime licence',
      value: `${price.symbol}${formatMinor(price.baseMinor)}`,
    },
  ];
  if (price.taxApplies) {
    rows.push({ label: 'GST', value: `${price.symbol}${formatMinor(price.taxMinor)}` });
  }
  rows.push({
    label: 'Total',
    value: `${price.symbol}${formatMinor(price.totalMinor)}`,
    strong: true,
  });

  return (
    <main style={pageStyle}>
      <div style={{ maxWidth: 440, margin: '0 auto' }}>
        <h1 style={{ fontSize: 20, fontWeight: 700, margin: '0 0 6px' }}>Danlite ELM</h1>
        <p style={{ color: C.muted, fontSize: 13, margin: '0 0 26px' }}>Complete your purchase</p>

        <div style={cardStyle}>
          <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 4px' }}>
            Lifetime licence
          </h2>
          <p style={{ color: C.muted, fontSize: 13, lineHeight: 1.6, margin: '0 0 20px' }}>
            One payment. No subscription, no renewal. Unlocks the full app on your Android
            device, permanently.
          </p>

          <div
            style={{
              border: `1px solid ${C.border}`,
              backgroundColor: C.card,
              borderRadius: 8,
              padding: '4px 14px',
              marginBottom: 18,
            }}
          >
            {rows.map((r, i) => (
              <div
                key={r.label}
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'baseline',
                  padding: '11px 0',
                  borderTop: i === 0 ? 'none' : `1px solid ${C.border}`,
                  fontSize: r.strong ? 15 : 13.5,
                  fontWeight: r.strong ? 700 : 400,
                  color: r.strong ? C.text : C.muted,
                }}
              >
                <span>{r.label}</span>
                <span style={{ fontFamily: MONO, color: r.strong ? C.green : C.text }}>
                  {r.value}
                </span>
              </div>
            ))}
          </div>

          <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: '0 0 18px' }}>
            {price.note} Billed in {price.currency}.
          </p>

          <PayButton label={`Pay ${price.symbol}${formatMinor(price.totalMinor)}`} />

          <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: '18px 0 0' }}>
            Signed in as{' '}
            <span style={{ color: C.text, fontFamily: MONO }}>
              {profile?.email ?? profile?.phone ?? user.email ?? 'your account'}
            </span>
            . By paying you accept the{' '}
            <Link href="/legal/terms" style={{ color: C.cyan }}>
              Terms
            </Link>{' '}
            and{' '}
            <Link href="/legal/refund" style={{ color: C.cyan }}>
              Refund policy
            </Link>
            .
          </p>
        </div>

        {/* Visible to whoever is testing, not to a paying customer later.
            GST_TREATMENT is an unconfirmed assumption and should be impossible
            to forget about — see portal/lib/gst.ts. */}
        {process.env.NODE_ENV !== 'production' && (
          <p
            style={{
              margin: '18px 0 0',
              padding: '12px 14px',
              borderRadius: 8,
              border: `1px dashed ${C.amber}`,
              color: C.amber,
              fontSize: 12,
              lineHeight: 1.6,
            }}
          >
            DEV NOTE — GST treatment is set to <strong>{GST_TREATMENT}</strong> as a placeholder
            and has not been confirmed by an accountant. Country <strong>{country}</strong> read
            from profiles.
          </p>
        )}

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
