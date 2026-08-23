'use client';

// ══════════════════════════════════════════════════════════════════════════
// Sign out of the admin tool. A Client Component because it needs an onClick;
// it holds no session state and reads no token — it posts to the server-side
// route handler and follows the redirect.
// ══════════════════════════════════════════════════════════════════════════

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { C, FONT } from '@/lib/theme';

export function SignOutButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function signOut() {
    setBusy(true);
    try {
      await fetch('/api/auth/signout', { method: 'POST' });
    } finally {
      // Replace, not push: the signed-in pages must not be reachable with the
      // browser Back button after signing out. They would bounce to /login
      // anyway (the proxy sees no session), but flashing customer data from
      // the bfcache on the way there is not acceptable on this tool.
      router.replace('/login');
      router.refresh();
    }
  }

  return (
    <button
      type="button"
      onClick={signOut}
      disabled={busy}
      style={{
        padding: '6px 13px',
        borderRadius: 8,
        border: `1px solid ${C.border}`,
        backgroundColor: 'transparent',
        color: C.muted,
        fontSize: 12,
        fontWeight: 600,
        fontFamily: FONT,
        cursor: busy ? 'default' : 'pointer',
      }}
    >
      {busy ? 'Signing out…' : 'Sign out'}
    </button>
  );
}
