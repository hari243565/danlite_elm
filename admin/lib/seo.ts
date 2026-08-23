// ══════════════════════════════════════════════════════════════════════════
// Search-invisibility, layer 2 of 3.
//
// The same three-layer model the billing portal uses:
//
//   1. app/robots.ts  — Disallow: / for every crawler.
//   2. THIS FILE      — <meta name="robots" content="noindex, nofollow,
//                       noarchive"> on every page, via the Metadata API.
//   3. proxy.ts       — X-Robots-Tag response header on every route.
//
// ── WHY THIS MATTERS MORE HERE THAN ON THE BILLING PORTAL ────────────────
// A leaked billing-portal URL exposes, at worst, one signed-in customer's own
// data — and only to someone who already has that customer's session. A
// leaked admin URL is a login page for a tool that renders EVERY customer's
// email, phone, payment history and device list on one screen.
//
// The layers are not the access control — the allowlist is, and it is
// re-checked inside every Edge Function on every request. These three layers
// exist so the login page never turns up in a search result in the first
// place, because an attacker who never finds the door never gets to test the
// lock.
//
// Exported as ONE shared constant deliberately: six pages each hand-rolling
// their own robots block is six chances for one of them to be wrong.
// ══════════════════════════════════════════════════════════════════════════

import type { Metadata } from 'next';

export const NOINDEX: Metadata['robots'] = {
  index: false,
  follow: false,
  noarchive: true,
  nocache: true,
  googleBot: {
    index: false,
    follow: false,
    noarchive: true,
  },
};
