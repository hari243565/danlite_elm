// ══════════════════════════════════════════════════════════════════════════
// POST /api/auth/request-otp — step 1 of admin login, from this app's side.
//
// A thin server-side proxy to the admin-request-otp Edge Function. It exists
// rather than having the browser call the function directly for one reason:
// the browser then never needs the Supabase URL or anon key in its bundle for
// auth purposes, and the whole login exchange stays same-origin. Less
// surface, no CORS, nothing for a page script to intercept.
//
// The Edge Function is the authority on the allowlist and the rate limit.
// This handler adds nothing and decides nothing — it forwards the answer,
// including the status code, verbatim.
// ══════════════════════════════════════════════════════════════════════════

import { NextResponse } from 'next/server';

export async function POST(request: Request) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) {
    return NextResponse.json({ error: 'Admin portal is not configured.' }, { status: 500 });
  }

  const body = await request.json().catch(() => ({}));
  const email = typeof body?.email === 'string' ? body.email : '';

  if (!email.trim()) {
    return NextResponse.json({ error: 'Enter your admin email address.' }, { status: 400 });
  }

  try {
    const res = await fetch(`${url}/functions/v1/admin-request-otp`, {
      method: 'POST',
      cache: 'no-store',
      headers: { 'Content-Type': 'application/json', apikey: anon },
      body: JSON.stringify({ email }),
    });

    const payload = await res.json().catch(() => ({ error: 'Unexpected response.' }));

    // Status forwarded as-is. The 403 for a non-allowlisted address is the
    // honest rejection this tool is specified to give, and softening it here
    // into a 200 "check your email" would undo the entire design decision.
    return NextResponse.json(payload, { status: res.status });
  } catch (err) {
    console.error(
      'admin-request-otp proxy failed:',
      err instanceof Error ? err.message : String(err),
    );
    return NextResponse.json({ error: 'Could not reach the sign-in service.' }, { status: 502 });
  }
}
