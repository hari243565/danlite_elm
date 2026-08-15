// ══════════════════════════════════════════════════════════════════════════
// Search-invisibility, layer 2 of 3.
//
// The commercial model depends on this portal being reachable by customers who
// are handed a link, and effectively invisible to everyone else. Three
// independent layers enforce that, so no single mistake exposes the site:
//
//   1. app/robots.ts       — Disallow: / for every crawler.
//   2. THIS FILE           — <meta name="robots" content="noindex, nofollow,
//                            noarchive"> on every page, via the Metadata API.
//   3. proxy.ts            — X-Robots-Tag response header on every route.
//
// Layer 1 is a request not to look. Layer 2 only works if the crawler fetches
// and parses the HTML. Layer 3 is the one that still applies to non-HTML
// responses and to pages reached from an unexpected inbound link.
//
// Exported as ONE shared constant deliberately: seven pages each hand-rolling
// their own robots block is seven chances for one of them to be wrong.
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
