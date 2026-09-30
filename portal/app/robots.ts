// ══════════════════════════════════════════════════════════════════════════
// Search-invisibility, layer 1 of 3 — see portal/lib/seo.ts for the full model.
//
// MECHANISM: the Next.js Metadata Files API (app/robots.ts), which is the
// canonical convention in the installed version (16.3.0) per
// node_modules/next/dist/docs/.../file-conventions/metadata/robots.md.
// Next generates /robots.txt from this at build time.
//
// Disallow: / for every user agent. No sitemap is emitted — publishing a
// sitemap for a site you want unlisted is self-defeating.
//
// ONE EXCEPTION: /legal (the policy pages). Razorpay's website review and
// Google Play both need them reachable and readable, so they are allowed.
// Crawlers that follow the standard pick the most specific (longest) rule,
// so Allow: /legal wins for /legal/* and Disallow: / still covers everything
// else. proxy.ts and the pages' own metadata make the matching exception.
// ══════════════════════════════════════════════════════════════════════════

import type { MetadataRoute } from 'next';

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: '*',
      allow: '/legal',
      disallow: '/',
    },
  };
}
