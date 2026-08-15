'use client';

// ══════════════════════════════════════════════════════════════════════════
// The "Finalizing your purchase…" state.
//
// A customer arrives here a fraction of a second after Razorpay's window
// closed, and the webhook that actually activates their licence may not have
// landed yet. So this component waits — visibly, with an honest explanation —
// instead of the page flatly reporting "no purchase found" to somebody who
// has just paid.
//
// IT DOES NOT DECIDE ANYTHING. It calls a server action that reads the
// database as the signed-in user, under the Phase 1 RLS policies. When that
// read reports a real captured payment, this component's entire response is
// router.refresh() — re-rendering the server component, which draws the
// receipt from the database row itself. There is no success state in this
// file to be tricked into showing, because success is not rendered here.
// ══════════════════════════════════════════════════════════════════════════

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { C } from '@/lib/theme';

/** ~2s x 15 ≈ 30 seconds before we soften the message. */
const INTERVAL_MS = 2_000;
const MAX_ATTEMPTS = 15;
/** After the visible timeout we keep going, just less eagerly. */
const SLOW_INTERVAL_MS = 5_000;

export default function StatusPoller({
  check,
}: {
  check: () => Promise<{ done: boolean }>;
}) {
  const router = useRouter();
  const [attempts, setAttempts] = useState(0);
  const [timedOut, setTimedOut] = useState(false);
  // Survives re-renders; stops a late timer firing after we have navigated.
  const stopped = useRef(false);

  useEffect(() => {
    stopped.current = false;
    let timer: ReturnType<typeof setTimeout>;
    let n = 0;

    async function tick() {
      if (stopped.current) return;
      n += 1;
      setAttempts(n);

      try {
        const { done } = await check();
        if (done && !stopped.current) {
          stopped.current = true;
          // The only thing success does here: ask the server to re-render.
          router.refresh();
          return;
        }
      } catch {
        // A failed poll is not a failed payment. Keep waiting; the next tick
        // may well succeed, and reporting an error would be a false negative
        // to somebody whose money has already moved.
      }

      if (stopped.current) return;
      if (n >= MAX_ATTEMPTS) setTimedOut(true);
      timer = setTimeout(tick, n >= MAX_ATTEMPTS ? SLOW_INTERVAL_MS : INTERVAL_MS);
    }

    timer = setTimeout(tick, INTERVAL_MS);
    return () => {
      stopped.current = true;
      clearTimeout(timer);
    };
  }, [check, router]);

  return (
    <>
      <h2
        style={{
          fontSize: 15,
          fontWeight: 700,
          margin: '0 0 6px',
          color: timedOut ? C.amber : C.cyan,
        }}
      >
        {timedOut ? 'Still finalizing…' : 'Finalizing your purchase…'}
      </h2>

      <p style={{ color: C.muted, fontSize: 13, lineHeight: 1.6, margin: '0 0 18px' }}>
        {timedOut
          ? 'This is taking a little longer than usual — this page will keep checking, or check back in a minute. If money has left your account, your licence will activate; payment confirmations occasionally arrive a few minutes late.'
          : 'We are waiting for your bank and the payment provider to confirm. This usually takes a few seconds. Please do not close this page.'}
      </p>

      {/* A moving thing, so the page never looks frozen. */}
      <div
        style={{
          height: 4,
          borderRadius: 999,
          backgroundColor: C.card,
          overflow: 'hidden',
          marginBottom: 14,
        }}
      >
        <div
          style={{
            height: '100%',
            width: `${Math.min(100, (attempts / MAX_ATTEMPTS) * 100)}%`,
            backgroundColor: timedOut ? C.amber : C.cyan,
            transition: 'width 0.6s linear',
          }}
        />
      </div>

      <p style={{ color: C.muted, fontSize: 12, margin: 0 }}>
        Checked {attempts} {attempts === 1 ? 'time' : 'times'}.
      </p>
    </>
  );
}
