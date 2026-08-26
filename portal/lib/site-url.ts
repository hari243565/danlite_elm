// ══════════════════════════════════════════════════════════════════════════
// The portal's own public address, for building absolute URLs.
//
// WHY THIS EXISTS AT ALL — a real outage, not a hypothetical:
//
// Every redirect in this app used to be built from the incoming request:
// `new URL('/activate', request.url)`, or `request.nextUrl.origin`. That is
// the pattern Next's own documentation shows, and it is correct right up
// until something sits in front of the server.
//
// This portal is deployed on Hostinger, behind a reverse proxy. Next therefore
// sees its own internal bind address rather than the public host, and every
// absolute URL it derived from the request came out as:
//
//   https://0.0.0.0:3000/activate?e=1
//
// which resolves to nothing at all. A customer clicking a perfectly valid
// activation link had their session cookie set correctly and was then handed
// a dead address — the failure landed on the last step of the flow, after
// payment, where it looks most like the product is broken.
//
// A request-derived origin is only ever as trustworthy as the hop in front of
// it. The public address of this portal is a fact about the deployment, not
// something to be re-derived from each request, so it is read from
// configuration and nothing else.
//
// NOTE ON DEPLOYMENT: NEXT_PUBLIC_* values are inlined at BUILD time, not read
// at runtime. NEXT_PUBLIC_BILLING_DOMAIN must therefore be set in the build
// environment on Hostinger — setting it only at runtime has no effect, and the
// localhost default below would silently ship instead.
// ══════════════════════════════════════════════════════════════════════════

/** Documented in .env.local.example: the default when nothing is configured. */
const DEV_FALLBACK = 'http://localhost:3000';

/**
 * The portal's public origin, with any trailing slashes removed.
 *
 * Normalised the same way `send-activation` normalises its own BILLING_DOMAIN
 * secret, so a value copied between the two behaves identically in both.
 */
export function siteOrigin(): string {
  const configured = process.env.NEXT_PUBLIC_BILLING_DOMAIN?.trim();
  if (!configured) return DEV_FALLBACK;
  return configured.replace(/\/+$/, '');
}

/**
 * Absolute URL for a path on this portal.
 *
 * @param path a root-relative path, e.g. `/activate?e=1`.
 */
export function siteUrl(path: string): URL {
  return new URL(path, siteOrigin());
}
