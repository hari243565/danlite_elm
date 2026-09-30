// What account deletion does — shared by /legal/delete-account and the
// #delete-account section of /legal/privacy, so the two can never disagree.
//
// It describes ONLY the mechanism that exists today: an emailed request that
// the team carries out by hand (docs/legal/RISK_REGISTER.md T3; no in-app or
// automated deletion exists — E-066, E-093). When backlog item B-06 ships,
// rewrite this file first; both pages follow.

import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import { Email, H3, T } from './legal';

export function DeletionHowTo() {
  return (
    <>
      <p>
        Send an email to <Email v={cfg.CONTACT.privacyEmail} /> <strong>from the email address
        you use to sign in</strong>, with the subject line “Delete my account”. You do not need
        to give a reason.
      </p>
      <p>
        If you can no longer use that email address, write to us from another address and tell us
        the email address on the account. We will ask for something only the account holder
        would know, such as the payment reference on your receipt, before we act. We do this so
        that nobody else can delete your account.
      </p>
      <p>
        The app does not yet have a delete button. Until it does, this email request is the way
        to delete your account, and a member of our team carries out each request by hand.
        Uninstalling the app does <strong>not</strong> delete your account.
      </p>
    </>
  );
}

export function DeletionDetails() {
  return (
    <>
      <H3>What happens after you ask</H3>
      <ol>
        <li>We reply to confirm we have your request and that it comes from the account holder.</li>
        <li>
          We sign your account out on every device and end your licence. <strong>A deleted
          licence cannot be restored.</strong> To use the app again you would need a new account
          and a new purchase.
        </li>
        <li>We delete your data as described below and email you when it is done.</li>
      </ol>
      <p>
        We complete deletion within <T v={cfg.PRIVACY.deletionCompletionTime} /> of confirming
        your request.
      </p>

      <H3>What we delete</H3>
      <ul>
        <li>Your phone number.</li>
        <li>Your name, email address and country (unless you have paid; see below).</li>
        <li>The list of phones you have signed in on, and your sign-in sessions.</li>
        <li>Your licence record and any activation links.</li>
        <li>Records of orders that were never paid.</li>
        <li>If you have never paid us: your whole account, including your account ID.</li>
      </ul>

      <H3>What we keep, and why</H3>
      <ul>
        <li>
          <strong>If you have paid:</strong> the payment record and the details shown on your
          receipt: your name (or your email address if you gave no name), the amount, the tax,
          the payment reference, the invoice number and the date. We also keep your country,
          because it decides how tax applied to the sale. Indian tax law requires us to keep
          these records for six years from the due date of the annual tax return for the year of
          purchase, or longer if a tax case is open. After that we delete them.
        </li>
        <li>
          <strong>Security records</strong>: when anyone asks for an activation link, we store a
          scrambled (hashed) form of the email address typed in and the internet (IP) address
          the request came from, to stop abuse. We keep these for{' '}
          <T v={cfg.PRIVACY.retentionSecurityRecords} />.
        </li>
        <li>
          <strong>Our audit log</strong>: a record of licence, payment and staff actions on
          accounts, identified by account ID. It is built so that nobody, including us, can
          quietly edit it. We keep it for <T v={cfg.PRIVACY.retentionAuditLog} />.
        </li>
        <li>
          <strong>Backups</strong>: our database backups are encrypted and are deleted
          automatically after 90 days, so your data can stay in a backup for up to 90 days after
          deletion. We use backups only to recover from a failure. If we ever restore one, we
          delete your data again.
        </li>
        <li>
          <strong>Our service providers’ records</strong>: our email, crash-reporting and hosting
          providers keep their own logs for <T v={cfg.PRIVACY.providerLogRetention} />. Razorpay
          keeps its own records of your payment under the rules that apply to it as a payment
          company.
        </li>
      </ul>

      <H3>Data on your phone</H3>
      <p>
        Your vehicle profiles, trip history and settings are stored only on your phone, so we
        cannot delete them for you. To remove them, uninstall the app or clear its storage in
        your phone’s Settings. If Android backup is switched on, a copy may also be in your Google
        account backup, which you manage with Google.
      </p>

      <H3>Your licence and refunds</H3>
      <p>
        Deleting your account is not in itself a reason for a refund. If your purchase qualifies
        for a refund under our <Link href="/legal/refund">Cancellation and Refund Policy</Link>, ask for
        the refund <strong>before</strong> you ask us to delete your account, because we need
        the account to process it.
      </p>
    </>
  );
}
