'use client';

// ══════════════════════════════════════════════════════════════════════════
// The Pay button. Opens a real Razorpay Checkout against a real order.
//
// ── THE ONE THING THIS FILE MUST NEVER DO ────────────────────────────────
// Razorpay's `handler` callback fires in THIS browser when Checkout believes
// the payment succeeded. It is a UI event on the customer's own machine. It
// can be fired by anyone with dev tools open, and it carries no proof of
// anything. So it does exactly one thing here: navigate to /confirmation.
//
// It does not call an API. It does not mark anything paid. There is no
// endpoint in this codebase it could call to do so — /confirmation reads the
// database and reports what it finds, and the only writer is the webhook,
// after an HMAC signature has verified. If you are editing this file and are
// tempted to "just update the licence here so it feels faster", that is the
// exact bug this architecture was built to make impossible.
//
// ── WHAT THIS FILE SENDS TO THE SERVER, AND WHY IT CANNOT SET A PRICE ────
// With the international rail live, this component now sends three things up
// to the server action: a billing country, a billing postcode, and a bot
// token. All three are advisory. None is in scope when the amount is chosen —
// /create-order derives the amount from profiles.country_code alone, via a
// function whose only parameter is a country code. The billing country box
// below is NOT the country that selects the price, and typing 'IN' into it
// buys nothing; there is a test named exactly that in
// supabase/tests/functions/intl_pricing.test.ts.
// ══════════════════════════════════════════════════════════════════════════

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { C, buttonStyle, MONO } from '@/lib/theme';

export type CreateOrderInput = {
  billingCountry: string;
  billingPostalCode: string;
  botToken: string | null;
};

export type CreateOrderResult =
  | {
      kind: 'ok';
      orderId: string;
      amount: number;
      currency: string;
      keyId: string;
      prefill: { email?: string; contact?: string };
    }
  | { kind: 'rate_limited'; message: string }
  | { kind: 'already_licensed'; message: string }
  | { kind: 'signed_out'; message: string }
  | { kind: 'error'; message: string };

/** Minimal shape of what we use from Checkout.js. */
type RazorpayInstance = {
  open: () => void;
  on: (event: string, cb: (e: unknown) => void) => void;
};
type Grecaptcha = {
  enterprise: {
    ready: (cb: () => void) => void;
    execute: (siteKey: string, opts: { action: string }) => Promise<string>;
  };
};
declare global {
  interface Window {
    Razorpay?: new (options: Record<string, unknown>) => RazorpayInstance;
    grecaptcha?: Grecaptcha;
  }
}

const CHECKOUT_JS = 'https://checkout.razorpay.com/v1/checkout.js';

/** Must match CHECKOUT_ACTION in supabase/functions/_shared/bot_score.ts. */
const RECAPTCHA_ACTION = 'intl_checkout_pay';

/**
 * Loaded on click, not on page load. A customer who never presses Pay never
 * fetches a third-party script, and /checkout renders without waiting on
 * Razorpay's CDN.
 */
function loadScript(src: string, isReady: () => boolean): Promise<boolean> {
  return new Promise((resolve) => {
    if (typeof window === 'undefined') return resolve(false);
    if (isReady()) return resolve(true);

    const existing = document.querySelector<HTMLScriptElement>(`script[src="${src}"]`);
    if (existing) {
      existing.addEventListener('load', () => resolve(isReady()));
      existing.addEventListener('error', () => resolve(false));
      return;
    }

    const s = document.createElement('script');
    s.src = src;
    s.async = true;
    s.onload = () => resolve(isReady());
    s.onerror = () => resolve(false);
    document.body.appendChild(s);
  });
}

/**
 * Mint an invisible reCAPTCHA Enterprise token for the PAY action
 * specifically — not for the page, and not for the session. Scoring the one
 * action the fraudster actually wants is the documented shape, and it is also
 * the only shape that does not interrupt a customer who has already decided
 * to buy.
 *
 * Returns null on every failure path: no site key configured, script blocked,
 * provider down, execute() rejected. The server treats a null token as "no
 * signal" and proceeds. An ad blocker must not be able to prevent a sale.
 */
