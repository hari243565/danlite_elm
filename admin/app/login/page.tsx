// ══════════════════════════════════════════════════════════════════════════
// /login — the only route in this app reachable without a session.
//
// The redirect for an already-signed-in visitor lives in proxy.ts, not here,
// so that the response carrying it keeps its X-Robots-Tag header (a redirect
// thrown from a Server Component is generated downstream of the proxy's
// response object and loses headers set on it).
// ══════════════════════════════════════════════════════════════════════════

import type { Metadata } from 'next';
import { C, pageStyle } from '@/lib/theme';
import { NOINDEX } from '@/lib/seo';
import { LoginForm } from './login-form';

export const metadata: Metadata = {
  title: 'Sign in — Danlite ELM Admin',
  robots: NOINDEX,
};

export default function LoginPage() {
  return (
    <div
      style={{
        ...pageStyle,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '48px 20px',
        boxSizing: 'border-box',
      }}
    >
      <div
        style={{
          backgroundColor: C.surface,
          border: `1px solid ${C.border}`,
          borderRadius: 12,
          padding: 28,
          width: '100%',
          maxWidth: 420,
        }}
      >
        <LoginForm />
      </div>
    </div>
  );
}
