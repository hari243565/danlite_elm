// ══════════════════════════════════════════════════════════════════════════
// Client for the EXISTING /entitlement Edge Function (Phase 3).
//
// Deliberately a thin caller and nothing more. The portal does NOT reimplement
// the licence-status decision, does not read the licences table to second-guess
// it, and does not verify the Ed25519 signature. There is exactly one authority
// on whether somebody holds a licence, and this is not it.
//
// A useful side effect: every /account page load is an independent live test
// that Phase 3's function still works from a client other than the Flutter app.
// ══════════════════════════════════════════════════════════════════════════

export type Entitlement = {
  /** 'active' | 'inactive' | 'revoked' | 'refunded' */
  lic: string;
  sub: string;
  iat: number;
  exp: number;
  sig: string;
  alg?: string;
};

export type EntitlementOutcome =
  | { ok: true; entitlement: Entitlement }
  | { ok: false; reason: string };

/**
 * @param accessToken the signed-in user's Supabase JWT. /entitlement derives
 *        the user id from this token and never from a request body, so there
 *        is nothing else to pass and nothing here that could name another user.
 */
export async function fetchEntitlement(accessToken: string): Promise<EntitlementOutcome> {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!base) return { ok: false, reason: 'supabase_url_not_configured' };

  try {
    const res = await fetch(`${base}/functions/v1/entitlement`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
      // Licence status is the one thing that must never be served from a cache.
      cache: 'no-store',
    });

    if (!res.ok) {
      return { ok: false, reason: `entitlement_http_${res.status}` };
    }

    const body = (await res.json()) as Entitlement;
    if (typeof body?.lic !== 'string') {
      return { ok: false, reason: 'entitlement_malformed' };
    }
    return { ok: true, entitlement: body };
  } catch (e) {
    return { ok: false, reason: e instanceof Error ? e.message : 'entitlement_unreachable' };
  }
}
