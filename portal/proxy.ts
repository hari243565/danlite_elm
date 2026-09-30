// ══════════════════════════════════════════════════════════════════════════
// PROXY — runs before every request. Two jobs:
//
//   1. Refresh the Supabase session cookie. Server Components cannot write
//      response headers, so without this the access token would silently
//      expire and users would be logged out at unpredictable moments.
//   2. Apply X-Robots-Tag to EVERY response — search-invisibility layer 3.
//
// ── WHY THIS FILE IS NAMED proxy.ts AND NOT middleware.ts ────────────────
// Next.js 16 renamed Middleware to Proxy. From the installed docs at
// node_modules/next/dist/docs/.../file-conventions/middleware.md:
//   "The middleware.js file convention has been DEPRECATED in Next.js 16 and
//    renamed to proxy.js."
// The X-Robots-Tag layer depends entirely on this file being loaded by the
// framework, so using the deprecated name would risk the header silently not
// being applied — the exact failure this layer exists to prevent.
// ══════════════════════════════════════════════════════════════════════════

import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { siteUrl } from '@/lib/site-url';

/**
 * Layer 3 of search-invisibility. Applied to every matched route, including
 * API routes and error responses — not just the four main pages. This is the
 * layer that keeps working if a page is ever linked from somewhere unexpected,
 * because it does not depend on the crawler reading robots.txt first or
 * parsing the HTML body at all.
 */
const ROBOTS_HEADER = 'noindex, nofollow';

/**
 * The ONE exception to layer 3: the public policy pages under /legal, which
 * Razorpay's website review and Google Play need to be able to read. Matched
 * exactly (`/legal` or `/legal/...`), so `/legalese` or `/checkout?x=/legal`
 * still get the header. Nothing else about the request is treated differently.
 */
function isIndexablePath(path: string): boolean {
  return path === '/legal' || path.startsWith('/legal/');
}

/**
 * Routes that require a session.
 *
 * The pages themselves ALSO check, with getUser(), and that check remains the
 * authoritative one — this is defence in depth, not a replacement.
 *
 * The reason the redirect is issued here rather than being left to the pages:
 * when a Server Component throws redirect(), Next generates the 307 downstream
 * and the headers set on this proxy's NextResponse are not carried onto it, so
 * the X-Robots-Tag silently disappeared from exactly those responses. Owning
 * the redirect here keeps every response covered by layer 3.
 */
const PROTECTED_PREFIXES = ['/checkout', '/confirmation', '/account'];

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Session refresh is skipped when Supabase is unconfigured (e.g. a fresh
  // clone with no .env.local). The robots header below is NOT skipped — the
  // search-invisibility guarantee must not depend on configuration state.
  if (url && anonKey) {
    const supabase = createServerClient(url, anonKey, {
      cookieOptions: {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'lax',
        path: '/',
      },
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet, headers) {
          for (const { name, value } of cookiesToSet) {
            request.cookies.set(name, value);
          }
          response = NextResponse.next({ request });
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options);
          }
          // @supabase/ssr 0.12.x passes a second argument carrying
          // Cache-Control/Expires/Pragma no-store headers. Applying them is
          // required, not optional: a response that sets an auth cookie must
          // never be cached by a CDN or reverse proxy, or one customer's
          // session token gets served to a different customer. Cloudflare sits
          // in front of this portal in Part D, which makes it load-bearing.
          for (const [key, value] of Object.entries(headers)) {
            response.headers.set(key, value);
          }
        },
      },
    });

    // Must be awaited BEFORE the response is returned, so a refresh that
    // happens here can still be written into the outgoing cookies.
    // getUser() validates the JWT against the auth server rather than trusting
    // whatever the cookie claims, so this is a real check, not a guess.
    const {
      data: { user },
    } = await supabase.auth.getUser();

    const path = request.nextUrl.pathname;
    const needsSession = PROTECTED_PREFIXES.some(
      (prefix) => path === prefix || path.startsWith(`${prefix}/`),
    );

    if (needsSession && !user) {
      // NOT new URL(..., request.url) — see lib/site-url.ts. Behind the
      // reverse proxy request.url carries the internal bind address, which
      // would send a signed-out customer to https://0.0.0.0:3000/activate.
      const redirectResponse = NextResponse.redirect(siteUrl('/activate'));
      redirectResponse.headers.set('X-Robots-Tag', ROBOTS_HEADER);
      return redirectResponse;
    }
  }

  if (!isIndexablePath(request.nextUrl.pathname)) {
    response.headers.set('X-Robots-Tag', ROBOTS_HEADER);
  }
  return response;
}

export const config = {
  // Everything except Next's own build output and the favicon. Deliberately
  // broad — see ROBOTS_HEADER above. Note that robots.txt itself IS matched,
  // which is harmless and intentional.
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
