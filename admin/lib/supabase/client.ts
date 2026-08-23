// ══════════════════════════════════════════════════════════════════════════
// Browser-side Supabase client for the ADMIN portal.
//
// ── READ THIS BEFORE USING IT ────────────────────────────────────────────
// Nothing in this app currently calls createClient(). That is intentional,
// and it is worth stating loudly because the obvious "improvement" is to
// start using it.
//
// The admin portal's entire session design is that the browser NEVER holds a
// token:
//
//   • The login form posts an email and a 6-digit code to this app's own
//     route handlers (app/api/auth/*), which are server-side.
//   • Those handlers call the admin Edge Functions, receive the token pair
//     server-to-server, and write it into httpOnly cookies the page cannot
//     read.
//   • Every page then reads customer data in a Server Component, forwarding
//     that cookie's access token to an Edge Function.
//
// If a Client Component ever calls supabase.auth here, the session moves
// into JS-reachable storage and that guarantee is gone — an XSS bug would
// escalate from "act as the admin until the tab closes" to "walk off with a
// refresh token that opens every customer record".
//
// This file exists because @supabase/ssr's browser half is part of the
// established pattern this app was asked to copy, and because a future phase
// with realtime or optimistic UI may legitimately need it. Until then it is
// documented, unused, and should stay that way for auth.
// ══════════════════════════════════════════════════════════════════════════

import { createBrowserClient } from '@supabase/ssr';

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
