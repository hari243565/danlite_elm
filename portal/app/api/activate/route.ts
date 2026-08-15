// ══════════════════════════════════════════════════════════════════════════
// GET /api/activate?t=<raw_token> — redeems an activation token and lands the
// customer on the right page.
//
// ── WHY THIS ROUTE HANDLER EXISTS ────────────────────────────────────────
// The emailed link points at /activate?t=… as specified. That is a PAGE, and
// a Next.js Server Component page cannot write cookies — only Route Handlers
// and Server Actions can. Since the entire point of redeeming the token is to
// set a session cookie, the redemption has to happen here. app/activate/page
// therefore forwards to this handler when it sees a ?t=.
//
// The redirect at the end also strips the token out of the address bar, so a
// single-use credential does not linger in browser history or leak through a
// Referer header to any third party.
// ══════════════════════════════════════════════════════════════════════════

import { NextResponse, type NextRequest } from 'next/server';
import { cookies } from 'next/headers';
import { createClient, SESSION_COOKIE_OPTIONS } from '@/lib/supabase/server';
import { fetchEntitlement } from '@/lib/entitlement';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const token = request.nextUrl.searchParams.get('t');
  const origin = request.nextUrl.origin;

  // No token — nothing to redeem. Send them to the request-a-link form.
  if (!token) {
    return NextResponse.redirect(new URL('/activate', origin));
  }

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!base) {
    return NextResponse.redirect(new URL('/activate?e=1', origin));
  }

  let session: { access_token: string; refresh_token: string } | null = null;

  try {
    const res = await fetch(`${base}/functions/v1/verify-activation`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token }),
      cache: 'no-store',
    });

    if (res.ok) {
      const body = await res.json();
      if (body?.status === 'ok' && body.access_token && body.refresh_token) {
        session = { access_token: body.access_token, refresh_token: body.refresh_token };
      }
    }
  } catch {
    // Network failure talking to the Edge Function. Treated exactly like an
    // invalid token from the customer's point of view — see ?e=1 below.
  }

  if (!session) {
    // Generic failure. The page renders "invalid or has expired" and offers a
    // fresh link; it is never told which check actually failed.
    return NextResponse.redirect(new URL('/activate?e=1', origin));
  }

  // Install the session. setSession() drives the @supabase/ssr cookie writer,
  // which applies SESSION_COOKIE_OPTIONS — httpOnly, Secure in production,
  // SameSite=Lax. The tokens themselves are never rendered into any page.
  const supabase = await createClient();
  const { error: setErr } = await supabase.auth.setSession(session);
  if (setErr) {
    return NextResponse.redirect(new URL('/activate?e=1', origin));
  }

  // Ask the EXISTING /entitlement function where to send them. Reused, not
  // reimplemented — the portal has no opinion of its own about licences.
  const outcome = await fetchEntitlement(session.access_token);
  const destination =
    outcome.ok && outcome.entitlement.lic === 'active' ? '/account' : '/checkout';

  const response = NextResponse.redirect(new URL(destination, origin));

  // Belt and braces: mirror the auth cookies onto THIS response too. The
  // redirect is generated here rather than by the page, so relying solely on
  // the cookie jar mutation would be fragile across Next versions.
  const jar = await cookies();
  for (const cookie of jar.getAll()) {
    if (cookie.name.startsWith('sb-')) {
      response.cookies.set(cookie.name, cookie.value, SESSION_COOKIE_OPTIONS);
    }
  }

  return response;
}
