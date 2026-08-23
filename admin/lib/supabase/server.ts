// ══════════════════════════════════════════════════════════════════════════
// Server-side Supabase client for the ADMIN portal.
//
// ── WHY THIS IS A COPY AND NOT AN IMPORT ─────────────────────────────────
// The billing portal has a near-identical file. It is deliberately NOT
// imported here, and this app is deliberately not part of a shared package
// with it. Two reasons, both about blast radius:
//
//   1. These two apps have opposite threat models. The billing portal holds
//      a session scoped to ONE customer and is constrained by RLS. This app
//      holds a session that can reach EVERY customer's data. A shared module
//      means a change made for the customer portal's convenience silently
//      alters the cookie handling of the tool that sees everything.
//   2. A cross-app relative import (`../../portal/lib/...`) would put the
//      billing portal's source inside this app's build graph, and vice
//      versa. Deploying one would mean rebuilding both, and a broken portal
//      build would take the admin tool down with it — precisely when you
//      most want the admin tool working.
//
// The duplication is nine lines of cookie plumbing. That is a cheap price
// for two independently deployable apps.
//
// ── PRIVILEGE ────────────────────────────────────────────────────────────
// This client uses the ANON key. This app never holds service_role. Every
// piece of customer data on every page arrives from an admin Edge Function
// that re-checked the allowlist for that specific request.
// ══════════════════════════════════════════════════════════════════════════

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

/** Fails loudly at call time rather than silently producing a broken client. */
function requiredEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    throw new Error(
      `${name} is not set. Copy admin/.env.local.example to admin/.env.local and fill it in.`,
    );
  }
  return v;
}

/**
 * Session cookie policy — stated explicitly rather than inherited from
 * library defaults so it cannot drift with a version bump.
 *
 *   httpOnly  Page JavaScript cannot read the session. This matters more
 *             here than on the billing portal: the token this cookie carries
 *             is the one that opens every customer record, so an XSS bug
 *             must not be able to exfiltrate it to an attacker's server.
 *   secure    Production only. Left off for http://localhost so the flow is
 *             testable before a real domain exists.
 *   sameSite  'lax'. There is no cross-site entry point into this app at all
 *             — no email links, no gateway redirects — so 'strict' would
 *             also work. 'lax' matches the billing portal and the brief, and
 *             the difference is immaterial when nothing links here.
 */
export const SESSION_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'lax' as const,
  path: '/',
};

/** One client per request. Never cache or share this — it carries a session. */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    requiredEnv('NEXT_PUBLIC_SUPABASE_URL'),
    requiredEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY'),
    {
      cookieOptions: SESSION_COOKIE_OPTIONS,
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Thrown when called from a Server Component, where the response
            // headers are already committed. Safe to ignore: proxy.ts runs on
            // every request and performs the refresh write there instead.
            // This is the documented reference behaviour, not a swallowed bug.
          }
        },
      },
    },
  );
}
