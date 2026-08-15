'use client';

// The Pay button. Calls /api/create-order, which is an honest 501 stub until
// Phase 5/6 wires Razorpay. When it gets that 501 it shows the server's own
// message inline, as a normal piece of the page — not a browser error dialog
// and not a fake success.

import { useState } from 'react';
import { C, buttonStyle } from '@/lib/theme';

export default function PayButton({ label }: { label: string }) {
  const [state, setState] = useState<'idle' | 'working' | 'unavailable' | 'error'>('idle');
  const [message, setMessage] = useState('');

  async function pay() {
    if (state === 'working') return;
    setState('working');
    try {
      const res = await fetch('/api/create-order', { method: 'POST' });
      const body = await res.json().catch(() => ({}));

      if (res.status === 501) {
        setState('unavailable');
        setMessage(body?.message ?? 'Checkout opens soon.');
        return;
      }
      if (!res.ok) {
        setState('error');
        setMessage('Something went wrong. Please try again shortly.');
        return;
      }
      // Phase 5/6 replaces this branch with the Razorpay handoff.
      setState('idle');
    } catch {
      setState('error');
      setMessage('Could not reach the server. Check your connection and try again.');
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={pay}
        disabled={state === 'working'}
        style={{ ...buttonStyle, opacity: state === 'working' ? 0.6 : 1 }}
      >
        {state === 'working' ? 'Please wait…' : label}
      </button>

      {(state === 'unavailable' || state === 'error') && (
        <p
          style={{
            margin: '14px 0 0',
            padding: '12px 14px',
            borderRadius: 8,
            border: `1px solid ${state === 'unavailable' ? C.amber : C.red}`,
            color: state === 'unavailable' ? C.amber : C.red,
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
