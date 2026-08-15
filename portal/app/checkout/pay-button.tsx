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
// ══════════════════════════════════════════════════════════════════════════

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { C, buttonStyle } from '@/lib/theme';

export type CreateOrderResult =
  | {
      kind: 'ok';
      orderId: string;
      amount: number;
      currency: string;
      keyId: string;
      prefill: { email?: string; contact?: string };
    }
  | { kind: 'unavailable'; message: string }
  | { kind: 'already_licensed'; message: string }
  | { kind: 'signed_out'; message: string }
  | { kind: 'error'; message: string };

/** Minimal shape of what we use from Checkout.js. */
type RazorpayInstance = {
  open: () => void;
  on: (event: string, cb: (e: unknown) => void) => void;
};
declare global {
  interface Window {
    Razorpay?: new (options: Record<string, unknown>) => RazorpayInstance;
  }
}

const CHECKOUT_JS = 'https://checkout.razorpay.com/v1/checkout.js';

/**
 * Loaded on click, not on page load. A customer who never presses Pay never
 * fetches a third-party script, and /checkout renders without waiting on
 * Razorpay's CDN.
 */
function loadCheckoutJs(): Promise<boolean> {
  return new Promise((resolve) => {
    if (typeof window === 'undefined') return resolve(false);
    if (window.Razorpay) return resolve(true);

    const existing = document.querySelector<HTMLScriptElement>(
      `script[src="${CHECKOUT_JS}"]`,
    );
    if (existing) {
      existing.addEventListener('load', () => resolve(Boolean(window.Razorpay)));
      existing.addEventListener('error', () => resolve(false));
      return;
    }

    const s = document.createElement('script');
    s.src = CHECKOUT_JS;
    s.async = true;
    s.onload = () => resolve(Boolean(window.Razorpay));
    s.onerror = () => resolve(false);
    document.body.appendChild(s);
  });
}

type UiState =
  | 'idle'
  | 'working'
  | 'open'
  | 'cancelled'
  | 'unavailable'
  | 'licensed'
  | 'error';

export default function PayButton({
  label,
  createOrder,
}: {
  label: string;
  createOrder: () => Promise<CreateOrderResult>;
}) {
  const router = useRouter();
  const [state, setState] = useState<UiState>('idle');
  const [message, setMessage] = useState('');

  async function pay() {
    if (state === 'working' || state === 'open') return;
    setState('working');
    setMessage('');

    let result: CreateOrderResult;
    try {
      result = await createOrder();
    } catch {
      setState('error');
      setMessage('Could not reach the server. Check your connection and try again.');
      return;
    }

    if (result.kind === 'unavailable') {
      setState('unavailable');
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

    const loaded = await loadCheckoutJs();
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
    state === 'unavailable' || state === 'licensed'
      ? C.amber
      : state === 'cancelled'
        ? C.muted
        : state === 'error'
          ? C.red
          : null;

  return (
    <>
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
