import type { Metadata } from 'next';
import { NOINDEX } from '@/lib/seo';
import { C } from '@/lib/theme';

export const metadata: Metadata = {
  title: 'Refund Policy (Draft) — Danlite ELM',
  robots: NOINDEX,
};

const h2: React.CSSProperties = {
  fontSize: 15,
  fontWeight: 700,
  color: C.text,
  margin: '28px 0 8px',
};
const p: React.CSSProperties = {
  fontSize: 13.5,
  lineHeight: 1.75,
  color: C.muted,
  margin: '0 0 12px',
};
const li: React.CSSProperties = { ...p, margin: '0 0 8px' };

export default function RefundDraft() {
  return (
    <article>
      <h1 style={{ fontSize: 22, fontWeight: 700, margin: '0 0 6px' }}>Refund Policy</h1>
      <p style={{ ...p, margin: '0 0 4px' }}>
        For the one-time Danlite ELM lifetime licence.
      </p>
      <p style={{ ...p, color: C.amber }}>
        Version 0.1 (draft) · Last updated [CONFIRM: date of approval]
      </p>

      <div
        style={{
          border: `1px solid ${C.amber}`,
          borderRadius: 8,
          padding: '14px 16px',
          margin: '0 0 8px',
        }}
      >
        <p style={{ ...p, margin: 0, color: C.amber }}>
          <strong>PROPOSED DEFAULT, NOT A DECISION.</strong> The 24-hour window and the
          activation condition below are a sensible starting position drafted for review, chosen
          to be simple to administer and hard to abuse. They are not a final policy, and Razorpay
          may require specific wording of its own before it will approve the account.
        </p>
      </div>

      <h2 style={h2}>1. The short version</h2>
      <p style={p}>
        You can have a full refund within <strong>24 hours</strong> of purchase, provided the
        licence has <strong>not yet been activated on a device</strong>. Once a licence has been
        activated, it is not refundable.
      </p>

      <h2 style={h2}>2. Why it is drawn that way</h2>
      <p style={p}>
        The product is a permanent, one-time licence to software that works offline. Once it has
        been activated on a device, its entire value has already been delivered and cannot be
        taken back in any practical sense. The 24-hour unactivated window exists to cover the
        genuine cases — a duplicate purchase, a wrong account, a change of mind before use —
        without creating a free trial that resets on demand.
      </p>

      <h2 style={h2}>3. We will always refund these</h2>
      <ul style={{ paddingLeft: 20, margin: '0 0 12px' }}>
        <li style={li}>
          <strong>Duplicate payment.</strong> If you were charged twice for the same licence, we
          refund the duplicate in full, whether or not the licence was activated.
        </li>
        <li style={li}>
          <strong>You were charged but received no licence.</strong> We will either fix the
          licence or refund you, whichever you prefer.
        </li>
        <li style={li}>
          <strong>We revoke your licence through no fault of yours</strong> — see section 9 of
          the Terms.
        </li>
        <li style={li}>
          <strong>The app cannot work on your device at all</strong> and we cannot fix it within
          a reasonable time. Report it within [CONFIRM: period] of purchase.
        </li>
      </ul>

      <h2 style={h2}>4. What is not refundable</h2>
      <ul style={{ paddingLeft: 20, margin: '0 0 12px' }}>
        <li style={li}>
          A licence that has been activated on a device, outside the cases in section 3.
        </li>
        <li style={li}>
          Dissatisfaction with what your vehicle reports. The app displays the data your
          vehicle&rsquo;s systems provide; a car that reports few fault codes, or codes you did
          not expect, is not a defect in the app.
        </li>
        <li style={li}>
          Incompatibility with a third-party ELM327 adapter of unknown quality. Clone adapters
          vary widely. [CONFIRM: whether you want to offer a goodwill exception here — it is a
          common support burden.]
        </li>
        <li style={li}>A licence revoked for sharing, fraud or a reversed payment.</li>
      </ul>

      <h2 style={h2}>5. How to request one</h2>
      <p style={p}>
        Email [CONFIRM: support email] from the address on your account, or use the mobile number
        on your account, and tell us the payment reference from your receipt. You do not need to
        give a reason for a request that falls inside the 24-hour unactivated window.
      </p>

      <h2 style={h2}>6. How long it takes</h2>
      <p style={p}>
        We aim to decide within [CONFIRM: e.g. 3 working days]. Approved refunds are returned to
        the original payment method through Razorpay. Your bank or card issuer then typically
        takes a further 5–7 working days to post it, which is outside our control.
      </p>

      <h2 style={h2}>7. Statutory rights</h2>
      <p style={p}>
        Nothing in this policy limits any right you have under the Consumer Protection Act, 2019
        or other applicable Indian law. Where those rights are wider than this policy, they
        apply.
      </p>

      <h2 style={h2}>8. Open questions for review</h2>
      <ul style={{ paddingLeft: 20, margin: '0 0 12px' }}>
        <li style={li}>
          [CONFIRM] Is 24 hours the right window, or would 48 hours / 7 days reduce chargebacks
          enough to be worth the extra exposure?
        </li>
        <li style={li}>
          [CONFIRM] Should international customers get a different window, given the higher cost
          and slower resolution of cross-border chargebacks?
        </li>
        <li style={li}>
          [CONFIRM] Razorpay requires a published refund policy for account approval. Check their
          current wording requirements against this text before publishing.
        </li>
      </ul>
    </article>
  );
}
