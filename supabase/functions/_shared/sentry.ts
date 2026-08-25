// ══════════════════════════════════════════════════════════════════════════
// _shared/sentry.ts — error reporting for the Edge Functions (Phase 9)
//
// ONE copy, imported by all seven functions. Not duplicated per function,
// because the PII settings below are the whole point of this file and they
// must not be able to drift apart between one function and the next.
//
// TWO RULES, the same two the Flutter side follows:
//
//   1. It never changes behaviour. Every export swallows its own failures.
//      A function's error boundary calls in here AFTER it has already decided
//      its status code and response body; nothing here can alter either. If
//      SENTRY_DSN is unset, every export is a no-op and the functions behave
//      exactly as they did before this file existed.
//
//   2. It never forwards PII. See the PII CONTROLS block below — this is the
//      part that needed reading the SDK rather than trusting the docs.
//
// PII CONTROLS — verified against @sentry/deno 10.71.0, not assumed:
//
//   • `sendDefaultPii: false` is the documented switch, and in v10 it maps to
//     a `dataCollection` shape with `httpBodies: []` — body collection off,
//     `userInfo: false`, and deny-lists on cookies, headers and query params.
//     (See core/utils/data-collection/defaultPiiToCollectionOptions.)
//     It is ALREADY the default; it is set explicitly so a reader can see it
//     was decided.
//
//     ⚠ `sendDefaultPii` is DEPRECATED in v10 and is removed in v11, replaced
//     by the finer-grained `dataCollection` option. It is deliberately NOT
//     paired with `dataCollection` here: when both are set, `sendDefaultPii`
//     is IGNORED. Whoever upgrades to v11 must replace it with
//     `dataCollection: { userInfo: false, httpBodies: [], ... }` — and until
//     they do, adding a `dataCollection` block would silently switch this
//     setting off.
//
//   • `maxRequestBodySize: 'none'` on the HTTP integration is a SEPARATE
//     control with its own default of **'medium'** — i.e. permissive. This is
//     the one that matters most here: `razorpay-webhook` and `send-activation`
//     receive bodies containing a customer's email address and phone number,
//     and on the default setting those bodies would be attached to events.
//     Passing a same-named integration replaces the default instance.
//
// Together those two make body capture off by category AND capped at zero
// bytes. Belt and braces, on purpose, because the failure mode is silent.
// ══════════════════════════════════════════════════════════════════════════

import * as Sentry from "npm:@sentry/deno@10.71.0";

const DSN = (Deno.env.get("SENTRY_DSN") ?? "").trim();

let enabled = false;

if (DSN) {
  try {
    Sentry.init({
      dsn: DSN,
      sendDefaultPii: false,
      // No performance tracing server-side. These functions are short,
      // synchronous request/response handlers; tracing them would spend the
      // free-tier allowance on data nobody reads, and the Flutter client
      // already samples the user-visible latency at 5%.
      tracesSampleRate: 0,
      environment: "production",
      integrations: [
        Sentry.denoHttpIntegration({
          maxRequestBodySize: "none",
          breadcrumbs: false,
        }),
      ],
      beforeSend(event) {
        // ── IP ADDRESS — READ THIS BEFORE TRUSTING `sendDefaultPii: false` ──
        //
        // `sendDefaultPii: false` does NOT stop an IP address reaching Sentry.
        // Observed, not assumed: the first deployment of this helper produced an
        // event tagged `user: ip:2406:da1a:…` with a "Mumbai, India"
        // geolocation, with sendDefaultPii already false.
        //
        // @sentry/core's own source (utils/ipAddress.ts) says *"By default, we
        // want to infer the IP address, unless this is explicitly set to null"*,
        // so the two lines below set it explicitly rather than deleting
        // `event.user` — deleting it would leave the field absent, which means
        // "infer at ingest" and would put the IP straight back.
        //
        // ⚠ THIS ALONE DID NOT WORK. A second event, sent by a build that
        // already contained this exact assignment, still arrived carrying the
        // IP — Sentry fills it in server-side at ingest. The authoritative
        // control is the PROJECT setting:
        //
        //     Sentry → Settings → Security & Privacy →
        //     "Prevent Storing of IP Addresses"   (enable on BOTH projects)
        //
        // This block is kept as defence in depth and as a statement of intent,
        // but do not read its presence as proof that no IP is stored. Verify
        // that on a real event after enabling the project setting.
        event.user = { ...(event.user ?? {}), ip_address: null };

        // Same class of leak one level down: an IP can also ride in on the
        // forwarding headers of the incoming request.
        const headers = event.request?.headers;
        if (headers) {
          for (
            const h of [
              "x-forwarded-for",
              "x-real-ip",
              "cf-connecting-ip",
              "true-client-ip",
              "forwarded",
            ]
          ) {
            delete headers[h];
          }
        }
        return event;
      },
    });
    enabled = true;
  } catch (_err) {
    // Never let reporting break a payment path.
    enabled = false;
  }
}

/** True when a DSN was present and the SDK started. */
export function sentryEnabled(): boolean {
  return enabled;
}

/**
 * Report an error that the calling function has ALREADY handled.
 *
 * `context` must contain only non-PII identifiers — an order id, a payment id,
 * a status code. Never an email address, a phone number, a token or a raw
 * request body. `scrub` below is a backstop, not a licence.
 *
 * Awaited by callers so the event is flushed before the isolate is frozen:
 * an Edge Function that returns without flushing loses the event.
 */
export async function captureFunctionError(
  functionName: string,
  err: unknown,
  context: Record<string, string | number | null | undefined> = {},
): Promise<void> {
  if (!enabled) return;
  try {
    Sentry.withScope((scope) => {
      scope.setTag("function", functionName);
      scope.setContext("danlite", { function: functionName, ...scrub(context) });
      Sentry.captureException(
        err instanceof Error ? err : new Error(String(err)),
      );
    });
    // 2s cap: a slow Sentry must not hold a customer's request open.
    await Sentry.flush(2000);
  } catch (_err) {
    // Reporting an error must never itself raise one.
  }
}

const EMAIL_LIKE = /[\w.+-]+@[\w-]+\.[\w.-]+/g;
const PHONE_LIKE = /\+?\d[\d\s-]{7,}\d/g;

/** Backstop redaction, in case a caller ever passes an identifier by accident. */
function scrub(
  context: Record<string, string | number | null | undefined>,
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(context)) {
    if (v === null || v === undefined) continue;
    out[k] = String(v)
      .replace(EMAIL_LIKE, "[email]")
      .replace(PHONE_LIKE, "[phone]");
  }
  return out;
}
