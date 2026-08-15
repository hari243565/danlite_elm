// ══════════════════════════════════════════════════════════════════════════
// In-process rate limiter for the portal's own API routes. SERVER ONLY —
// never import this from a Client Component; the map below must not be
// shipped to a browser, where it would be both useless and bypassable.
//
// ── HONEST SCOPE ─────────────────────────────────────────────────────────
// This is a SECOND layer, not the primary one, and it is important to be
// precise about what it does and does not do:
//
//   • State lives in the memory of one server process. Two instances behind a
//     load balancer keep two independent counters, so the effective limit is
//     N x the configured limit. A restart clears it entirely.
//   • It is therefore NOT the defence for activation requests. That one is
//     DB-backed (public.activation_requests), shared across every instance,
//     and survives restarts — see supabase/functions/send-activation.
//   • Cloudflare (Part D, deferred) is a third layer at the network edge.
//
// What it IS good for: cheaply absorbing a burst against a single instance
// before that burst reaches anything expensive, with no external dependency.
// The task requires a code-level limiter that does not depend on Cloudflare
// being configured; this satisfies that for the portal's own routes.
// ══════════════════════════════════════════════════════════════════════════

// NOTE: the `server-only` package would enforce the "server only" rule above
// at build time, but adding it is outside this phase's dependency budget
// (@supabase/ssr only). The module is imported exclusively by route handlers,
// which never ship to the browser. If `server-only` is ever added to the
// project, import it here and the rule becomes machine-checked.

type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();

/** Bounds memory: a hostile caller cycling keys must not grow the map forever. */
const MAX_TRACKED_KEYS = 10_000;

function sweep(now: number) {
  for (const [key, bucket] of buckets) {
    if (bucket.resetAt <= now) buckets.delete(key);
  }
}

export type RateLimitResult = {
  ok: boolean;
  /** Requests still available in the current window. */
  remaining: number;
  /** Seconds until the window resets — suitable for a Retry-After header. */
  retryAfterSeconds: number;
};

/**
 * Fixed-window counter.
 *
 * @param key      Caller identity. Use an IP, or better, a hash of one.
 * @param limit    Requests permitted per window.
 * @param windowMs Window length in milliseconds.
 */
export function rateLimit(key: string, limit: number, windowMs: number): RateLimitResult {
  const now = Date.now();

  if (buckets.size > MAX_TRACKED_KEYS) sweep(now);

  const existing = buckets.get(key);

  if (!existing || existing.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return { ok: true, remaining: limit - 1, retryAfterSeconds: Math.ceil(windowMs / 1000) };
  }

  existing.count += 1;
  const retryAfterSeconds = Math.max(1, Math.ceil((existing.resetAt - now) / 1000));

  if (existing.count > limit) {
    return { ok: false, remaining: 0, retryAfterSeconds };
  }

  return { ok: true, remaining: limit - existing.count, retryAfterSeconds };
}

/**
 * Best-effort client IP from proxy headers.
 *
 * These headers are attacker-controlled unless a trusted proxy overwrites
 * them, so this value is fine for rate limiting (worst case, an attacker
 * spreads their own requests across buckets) and must NEVER be used for
 * authorisation or audit. Behind Cloudflare, CF-Connecting-IP is the
 * trustworthy one and is checked first.
 */
export function clientIpFrom(headers: Headers): string {
  return (
    headers.get('cf-connecting-ip') ??
    headers.get('x-real-ip') ??
    headers.get('x-forwarded-for')?.split(',')[0]?.trim() ??
    'unknown'
  );
}
