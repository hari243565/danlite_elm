import type { Metadata } from 'next';
import { NOINDEX } from '@/lib/seo';
import { C } from '@/lib/theme';

export const metadata: Metadata = {
  title: 'Privacy Policy (Draft) — Danlite ELM',
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

export default function PrivacyDraft() {
  return (
    <article>
      <h1 style={{ fontSize: 22, fontWeight: 700, margin: '0 0 6px' }}>Privacy Policy</h1>
      <p style={{ ...p, margin: '0 0 4px' }}>
        Applies to the Danlite ELM Android application and this billing portal.
      </p>
      <p style={{ ...p, color: C.amber }}>
        Version 0.1 (draft) · Last updated [CONFIRM: date of approval]
      </p>

      <h2 style={h2}>1. Who we are</h2>
      <p style={p}>
        Danlite ELM is an OBD2 vehicle diagnostics application for Android, published by
        [CONFIRM: registered legal entity name], [CONFIRM: registered address, India]. For any
        privacy question, or to exercise the rights described in section 7, contact us at
        [CONFIRM: privacy contact email].
      </p>
      <p style={p}>
        Under the Digital Personal Data Protection Act, 2023 (&ldquo;DPDP Act&rdquo;) we are the{' '}
        <strong>Data Fiduciary</strong> for the personal data described below, and you are the{' '}
        <strong>Data Principal</strong>.
      </p>

      <h2 style={h2}>2. What we collect</h2>
      <p style={p}>
        We deliberately collect as little as possible. To sell and license a one-time product we
        need to know who bought it and how to reach them, and nothing more.
      </p>
      <ul style={{ paddingLeft: 20, margin: '0 0 12px' }}>
        <li style={li}>
          <strong>Email address or mobile number</strong> — whichever you use to sign in. This is
          your account identifier and the address we send your activation link and receipt to.
        </li>
        <li style={li}>
          <strong>Country</strong> — a two-letter country code, recorded at signup. It determines
          your price and currency, and which channel we can send one-time passcodes over.
        </li>
        <li style={li}>
          <strong>Device identifier</strong> — an identifier for the Android device your licence
          is active on, so that a single-user licence cannot be shared across unlimited devices.
        </li>
        <li style={li}>
          <strong>Payment records</strong> — the amount, currency, date, and the payment
          reference issued by our payment provider. <strong>We never receive or store your card
          number, UPI PIN, CVV or bank credentials.</strong> Those go directly to the payment
          provider.
        </li>
      </ul>

      <h2 style={h2}>3. What we do not collect</h2>
      <p style={p}>
        We do not collect the diagnostic data your app reads from your vehicle. Fault codes, live
        sensor readings, freeze-frame data and any vehicle identifiers stay on your device and
        are not transmitted to us. We do not collect your location, your contacts, or your
        browsing activity, and we do not use advertising or analytics trackers on this portal.
      </p>

      <h2 style={h2}>4. Why we process it, and on what basis</h2>
      <p style={p}>
        We process the data in section 2 to create and secure your account, to take payment, to
        issue and verify your licence, to send transactional messages such as activation links
        and receipts, and to meet our tax and accounting obligations. Under the DPDP Act our
        basis is your consent, given at signup, together with the legitimate uses permitted for
        performing a contract you have entered into and for complying with law.
      </p>

      <h2 style={h2}>5. Who else sees it</h2>
      <p style={p}>
        We share the minimum necessary with processors acting on our instructions: our hosting
        and database provider (Supabase), our transactional email provider (Resend), our SMS
        provider for Indian one-time passcodes [CONFIRM: MSG91 or alternative], and our payment
        provider (Razorpay). We do not sell your personal data, and we do not share it for
        anyone else&rsquo;s marketing.
      </p>
      <p style={p}>
        [CONFIRM] Some of these providers process data outside India. Confirm the transfer
        position with your adviser and name the countries here.
      </p>

      <h2 style={h2}>6. How long we keep it</h2>
      <p style={p}>
        Because the licence is a lifetime one, we keep your account and licence records for as
        long as the licence is capable of being used. Payment and tax records are retained for
        [CONFIRM: retention period, commonly 8 years for Indian tax records]. When you ask us to
        delete your account we mark it for erasure immediately and remove the underlying data
        after that retention window, keeping only what the law requires us to keep.
      </p>

      <h2 style={h2}>7. Your rights</h2>
      <p style={p}>
        Under the DPDP Act you may ask us for a summary of the personal data we hold about you
        and how we process it; ask us to correct or complete anything inaccurate; ask us to erase
        your data where we are not required to retain it; withdraw your consent at any time; and
        nominate another person to exercise these rights on your behalf if you die or become
        incapacitated. Write to [CONFIRM: privacy contact email] and we will respond within
        [CONFIRM: response period].
      </p>
      <p style={p}>
        Withdrawing consent for the data in section 2 means we can no longer operate your
        licence, because that data <em>is</em> the licence.
      </p>

      <h2 style={h2}>8. Security</h2>
      <p style={p}>
        Access to your records is restricted at the database level so that one customer cannot
        read another&rsquo;s. Sign-in tokens are held in the Android system keystore on your
        device, not in ordinary application storage. Activation links are single-use, expire
        within fifteen minutes, and are stored only as an irreversible hash. No system is
        perfectly secure, but we will notify you and the Data Protection Board of India of a
        personal data breach as the DPDP Act requires.
      </p>

      <h2 style={h2}>9. Children</h2>
      <p style={p}>
        This product is intended for vehicle owners and professional mechanics and is not
        directed at children. We do not knowingly process the personal data of a child under 18
        without verifiable parental consent as required by the DPDP Act.
      </p>

      <h2 style={h2}>10. Grievance officer</h2>
      <p style={p}>
        [CONFIRM] The DPDP Act requires a named grievance contact. Insert name, designation and
        contact address before publication.
      </p>
    </article>
  );
}
