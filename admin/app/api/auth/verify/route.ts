// ══════════════════════════════════════════════════════════════════════════
// POST /api/auth/verify — step 2 of admin login. THE COOKIE IS SET HERE.
//
// This is the hinge of the admin session design, so it is worth being
// explicit about what happens and why:
//
//   1. The browser posts { email, token } to this same-origin handler.
//   2. This handler (server-side) calls admin-verify-otp, which re-checks the
//      allowlist and verifies the 6-digit code with Supabase Auth.
//   3. The Edge Function returns { access_token, refresh_token } over HTTPS
//      to THIS SERVER — never to the browser.
//   4. setSession() on the @supabase/ssr server client writes them into
//      httpOnly + Secure + SameSite=Lax cookies via lib/supabase/server.ts.
//   5. The browser receives Set-Cookie and nothing else. The response body
//      deliberately carries no token.
//
// The result is that the refresh token — the credential that can mint access
// to every customer record for as long as it lives — never exists anywhere
// page JavaScript can reach. The common alternative (verify in the browser,
// call setSession() client-side) puts it in JS-reachable storage, which
// turns any XSS bug in this tool into a durable, silent breach of the entire
// customer database rather than a bounded session hijack.
//
// Verified against the installed @supabase/ssr 0.12.4 and supabase-js
// 2.112.3: setSession({ access_token, refresh_token }) is the current API,
// and the client's configured cookieOptions are what the resulting
// Set-Cookie headers use.
// ══════════════════════════════════════════════════════════════════════════

import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export async function POST(request: Request) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) {
    return NextResponse.json({ error: 'Admin portal is not configured.' }, { status: 500 });
  }

  const body = await request.json().catch(() => ({}));
  const email = typeof body?.email === 'string' ? body.email : '';
  const token = typeof body?.token === 'string' ? body.token : '';

  if (!email.trim() || !token.trim()) {
    return NextResponse.json({ error: 'Enter the 6-digit code.' }, { status: 400 });
  }

  try {
    const res = await fetch(`${url}/functions/v1/admin-verify-otp`, {
      method: 'POST',
      cache: 'no-store',
      headers: { 'Content-Type': 'application/json', apikey: anon },
      body: JSON.stringify({ email, token }),
    });

    const payload = await res.json().catch(() => ({ error: 'Unexpected response.' }));

    if (!res.ok || !payload?.access_token || !payload?.refresh_token) {
      return NextResponse.json(
        { error: payload?.error ?? 'Sign-in failed.' },
        { status: res.ok ? 502 : res.status },
      );
    }

    // Writes the httpOnly session cookies. Any failure here must NOT be
    // reported as a successful login: the browser would navigate to a page
    // that immediately bounces back to /login with no explanation.
    const supabase = await createClient();
    const { error: setErr } = await supabase.auth.setSession({
      access_token: payload.access_token,
      refresh_token: payload.refresh_token,
    });

    if (setErr) {
      console.error('admin setSession failed:', setErr.message);
      return NextResponse.json({ error: 'Could not start your session.' }, { status: 500 });
    }

    // Note what is NOT in this body: no tokens. The browser gets a redirect
    // target and the confirmed address, nothing it could store or leak.
    return NextResponse.json({ status: 'ok', email: payload.email, redirect: '/' });
  } catch (err) {
    console.error(
      'admin-verify-otp proxy failed:',
      err instanceof Error ? err.message : String(err),
    );
    return NextResponse.json({ error: 'Could not reach the sign-in service.' }, { status: 502 });
  }
}