async function mintBotToken(siteKey: string | null): Promise<string | null> {
  if (!siteKey) return null;
  try {
    const ok = await loadScript(
      `https://www.google.com/recaptcha/enterprise.js?render=${encodeURIComponent(siteKey)}`,
      () => Boolean(window.grecaptcha?.enterprise),
    );
    if (!ok || !window.grecaptcha?.enterprise) return null;

    return await new Promise<string | null>((resolve) => {
      // If the provider never calls ready(), we must not hang the Pay button
      // forever — 4s then proceed without a token.
      const timer = setTimeout(() => resolve(null), 4000);
      window.grecaptcha!.enterprise.ready(() => {
        window
          .grecaptcha!.enterprise.execute(siteKey, { action: RECAPTCHA_ACTION })
          .then((t) => {
            clearTimeout(timer);
            resolve(t);
          })
          .catch(() => {
            clearTimeout(timer);
            resolve(null);
          });
      });
    });
  } catch {
    return null;
  }
}

type UiState = 'idle' | 'working' | 'open' | 'cancelled' | 'limited' | 'licensed' | 'error';

const fieldStyle: React.CSSProperties = {
  width: '100%',
  boxSizing: 'border-box',
  padding: '10px 12px',
  borderRadius: 8,
  border: `1px solid ${C.border}`,
  backgroundColor: C.card,
  color: C.text,
  fontSize: 13.5,
  fontFamily: MONO,
};

const labelStyle: React.CSSProperties = {
  display: 'block',
  color: C.muted,
  fontSize: 12,
  marginBottom: 6,
};

