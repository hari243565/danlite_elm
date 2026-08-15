'use client';

// ══════════════════════════════════════════════════════════════════════════
// The "send me a new link" form.
//
// WHY THIS POSTS STRAIGHT TO THE EDGE FUNCTION rather than going through a
// Next.js server action: /send-activation rate-limits by client IP. If the
// request were proxied through this server, every customer in the country
// would arrive wearing the portal's single IP address and the 10-per-hour IP
// budget would lock out real customers within minutes. Posting from the
// browser means the limiter sees the actual caller.
//
// The response is deliberately treated as opaque — success and "no such
// account" are the same message, because the Edge Function returns the same
// body for both. Nothing here tries to be more informative than the server
// was willing to be.
// ══════════════════════════════════════════════════════════════════════════

import { useState } from 'react';
import { C, buttonStyle, inputStyle, MONO } from '@/lib/theme';

export default function RequestForm({ functionsBase }: { functionsBase: string | null }) {
  const [identifier, setIdentifier] = useState('');
  const [state, setState] = useState<'idle' | 'sending' | 'done' | 'limited' | 'error'>('idle');
  const [message, setMessage] = useState('');

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!identifier.trim() || state === 'sending') return;

    if (!functionsBase) {
      setState('error');
      setMessage('This portal is not configured yet. Please contact support.');
      return;
    }

    setState('sending');
    try {
      const res = await fetch(`${functionsBase}/functions/v1/send-activation`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ identifier: identifier.trim() }),
      });
      const body = await res.json().catch(() => ({}));

      if (res.status === 429) {
        setState('limited');
        setMessage(body?.message ?? 'Too many requests. Please try again in an hour.');
        return;
      }
      if (!res.ok) {
        setState('error');
        setMessage('Something went wrong. Please try again in a moment.');
        return;
      }
      setState('done');
      setMessage(body?.message ?? '');
    } catch {
      setState('error');
      setMessage('Could not reach the server. Check your connection and try again.');
    }
  }

  if (state === 'done') {
    return (
      <p
        style={{
          margin: 0,
          padding: '14px 16px',
          borderRadius: 8,
          border: `1px solid ${C.green}`,
          color: C.green,
          fontSize: 13.5,
          lineHeight: 1.6,
        }}
      >
        {message}
      </p>
    );
  }

  return (
    <form onSubmit={submit}>
      <label
        htmlFor="identifier"
        style={{ display: 'block', color: C.muted, fontSize: 13, marginBottom: 8 }}
      >
        Email or mobile number
      </label>
      <input
        id="identifier"
        name="identifier"
        type="text"
        autoComplete="email"
        value={identifier}
        onChange={(e) => setIdentifier(e.target.value)}
        placeholder="you@example.com"
        style={{ ...inputStyle, fontFamily: MONO, marginBottom: 14 }}
      />

      <button
        type="submit"
        disabled={state === 'sending'}
        style={{
          ...buttonStyle,
          opacity: state === 'sending' ? 0.6 : 1,
          cursor: state === 'sending' ? 'default' : 'pointer',
        }}
      >
        {state === 'sending' ? 'Sending…' : 'Send activation link'}
      </button>

      {(state === 'limited' || state === 'error') && (
        <p
          style={{
            margin: '14px 0 0',
            padding: '12px 14px',
            borderRadius: 8,
            border: `1px solid ${state === 'limited' ? C.amber : C.red}`,
            color: state === 'limited' ? C.amber : C.red,
            fontSize: 13,
            lineHeight: 1.6,
          }}
        >
          {message}
        </p>
      )}
    </form>
  );
}
