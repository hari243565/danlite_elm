// ══════════════════════════════════════════════════════════════════════════
// POST /api/create-order — INTENTIONALLY NOT IMPLEMENTED.
//
// Returns 501 Not Implemented. This is a placeholder, and it says so in its
// status code rather than pretending.
//
// PHASE 5/6 REPLACES THE BODY OF THIS HANDLER with real Razorpay order
// creation. When that happens it must:
//   • create the order server-side with the amount taken from lib/gst.ts and
//     the country read from public.profiles — never from the request body, or
//     a customer can name their own price;
//   • record the order against the signed-in user;
//   • leave licence activation to the webhook handler, which verifies the
//     Razorpay HMAC signature. A browser callback saying "payment succeeded"
//     is not evidence of payment.
//
// Until then, returning a fake order id here would produce a checkout that
// appears to work and silently takes no money.
// ══════════════════════════════════════════════════════════════════════════

import { NextResponse } from 'next/server';
import { headers } from 'next/headers';
import { rateLimit, clientIpFrom } from '@/lib/rate-limit';

export const dynamic = 'force-dynamic';

/** Deliberately tight. Nothing legitimate calls this more than a few times. */
const MAX_REQUESTS = 10;
const WINDOW_MS = 60_000;

export async function POST() {
  // Wired up now rather than "later" so the limiter is exercised from the day
  // the real Razorpay call lands here, instead of being added under pressure
  // once the endpoint is already taking money.
  const ip = clientIpFrom(await headers());
  const limit = rateLimit(`create-order:${ip}`, MAX_REQUESTS, WINDOW_MS);

  if (!limit.ok) {
    return NextResponse.json(
      { status: 'rate_limited', message: 'Too many attempts. Please wait a moment.' },
      { status: 429, headers: { 'Retry-After': String(limit.retryAfterSeconds) } },
    );
  }

  return NextResponse.json(
    {
      status: 'not_yet_available',
      message: 'Checkout opens soon.',
    },
    { status: 501 },
  );
}