export default function PayButton({
  label,
  createOrder,
  collectBillingAddress,
  defaultBillingCountry,
  recaptchaSiteKey,
}: {
  label: string;
  createOrder: (input: CreateOrderInput) => Promise<CreateOrderResult>;
  /** True only on the international rail — see the note in page.tsx. */
  collectBillingAddress: boolean;
  defaultBillingCountry: string;
  recaptchaSiteKey: string | null;
}) {
  const router = useRouter();
  const [state, setState] = useState<UiState>('idle');
  const [message, setMessage] = useState('');
  const [billingCountry, setBillingCountry] = useState(defaultBillingCountry);
  const [billingPostalCode, setBillingPostalCode] = useState('');

  // Warm the provider script while the customer is reading the price, so
  // pressing Pay does not wait on a CDN. Harmless if it never finishes.
  const warmed = useRef(false);
  useEffect(() => {
    if (!collectBillingAddress || !recaptchaSiteKey || warmed.current) return;
    warmed.current = true;
    void loadScript(
      `https://www.google.com/recaptcha/enterprise.js?render=${encodeURIComponent(recaptchaSiteKey)}`,
      () => Boolean(window.grecaptcha?.enterprise),
    );
  }, [collectBillingAddress, recaptchaSiteKey]);

  async function pay() {
    if (state === 'working' || state === 'open') return;
    setState('working');
    setMessage('');

    const botToken = collectBillingAddress ? await mintBotToken(recaptchaSiteKey) : null;

    let result: CreateOrderResult;
    try {
      result = await createOrder({
        billingCountry: collectBillingAddress ? billingCountry : '',
        billingPostalCode: collectBillingAddress ? billingPostalCode : '',
        botToken,
      });
    } catch {
      setState('error');
      setMessage('Could not reach the server. Check your connection and try again.');
      return;
    }

    if (result.kind === 'rate_limited') {
      setState('limited');
      setMessage(result.message);
      return;
    }
    if (result.kind === 'already_licensed') {
      setState('licensed');
      setMessage(result.message);
      return;
    }
    if (result.kind === 'signed_out') {
      setState('error');
      setMessage(result.message);
      router.push('/activate');
      return;
    }
    if (result.kind === 'error') {
      setState('error');
      setMessage(result.message);
      return;
    }

    const loaded = await loadScript(CHECKOUT_JS, () => Boolean(window.Razorpay));
    if (!loaded || !window.Razorpay) {
      setState('error');
      setMessage(
        'Could not load the payment window. Check your connection, or disable any ad blocker for this page, and try again.',
      );
      return;
    }

    setState('open');

    const rzp = new window.Razorpay({
      key: result.keyId,
      order_id: result.orderId,
      amount: result.amount,
      currency: result.currency,
      name: 'Danlite ELM',
      description: 'Lifetime licence',
      prefill: {
        email: result.prefill.email ?? '',
        contact: result.prefill.contact ?? '',
      },
      theme: { color: C.cyan },
      notes: { order_id: result.orderId },

      // ── See the header of this file. One navigation, nothing else. ──────
      handler: () => {
        router.push(`/confirmation?order_id=${encodeURIComponent(result.orderId)}`);
      },

      modal: {
        // Cancelling is a normal thing a customer does, not an error. Back to
        // a neutral state with the button live again.
        ondismiss: () => {
          setState('cancelled');
          setMessage('Payment cancelled. Nothing has been charged.');
        },
      },
    });

    rzp.on('payment.failed', () => {
      setState('error');
      setMessage('That payment did not go through. No money has been taken — please try again.');
    });

    rzp.open();
  }

  const busy = state === 'working' || state === 'open';

  const banner =
    state === 'limited' || state === 'licensed'
      ? C.amber
      : state === 'cancelled'
        ? C.muted
        : state === 'error'
          ? C.red
          : null;

  return (
    <>
      {collectBillingAddress && (
        <div style={{ marginBottom: 18 }}>
          <div style={{ display: 'flex', gap: 12 }}>
            <div style={{ flex: 1 }}>
              <label htmlFor="billing-country" style={labelStyle}>
                Billing country
              </label>
              <input
                id="billing-country"
                name="billing-country"
                autoComplete="billing country"
                maxLength={2}
                placeholder="US"
                value={billingCountry}
                onChange={(e) => setBillingCountry(e.target.value.toUpperCase().slice(0, 2))}
                disabled={busy}
                style={fieldStyle}
              />
            </div>
            <div style={{ flex: 1 }}>
              <label htmlFor="billing-postal" style={labelStyle}>
                Postcode{' '}
                <span style={{ opacity: 0.7 }}>(optional)</span>
              </label>
              <input
                id="billing-postal"
                name="billing-postal"
                autoComplete="billing postal-code"
                maxLength={32}
                placeholder="—"
                value={billingPostalCode}
                onChange={(e) => setBillingPostalCode(e.target.value.slice(0, 32))}
                disabled={busy}
                style={fieldStyle}
              />
            </div>
          </div>

          {/* The postcode is OPTIONAL on purpose. Several countries this rail
              serves — the UAE, Hong Kong, much of Ireland — have no postcode
              to give, and a required field they cannot satisfy is a checkout
              they abandon. It improves card verification where it exists and
              costs nothing where it does not. */}
          <p style={{ color: C.muted, fontSize: 11.5, lineHeight: 1.6, margin: '8px 0 0' }}>
            Used to help your bank verify the card. It does not change your price, and a
            mismatch will not stop your payment.
          </p>
        </div>
      )}

      <button
        type="button"
        onClick={pay}
        disabled={busy}
        style={{ ...buttonStyle, opacity: busy ? 0.6 : 1 }}
      >
        {state === 'working' ? 'Please wait…' : state === 'open' ? 'Payment window open…' : label}
      </button>

      {banner && message && (
        <p
          style={{
            margin: '14px 0 0',
            padding: '12px 14px',
            borderRadius: 8,
            border: `1px solid ${banner}`,
            color: banner,
            fontSize: 13,
            lineHeight: 1.6,
          }}
        >
          {message}
        </p>
      )}
    </>
  );
}
