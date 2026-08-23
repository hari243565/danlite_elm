'use client';

// ══════════════════════════════════════════════════════════════════════════
// Admin login — email, then 6-digit code.
//
// ── ON THE WORDING OF THE ERRORS ─────────────────────────────────────────
// This form says exactly what went wrong. "This email is not authorized for
// admin access." is rendered verbatim, as the server sent it.
//
// That is the opposite of the billing portal's /activate form, which is
// deliberately ambiguous ("if that email matches an account…") because
// customers are an open population and confirming membership leaks a real
// person's private fact. The admin population is two or three known people,
// so there is nothing to leak — and a mistyped address that returns a
// friendly "check your email" would send an admin off to hunt through a spam
// folder for a message that was never sent.
//
// Do not "harmonise" this copy with the customer paywall's softer language.
// The difference is the design.
//
// NO TOKEN EVER TOUCHES THIS COMPONENT. Both submits post to same-origin
// route handlers; the session arrives as an httpOnly cookie this code cannot
// read.
// ══════════════════════════════════════════════════════════════════════════

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { buttonStyle, C, FONT, inputStyle, MONO } from '@/lib/theme';

type Stage = 'email' | 'code';

export function LoginForm() {
  const router = useRouter();
  const [stage, setStage] = useState<Stage>('email');
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function requestCode(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setNotice(null);

    try {
      const res = await fetch('/api/auth/request-otp', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email }),
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        // Rendered as sent — including the plain 403 and the 429.
        setError(data?.error ?? 'Could not send the sign-in code.');
        return;
      }

      setStage('code');
      setNotice(data?.message ?? 'A 6-digit code has been sent to your email.');
    } catch {
      setError('Could not reach the sign-in service.');
    } finally {
      setBusy(false);
    }
  }

  async function verifyCode(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);

    try {
      const res = await fetch('/api/auth/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, token: code }),
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        setError(data?.error ?? 'Sign-in failed.');
        return;
      }

      // The cookie is already set by the route handler at this point.
      // refresh() forces the Server Components to re-render with the new
      // session rather than serving the signed-out render from the router
      // cache.
      router.replace(data?.redirect ?? '/');
      router.refresh();
    } catch {
      setError('Could not reach the sign-in service.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={{ width: '100%', maxWidth: 380 }}>
      <h1 style={{ fontSize: 19, fontWeight: 800, margin: '0 0 5px' }}>
        Danlite ELM <span style={{ color: C.cyan }}>Admin</span>
      </h1>
      <p style={{ color: C.muted, fontSize: 13, lineHeight: 1.6, margin: '0 0 22px' }}>
        Internal tool. Access is limited to a fixed allowlist of addresses.
      </p>

      {stage === 'email' ? (
        <form onSubmit={requestCode}>
          <label
            htmlFor="email"
            style={{ display: 'block', color: C.muted, fontSize: 12, marginBottom: 7 }}
          >
            Admin email address
          </label>
          <input
            id="email"
            type="email"
            required
            autoComplete="email"
            autoFocus
            value={email}
            onChange={(ev) => setEmail(ev.target.value)}
            style={{ ...inputStyle, marginBottom: 14 }}
            placeholder="you@example.com"
          />
          <button type="submit" disabled={busy} style={{ ...buttonStyle, opacity: busy ? 0.6 : 1 }}>
            {busy ? 'Checking…' : 'Send sign-in code'}
          </button>
        </form>
      ) : (
        <form onSubmit={verifyCode}>
          <label
            htmlFor="code"
            style={{ display: 'block', color: C.muted, fontSize: 12, marginBottom: 7 }}
          >
            6-digit code sent to <span style={{ color: C.text }}>{email}</span>
          </label>
          <input
            id="code"
            type="text"
            inputMode="numeric"
            pattern="[0-9]*"
            maxLength={6}
            required
            autoFocus
            autoComplete="one-time-code"
            value={code}
            onChange={(ev) => setCode(ev.target.value.replace(/\D/g, ''))}
            style={{
              ...inputStyle,
              marginBottom: 14,
              fontFamily: MONO,
              fontSize: 21,
              letterSpacing: 7,
              textAlign: 'center',
            }}
            placeholder="000000"
          />
          <button type="submit" disabled={busy} style={{ ...buttonStyle, opacity: busy ? 0.6 : 1 }}>
            {busy ? 'Verifying…' : 'Sign in'}
          </button>
          <button
            type="button"
            onClick={() => {
              setStage('email');
              setCode('');
              setError(null);
              setNotice(null);
            }}
            style={{
              width: '100%',
              marginTop: 10,
              padding: '9px',
              background: 'none',
              border: 'none',
              color: C.muted,
              fontSize: 12.5,
              fontFamily: FONT,
              cursor: 'pointer',
            }}
          >
            Use a different address
          </button>
        </form>
      )}

      {notice && !error ? (
        <p
          style={{
            marginTop: 16,
            padding: '11px 13px',
            borderRadius: 8,
            border: `1px solid ${C.green}44`,
            backgroundColor: `${C.green}12`,
            color: C.green,
            fontSize: 12.5,
            lineHeight: 1.55,
          }}
        >
          {notice}
        </p>
      ) : null}

      {error ? (
        <p
          role="alert"
          style={{
            marginTop: 16,
            padding: '11px 13px',
            borderRadius: 8,
            border: `1px solid ${C.red}44`,
            backgroundColor: `${C.red}12`,
            color: C.red,
            fontSize: 12.5,
            lineHeight: 1.55,
          }}
        >
          {error}
        </p>
      ) : null}
    </div>
  );
}
