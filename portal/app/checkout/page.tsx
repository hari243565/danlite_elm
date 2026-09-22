// ══════════════════════════════════════════════════════════════════════════
// /checkout — the price and the Pay button. Requires a session.
//
// THE PRICE IS DECIDED SERVER-SIDE, FROM THE DATABASE. country_code is read
// out of public.profiles as the signed-in user, never taken from a query
// string, a form field, or a browser locale. Phase 1 went as far as adding a
// trigger (protect_profile_fields) that silently reverts any client attempt to
// change country_code, precisely because country selects the price: a
// client-editable country would be a 99% discount.
//
// ── PHASE 5: WHAT THIS PAGE MAY AND MAY NOT DO ──────────────────────────
// It may open an order. It may hand Razorpay's Checkout the order id. It may
// send the customer to /confirmation afterwards.
//
// It may NOT record a payment, and it may NOT activate a licence — and no
// code path from this page to either exists to be misused. The browser's
// "payment succeeded" callback is a UI event, not evidence: it is produced on
// the customer's own machine and is trivially forgeable. Only
// /razorpay-webhook, after verifying an HMAC-SHA256 signature over the raw
// request body, may write payments or licences.
// ══════════════════════════════════════════════════════════════════════════

import type { Metadata } from 'next';
import Link from 'next/link';
import { headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { NOINDEX } from '@/lib/seo';
import { C, cardStyle, pageStyle, legalLinkStyle, MONO } from '@/lib/theme';
import { createClient } from '@/lib/supabase/server';
import { priceFor, formatMinor, GST_TREATMENT } from '@/lib/gst';
import { rateLimit, clientIpFrom } from '@/lib/rate-limit';
import PayButton, {
  type CreateOrderInput,
  type CreateOrderResult,
} from './pay-button';

export const dynamic = 'force-dynamic';

/** Deliberately tight. Nothing legitimate opens orders more than a few times. */
const MAX_ORDER_ATTEMPTS = 10;
const ORDER_WINDOW_MS = 60_000;

// ══════════════════════════════════════════════════════════════════════════
// The server action behind the Pay button.
//
// WHY A SERVER ACTION AND NOT A BROWSER FETCH: the Supabase session lives in
// httpOnly cookies (Phase 4, deliberately — an XSS bug must not be able to
// exfiltrate a refresh token). Page JavaScript therefore cannot read the
// access token, and so cannot call the Edge Function directly. This action
// runs on the server, where the cookie is readable, and forwards the caller's
// own token. The portal still never holds a service-role key.
// ══════════════════════════════════════════════════════════════════════════
async function createOrderAction(input: CreateOrderInput): Promise<CreateOrderResult> {
  'use server';

  // Carried over from the Phase 4 stub rather than quietly dropped when the
  // endpoint moved. Single-instance and in-process — honest about its scope,
  // exactly as portal/lib/rate-limit.ts says.
  //
  // This is NOT the card-testing limiter. It is unchanged, it applies to both
  // rails as it always has, and it resets on every cold start, which is why
  // it cannot be the control that guards a card-testing target. The durable
  // one lives in the Edge Function against public.intl_order_attempts and
  // fires only on the international rail.
  const ip = clientIpFrom(await headers());
  const limit = rateLimit(`create-order:${ip}`, MAX_ORDER_ATTEMPTS, ORDER_WINDOW_MS);
  if (!limit.ok) {
    return {
      kind: 'error',
      message: `Too many attempts. Please wait ${limit.retryAfterSeconds}s and try again.`,
    };
  }

  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { kind: 'signed_out', message: 'Your session has expired. Please sign in again.' };
  }

  // getUser() above already revalidated the JWT against the auth server; this
  // read is only to obtain the raw token to forward. The Edge Function
  // independently validates it again on arrival.
  const {
    data: { session },
  } = await supabase.auth.getSession();
  const accessToken = session?.access_token;
  if (!accessToken) {
    return { kind: 'signed_out', message: 'Your session has expired. Please sign in again.' };
  }

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!base || !anonKey) {
    console.error('NEXT_PUBLIC_SUPABASE_URL / ANON_KEY not set');
    return { kind: 'error', message: 'Checkout is not configured. Please contact support.' };
  }

  try {
    const res = await fetch(`${base}/functions/v1/create-order`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        apikey: anonKey,
        'Content-Type': 'application/json',
      },
      // Forwarded, not trusted. The Edge Function re-normalises all three and
      // uses them only as evidence and soft signals — the amount it charges
      // comes from profiles.country_code, which is not in this body and
      // cannot be put there.
      body: JSON.stringify({
        billing_country: input.billingCountry,
        billing_postal_code: input.billingPostalCode,
        bot_token: input.botToken,
      }),
      cache: 'no-store',
    });

    const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;

    if (res.status === 409) {
      return {
        kind: 'already_licensed',
        message:
          (body.message as string) ??
          'You already have a lifetime licence on this account.',
      };
    }

    // The card-testing limiter. Its own kind rather than a generic error, so
    // the customer is told to wait rather than told something broke — and so
    // this stays visually distinct from a payment failure.
    if (res.status === 429) {
      return {
        kind: 'rate_limited',
        message:
          (body.message as string) ??
          'Too many checkout attempts. Please wait a few minutes and try again.',
      };
    }

    if (!res.ok) {
      console.error(`create-order failed ${res.status}`);
      return {
        kind: 'error',
        message: (body.error as string) ?? 'Could not start checkout. Please try again.',
      };
    }

    return {
      kind: 'ok',
      orderId: body.order_id as string,
      amount: body.amount as number,
      currency: body.currency as string,
      // Razorpay's own design exposes the Key ID to the browser; it identifies
      // the account and authorises nothing without the secret, which never
      // leaves Supabase. It reaches the page only through this response — it
      // is not in .env.local.example, not in any committed file, and not in
      // the repo at all.
      keyId: body.key_id as string,
      prefill: (body.prefill as { email?: string; contact?: string }) ?? {},
    };
  } catch (e) {
    console.error('create-order request failed:', e instanceof Error ? e.message : String(e));
    return { kind: 'error', message: 'Could not reach the payment service. Please try again.' };
  }
}

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

  // The one place the rail is decided for this page, from the same value
  // priceFor() just used. Kept as a named constant rather than repeating the
  // comparison, so the price shown and the fields shown cannot disagree.
  const isIndia = country.toUpperCase() === 'IN';

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

          {/* The billing-address fields appear on the international rail
              only. `country` here is profiles.country_code — the same value
              that selected the price above — so this cannot be turned on by
              anything the browser sends. A domestic customer sees exactly the
              checkout they saw before this rail existed. */}
          <PayButton
            label={`Pay ${price.symbol}${formatMinor(price.totalMinor)}`}
            createOrder={createOrderAction}
            collectBillingAddress={!isIndia}
            defaultBillingCountry={isIndia ? '' : country.toUpperCase()}
            // Public by design — a reCAPTCHA site key identifies the site in
            // the browser and authorises nothing; the API key that reads an
            // assessment lives only in the Edge Function's secrets. null when
            // unset, which makes the whole check fail open.
            recaptchaSiteKey={process.env.NEXT_PUBLIC_RECAPTCHA_SITE_KEY ?? null}
          />

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
