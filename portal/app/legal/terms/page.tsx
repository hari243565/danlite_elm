import type { Metadata } from 'next';
import { NOINDEX } from '@/lib/seo';
import { C } from '@/lib/theme';

export const metadata: Metadata = {
  title: 'Terms of Service (Draft) — Danlite ELM',
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

export default function TermsDraft() {
  return (
    <article>
      <h1 style={{ fontSize: 22, fontWeight: 700, margin: '0 0 6px' }}>Terms of Service</h1>
      <p style={{ ...p, margin: '0 0 4px' }}>
        The agreement between you and us for the Danlite ELM application.
      </p>
      <p style={{ ...p, color: C.amber }}>
        Version 0.1 (draft) · Last updated [CONFIRM: date of approval]
      </p>

      <h2 style={h2}>1. The agreement</h2>
      <p style={p}>
        These terms are between you and [CONFIRM: registered legal entity name] (&ldquo;we&rdquo;,
        &ldquo;us&rdquo;). By purchasing or using Danlite ELM you accept them. If you do not
        accept them, do not purchase or use the app.
      </p>

      <h2 style={h2}>2. What you are buying</h2>
      <p style={p}>
        You are buying a <strong>one-time, lifetime licence</strong> to use the Danlite ELM
        Android application. There is no subscription and no recurring charge. The price is
        ₹129 for customers in India and US$1.29 for customers elsewhere, determined by the
        country recorded on your account at signup.
      </p>
      <p style={p}>
        &ldquo;Lifetime&rdquo; means the working life of the product: the licence does not expire
        on a date, and we will not convert it into a subscription. It does not mean we guarantee
        to publish the app, or to support any particular Android version or vehicle, forever.
        [CONFIRM: whether you want to state a minimum support period, e.g. 24 months.]
      </p>

      <h2 style={h2}>3. What the licence permits</h2>
      <p style={p}>
        We grant you a personal, non-exclusive, non-transferable, revocable licence to install
        and use one copy of the app for your own use, including professional use in your own
        workshop. You may not:
      </p>
      <ul style={{ paddingLeft: 20, margin: '0 0 12px' }}>
        <li style={li}>share, resell, sublicense, rent or transfer your licence or account;</li>
        <li style={li}>
          modify, reverse-engineer, decompile or attempt to defeat the licensing mechanism,
          except to the extent that applicable law expressly permits it;
        </li>
        <li style={li}>use the app to build or assist a competing product.</li>
      </ul>
      <p style={p}>
        A licence is issued to one person and is enforced against a single active device. Signing
        in on a new device signs you out of the previous one.
      </p>

      <h2 style={h2}>4. Your account</h2>
      <p style={p}>
        You are responsible for keeping access to your email address or mobile number secure,
        because they are how you sign in and how activation links reach you. Tell us promptly at
        [CONFIRM: support email] if you believe someone else has accessed your account.
      </p>

      <h2 style={h2}>5. Payment</h2>
      <p style={p}>
        Payments are processed by Razorpay. We do not see or store your card or UPI credentials.
        Prices are stated inclusive of GST where applicable — see the checkout page for the
        breakdown that applies to your order. [CONFIRM: this sentence must match the GST
        treatment finally chosen; see portal/lib/gst.ts.]
      </p>

      <h2 style={h2}>6. Refunds</h2>
      <p style={p}>
        Refunds are governed by our Refund Policy, which forms part of these terms.
      </p>

      <h2 style={h2}>7. Safety and fitness for purpose — please read</h2>
      <p style={p}>
        Danlite ELM reads diagnostic information reported by your vehicle&rsquo;s own systems. It
        is a diagnostic aid, not a certification of roadworthiness and not a substitute for a
        qualified mechanic&rsquo;s judgement. Fault codes can be ambiguous, sensors can fail, and
        an adapter can misreport. <strong>Do not rely on the app alone to decide whether a
        vehicle is safe to drive, and do not operate the app while driving.</strong> You are
        responsible for any work you carry out on a vehicle.
      </p>

      <h2 style={h2}>8. Availability</h2>
      <p style={p}>
        The app is designed to keep working without a network connection for a period after your
        licence is last verified, so that it remains usable in workshops with poor signal. We do
        not guarantee uninterrupted availability of the online parts of the service, and we may
        suspend them for maintenance.
      </p>

      <h2 style={h2}>9. Suspension and termination</h2>
      <p style={p}>
        We may suspend or revoke a licence obtained by fraud, used in breach of section 3, or
        associated with a reversed or disputed payment. Where we revoke a licence for a reason
        that is not your fault, we will refund it.
      </p>

      <h2 style={h2}>10. Liability</h2>
      <p style={p}>
        Nothing in these terms limits liability that cannot lawfully be limited, including for
        death or personal injury caused by our negligence, or for fraud. Subject to that, and to
        the maximum extent permitted by law, our total liability arising out of or in connection
        with the app is limited to the amount you paid for your licence. We are not liable for
        indirect or consequential loss, including vehicle damage, loss of profit, or the cost of
        repairs undertaken in reliance on a diagnostic reading.
      </p>
      <p style={p}>
        [CONFIRM] A liability cap at the purchase price is standard for a low-value consumer
        product, but its enforceability against Indian consumer-protection law should be
        confirmed by your adviser.
      </p>

      <h2 style={h2}>11. Changes</h2>
      <p style={p}>
        We may update these terms. If a change materially reduces your rights we will give
        reasonable notice to the contact address on your account. Continuing to use the app after
        a change takes effect means you accept it.
      </p>

      <h2 style={h2}>12. Governing law</h2>
      <p style={p}>
        These terms are governed by the laws of India, and the courts of [CONFIRM: city] have
        exclusive jurisdiction, without prejudice to any right you have to bring proceedings
        before a consumer forum where you live.
      </p>

      <h2 style={h2}>13. Contact</h2>
      <p style={p}>[CONFIRM: support email and registered address].</p>
    </article>
  );
}
