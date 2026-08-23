// ══════════════════════════════════════════════════════════════════════════
// Search-invisibility, layer 1 of 3 — see admin/lib/seo.ts for the full model.
//
// MECHANISM: the Next.js Metadata Files API (app/robots.ts), the canonical
// convention in the installed version (16.3.0) per
// node_modules/next/dist/docs/.../file-conventions/metadata/robots.md.
// Next generates /robots.txt from this at build time.
//
// Disallow: / for every user agent, with no exceptions and no sitemap. A
// sitemap for a site you want unlisted is self-defeating; on a tool that
// renders every customer's data it would be an index of exactly the pages
// that must never be indexed.
// ══════════════════════════════════════════════════════════════════════════

import type { MetadataRoute } from 'next';

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: '*',
      disallow: '/',
    },
  };
}
