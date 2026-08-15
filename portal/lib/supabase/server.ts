// ══════════════════════════════════════════════════════════════════════════
// Server-side Supabase client for the billing portal.
//
// Kept as close to the @supabase/ssr reference implementation as possible —
// this is plumbing, and clever plumbing is how sessions break. Written against
// the INSTALLED package (@supabase/ssr 0.12.4), whose current contract is the
// getAll/setAll cookie pair; the older get/set/remove trio is deprecated in
// this version and is documented to cause "random logouts, early session
// termination, JSON parsing errors".
//
// NOTE ON PRIVILEGE: this portal NEVER holds the service-role key. Every read
// it performs (profiles.country_code, payments, licences) happens as the
// signed-in user and is therefore constrained by the Phase 1 RLS policies. The
// only components that hold service_role are the Edge Functions. A full
// compromise of this Next.js app cannot read another customer's row.
// ══════════════════════════════════════════════════════════════════════════

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

/** Fails loudly at call time rather than silently producing a broken client. */
function requiredEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    throw new Error(
      `${name} is not set. Copy portal/.env.local.example to portal/.env.local and fill it in.`,
    );
  }
  return v;
}

/**
 * Session cookie policy — the Step 6 requirement, stated explicitly rather
 * than inherited from library defaults so it cannot drift with a version bump.
 *
 *   httpOnly  JavaScript in the page cannot read the session. An XSS bug can
 *             then act as the user but cannot exfiltrate the refresh token to
 *             a server the attacker controls, which is the difference between
 *             a session hijack and a permanent account takeover.
 *   secure    Production only. Left off for http://localhost so the flow is
 *             testable today, before a real domain exists.
 *   sameSite  'lax' — the activation link is a cross-site top-level GET
 *             navigation from an email client, which 'lax' permits and
 *             'strict' would break by dropping the cookie on arrival.
 */
export const SESSION_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'lax' as const,
  path: '/',
};

/**
 * One client per request. Never cache or share this across requests — it
 * carries the caller's session.
 */
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
