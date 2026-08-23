// ══════════════════════════════════════════════════════════════════════════
// PROXY — runs before every request into the admin portal. Three jobs:
//
//   1. Refresh the Supabase session cookie. Server Components cannot write
//      response headers, so without this the access token would silently
//      expire and the admin would be logged out at unpredictable moments.
//   2. Redirect unauthenticated requests to /login, and bounce an
//      already-signed-in admin away from /login.
//   3. Apply X-Robots-Tag to EVERY response — search-invisibility layer 3.
//
// ── WHY THIS FILE IS NAMED proxy.ts AND NOT middleware.ts ────────────────
// Verified against the INSTALLED Next.js (16.3.0), not assumed. From
// node_modules/next/dist/docs/.../file-conventions/middleware.md:
//   "The middleware.js file convention has been DEPRECATED in Next.js 16 and
//    renamed to proxy.js."
// The billing portal resolved this the same way and its file is proxy.ts
// too. Getting this wrong would not be a loud error — the file would simply
// never load, taking the X-Robots-Tag layer and the login redirect with it.
//
// ── WHAT THIS FILE IS *NOT* ──────────────────────────────────────────────
// It is NOT the access control for customer data. It only knows whether a
// valid Supabase session exists — it does not, and deliberately cannot,
// check the admin allowlist. Any Supabase user in the project (i.e. any
// Danlite customer) can hold a valid session and would pass the check below.
//
// The real gate is inside every admin-* Edge Function, which re-reads
// public.admin_users on every single call. This proxy exists to give a
// signed-out person a login page instead of a broken screen, and to keep the
// robots header on every response. If it were ever bypassed entirely, the
// pages would render but every one of them would show an authorization
// error, because the data never arrives without passing the real gate.
// ══════════════════════════════════════════════════════════════════════════

import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

/**
 * Layer 3 of search-invisibility. Applied to every matched route, including
 * API routes and error responses. This is the layer that keeps working if a
 * page is ever linked from somewhere unexpected, because it does not depend
 * on the crawler reading robots.txt first or parsing the HTML body at all.
 *
 * `noarchive` is included alongside noindex/nofollow so that a crawler which
 * fetched a page before this was deployed cannot keep serving a cached copy
 * of an admin screen from its own index.
 */
const ROBOTS_HEADER = 'noindex, nofollow, noarchive';

/**
 * Routes reachable without a session. Everything else is customer data.
 *
 * This is an ALLOWLIST, not a blocklist of protected prefixes: on a tool
 * where every page is sensitive, a page added next month must default to
 * protected rather than depending on somebody remembering to protect it.
 * (The billing portal can safely use a blocklist — most of its pages are
 * public marketing and legal text. Here, none are.)
 *
 * /robots.txt IS ON THIS LIST, AND THAT IS NOT A HOLE. Caught by the header
 * check in Step 7: default-protected swept up robots.txt too, so a crawler
 * asking for the rules got a 307 to /login and never saw a single Disallow
 * line — search-invisibility layer 1 was silently dead while appearing to
 * be configured. The file's entire content is "Disallow: /", which tells an
 * attacker nothing they could not learn by requesting any other path, and
 * serving it is the whole point of layer 1. Layer 3 still stamps
 * X-Robots-Tag on it regardless.
 */
const PUBLIC_PATHS = ['/login', '/robots.txt'];

function isPublic(path: string): boolean {
  return PUBLIC_PATHS.some((p) => path === p || path.startsWith(`${p}/`));
}

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const path = request.nextUrl.pathname;

  // The auth route handlers manage their own cookies and must be reachable
  // while signed out — that is how signing in happens at all.
  const isAuthApi = path.startsWith('/api/auth/');

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Session handling is skipped when Supabase is unconfigured (e.g. a fresh
  // clone with no .env.local). The robots header below is NOT skipped — the
  // search-invisibility guarantee must not depend on configuration state.
  if (url && anonKey && !isAuthApi) {
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
          // never be cached by a CDN or reverse proxy, or one session token
          // gets served to a different person.
          for (const [key, value] of Object.entries(headers)) {
            response.headers.set(key, value);
          }
        },
      },
    });

    // Awaited BEFORE the response is returned, so a refresh that happens here
    // can still be written into the outgoing cookies. getUser() validates the
    // JWT against the auth server rather than trusting the cookie's claims.
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user && !isPublic(path)) {
      // The redirect is issued HERE rather than left to the pages: when a
      // Server Component throws redirect(), Next generates the 307 downstream
      // and headers set on this proxy's NextResponse are not carried onto it,
      // so X-Robots-Tag would silently vanish from exactly those responses.
      const redirectResponse = NextResponse.redirect(new URL('/login', request.url));
      redirectResponse.headers.set('X-Robots-Tag', ROBOTS_HEADER);
      return redirectResponse;
    }

    if (user && path === '/login') {
      const redirectResponse = NextResponse.redirect(new URL('/', request.url));
      redirectResponse.headers.set('X-Robots-Tag', ROBOTS_HEADER);
      return redirectResponse;
    }
  }

  response.headers.set('X-Robots-Tag', ROBOTS_HEADER);
  return response;
}

export const config = {
  // Everything except Next's own build output and the favicon. Deliberately
  // broad — see ROBOTS_HEADER above. Note that robots.txt itself IS matched,
  // which is harmless and intentional.
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
