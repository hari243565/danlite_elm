// Privacy Policy. Every factual sentence here is traced in
// docs/legal/CLAIM_LEDGER.md (rows P-nn). Change the ledger with the text.

import type { Metadata } from 'next';
import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import { Email, INDEXABLE, LegalDoc, T, Table, type Section } from '../_components/legal';
import { DeletionDetails, DeletionHowTo } from '../_components/deletion';

export const metadata: Metadata = {
  title: 'Privacy Policy — Danlite ELM',
  description:
    'What personal data the Danlite ELM app and billing website collect, why, who receives it, how long it is kept, and your rights.',
  robots: INDEXABLE,
};

const B = cfg.BUSINESS;
const K = cfg.CONTACT;
const P = cfg.PRIVACY;

const summary = (
  <ul>
    <li>
      To use the app you create an account with your <strong>email address</strong>, your{' '}
      <strong>name</strong> and your <strong>country</strong>. A phone number is optional.
    </li>
    <li>
      When you create an account we <strong>automatically email you a link to buy the
      licence</strong>. Your email and phone number (if given) are also passed to Razorpay to
      fill in the payment form.
    </li>
    <li>
      We <strong>never see your card, UPI or bank details</strong>. Razorpay handles them.
    </li>
    <li>
      Your vehicle profiles and trip history stay on your phone. But when the app hits an error,
      the <strong>crash report can include recent diagnostic messages from your vehicle</strong>{' '}
      (for example fault codes). Crash reports go to Sentry in Germany.
    </li>
    <li>
      Some of our providers store data <strong>outside India</strong>: in the United States,
      Germany and Japan.
    </li>
    <li>
      Records of a purchase are <strong>kept for several years for tax law</strong>, even if you
      delete your account. Backups keep deleted data for up to 90 days.
    </li>
    <li>
      To delete your account, email us. There is no delete button in the app yet.{' '}
      <a href="#delete-account">How deletion works</a>.
    </li>
    <li>We do not sell your data and we do not show ads.</li>
  </ul>
);

const sections: Section[] = [
  {
    id: 'who-we-are',
    title: 'Who we are',
    body: (
      <>
        <p>
          {B.productName} is a vehicle diagnostics app for Android. On your phone it appears as
          “{B.appLabel}”. On Google Play it is listed as <T v={B.playListingName} /> by{' '}
          <T v={B.playDeveloperName} />. It is sold through our billing website{' '}
          <a href={B.website}>billing.danlite.in</a>.
        </p>
        <p>
          The app and the website are run by <T v={B.legalName} /> (<T v={B.entityType} />),{' '}
          <T v={B.registeredAddress} /> (“we”, “us”). We decide why and how your personal data
          is used. Under India’s Digital Personal Data Protection Act, 2023 that makes us the{' '}
          <strong>Data Fiduciary</strong>, and you are the <strong>Data Principal</strong>.
        </p>
        <p>
          This policy covers the app and billing.danlite.in. It does not cover Razorpay’s payment
          window, which is governed by{' '}
          <a href="https://razorpay.com/privacy/" rel="noopener noreferrer">
            Razorpay’s own privacy policy
          </a>
          .
        </p>
        <p>
          Questions about privacy: <Email v={K.privacyEmail} />. Our grievance officer is named
          in <a href="#contact">section 19</a>.
        </p>
      </>
    ),
  },
  {
    id: 'what-we-collect',
    title: 'What we collect',
    body: (
      <>
        <Table
          head={['Data', 'Why we need it', 'Do you have to give it?']}
          rows={[
            [
              'Email address',
              'Your login (we email you a one-time code). We also send activation and purchase links to it, show it on your receipt if you gave no name, and use it to find your account when you contact us.',
              'Yes. You cannot have an account without one.',
            ],
            [
              'Full name',
              'Shown on your receipt as the buyer. Helps us recognise you when you contact us.',
              'Yes, the sign-up screen asks for it.',
            ],
            [
              'Phone number',
              'For support contact. It is also passed to Razorpay to fill in the payment form.',
              'No, it is optional.',
            ],
            [
              'Country',
              'Decides your price, currency and how tax applies. You choose it when you sign up and cannot change it yourself afterwards.',
              'Yes.',
            ],
            [
              'Account ID',
              'A random code that identifies your account in our systems and in payment records.',
              'Created automatically.',
            ],
            [
              'Device details: phone make and model, and a random device ID',
              'So your licence works on one phone at a time, and so you can see which phone is signed in. The random ID is created by the app. It is not your phone’s IMEI, serial number or advertising ID.',
              'Collected automatically when you sign in.',
            ],
            [
              'Sign-in records: IP address and device or browser type',
              'Kept by our login provider for each sign-in session, for security.',
              'Collected automatically.',
            ],
            [
              'Purchase records: order and payment references, amount, currency, status, invoice number, payment method type (for example “card” or “upi”), and Razorpay’s fee and tax',
              'To give you your licence, show your receipt, handle refunds and keep tax records.',
              'Needed to buy.',
            ],
            [
              'For buyers outside India: billing country, postcode (optional), the IP address and device ID used at checkout, and fraud checks (whether the card’s country matches your billing country)',
              'To help your bank verify the card and to stop stolen-card testing.',
              'Billing country: needed. Postcode: optional.',
            ],
            [
              'Crash and error reports (see section 5)',
              'To find and fix faults in the app.',
              'Sent automatically when an error happens.',
            ],
            [
              'Messages you send us',
              'To answer you.',
              'Only if you contact us.',
            ],
          ]}
        />
      </>
    ),
  },
  {
    id: 'what-we-do-not-collect',
    title: 'What we do not collect',
    body: (
      <ul>
        <li>
          <strong>Card, UPI or bank details.</strong> You enter these in Razorpay’s payment window
          and they go to Razorpay, not to us.
        </li>
        <li>
          <strong>Your location.</strong> On Android 11 and older, Android makes apps ask for
          location permission before they can search for Bluetooth adapters. The app asks for it
          only for that reason and does not read your location.
        </li>
        <li>
          <strong>Contacts, photos, files, camera or microphone.</strong> The app does not ask for
          these permissions.
        </li>
        <li>
          <strong>Advertising or analytics tracking.</strong> The app and this website contain no
          advertising or analytics services.
        </li>
      </ul>
    ),
  },
  {
    id: 'sources',
    title: 'Where your data comes from',
    body: (
      <ul>
        <li>
          <strong>From you:</strong> what you type when you sign up or contact us.
        </li>
        <li>
          <strong>From your phone and browser, automatically:</strong> device details, IP address,
          and crash reports.
        </li>
        <li>
          <strong>From Razorpay:</strong> whether your payment succeeded, the payment references,
          method type, fee and tax, and for international cards the card’s country.
        </li>
        <li>
          <strong>From our email provider:</strong> records of whether our emails to you were
          delivered. These stay in the provider’s own systems.
        </li>
      </ul>
    ),
  },
  {
    id: 'vehicle-data',
    title: 'Your vehicle data and the app on your phone',
    body: (
      <>
        <p>
          The app reads information from your vehicle through a Bluetooth or Wi-Fi adapter: fault
          codes, live sensor readings, and identifiers your vehicle reports. It stores your
          vehicle profiles (including a VIN if you enter one), trip history and settings{' '}
          <strong>on your phone only</strong>. We do not upload them to our servers.
        </p>
        <p>
          There are three exceptions you should know about:
        </p>
        <ul>
          <li>
            <strong>Crash reports.</strong> When the app records an error, it sends a report to
            our crash-reporting provider, Sentry. The report contains technical details (phone
            model, Android version, app version, what went wrong) and the app’s most recent log
            messages. These messages <strong>can include recent communication between the app and
            your vehicle</strong>, such as fault codes, sensor values and identifiers the vehicle
            reported. Sentry may also record the IP address your phone used and an approximate
            (city-level) location worked out from it. We also receive a small sample of
            performance measurements.
          </li>
          <li>
            <strong>Fonts.</strong> The first time the app runs, it downloads its typeface from
            Google’s font service. Google receives your phone’s IP address and basic technical
            details of the request.
          </li>
          <li>
            <strong>Your own backups and exports.</strong> If Android backup is switched on, Android
            may include the app’s settings, vehicle profiles and trip history in your backup to
            your Google account. If you use “export” on a trip, the app copies it to your phone’s
            clipboard, and what happens next is up to you.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: 'purposes',
    title: 'Why we use your data, and on what basis',
    body: (
      <>
        <Table
          head={['What we do', 'Why we are allowed to']}
          rows={[
            [
              'Create your account, log you in, and keep your licence working on one phone',
              'You gave us this data to use the app. We need it to provide what you asked for.',
            ],
            [
              'Email you activation and purchase links, and pass your email and phone to Razorpay to fill in the payment form',
              'To complete the purchase you started by creating an account.',
            ],
            [
              'Take payment, issue your licence, show your receipt, handle refunds',
              'To provide what you bought.',
            ],
            [
              'Keep payment and tax records',
              'Required by Indian tax law.',
            ],
            [
              'Security: limit link requests, detect card-testing, keep an audit log, record sign-in sessions',
              'To protect you and the service from misuse and fraud.',
            ],
            [
              'Crash reports',
              'To keep the app working and fix faults.',
            ],
            [
              'Answer your messages, complaints and requests',
              'You asked us to, and the law requires us to handle complaints.',
            ],
          ]}
        />
        <p>
          We do not use your data for advertising and we do not send you marketing emails. We do
          not sell your personal data.
        </p>
        <p>
          Where the law needs your consent for a use, you can withdraw it at any time (see{' '}
          <a href="#your-rights">section 12</a>). Withdrawing does not undo what we did before, and
          if you withdraw consent for data the licence needs, we can no longer provide the
          licence.
        </p>
      </>
    ),
  },
  {
    id: 'emails',
    title: 'Emails we send you',
    body: (
      <ul>
        <li>
          <strong>Login codes</strong>: a 6-digit code each time you log in, sent by our login
          provider (<T v={K.loginCodeSender} />).
        </li>
        <li>
          <strong>Activation and purchase links</strong>: sent automatically when you create an
          account, and again whenever you (or anyone typing your email address) ask for a new
          link. Each link works once and expires after 15 minutes. They come from{' '}
          <T v={K.activationSender} />.
        </li>
        <li>
          <strong>Replies</strong> to messages you send us.
        </li>
      </ul>
    ),
  },
  {
    id: 'recipients',
    title: 'Who receives your data',
    body: (
      <>
        <p>
          We use the service providers below. They handle data on our behalf and for the purposes
          in this policy, except where noted. A small number of our own staff (currently two
          people) can see customer account, licence, payment and device records in order to run
          the service and answer support requests. Changes they make to an account are logged.
        </p>
        <Table
          head={['Provider', 'What it does for us', 'What it receives', 'Where']}
          rows={[
            [
              'Supabase',
              'Our database, login system and server functions',
              'All the account, licence, purchase, device and security data in section 2',
              'Mumbai, India',
            ],
            [
              'Cloudflare (used by Supabase)',
              'Network that carries traffic to our database',
              'Your IP address and the requests your app or browser makes',
              'Global network',
            ],
            [
              'Razorpay Software Limited',
              'Payment processing',
              'Your email and phone (to fill in the form), the amount, your account ID and, for international orders, your billing country. You give your card, UPI or bank details directly to Razorpay. Razorpay also uses payment data for its own legal duties as a payment company.',
              'India (Bengaluru-based company)',
            ],
            [
              'Resend, sending through Amazon Web Services',
              'Sends our activation and purchase emails',
              'Your email address, the email content and delivery records',
              'Sent from Japan (Tokyo). Resend stores account data and logs in the United States.',
            ],
            [
              'Sentry',
              'Crash and error reports (see section 5)',
              'Error details, phone model and software versions, recent app log messages, possibly your IP address and approximate location',
              'Germany (Frankfurt)',
            ],
            [
              'Hostinger',
              'Hosts this website',
              'Your IP address, browser type and the pages you visit (standard server logs)',
              <T key="h" v={P.hostingerLocation} />,
            ],
            [
              'GitHub',
              'Stores our encrypted database backups',
              'Backups of our database, encrypted before they are stored. The key to decrypt them is not stored at GitHub.',
              <T key="g" v={P.githubLocation} />,
            ],
            [
              'Google (Fonts)',
              'Supplies the app’s typeface',
              'Your phone’s IP address when the font is downloaded. Google uses this under its own terms.',
              'Global',
            ],
            [
              'Google (reCAPTCHA)',
              'Checks for automated abuse on international checkout, only when we switch it on',
              'Technical signals from your browser during checkout',
              'Global',
            ],
          ]}
        />
        <p>
          We may also disclose data where the law requires it, for example to a tax authority or
          under a lawful order.
        </p>
      </>
    ),
  },
  {
    id: 'international-transfers',
    title: 'Data stored outside India',
    body: (
      <>
        <p>
          Our main database is in India. As the table above shows, some providers process data in
          other countries: email records in the <strong>United States</strong>, emails sent from{' '}
          <strong>Japan</strong>, crash reports in <strong>Germany</strong>, and network traffic
          through Cloudflare’s and Google’s global networks.
        </p>
        <p>
          <T v={P.transferSafeguards} />
        </p>
      </>
    ),
  },
  {
    id: 'retention',
    title: 'How long we keep your data',
    body: (
      <>
        <Table
          head={['Data', 'How long']}
          rows={[
            [
              'Account details (email, name, phone, country), devices, sign-in sessions, licence',
              'While your account exists. After you ask us to delete it, see section 13.',
            ],
            [
              'Payment records and the details on your receipt',
              'Six years from the due date of the annual tax return for the year of purchase (roughly seven to eight years in total), or longer if a tax case is open. Indian tax law requires this.',
            ],
            [
              'Security records (hashed email and IP address from link requests, used activation links, card-testing checks)',
              <T key="s" v={P.retentionSecurityRecords} />,
            ],
            ['Audit log of licence, payment and staff actions', <T key="a" v={P.retentionAuditLog} />],
            [
              'Logs kept by our providers (login sessions, hosting, email delivery, crash reports)',
              <T key="p" v={P.providerLogRetention} />,
            ],
            ['Encrypted database backups', 'Deleted automatically after 90 days.'],
            [
              'Data on your phone',
              'Until you uninstall the app or clear its storage. Your own Android backup follows your Google settings.',
            ],
          ]}
        />
        <p>
          Automatic deletion is not yet in place for every row above. Where it is not, we delete
          old records by hand at the end of the period.
        </p>
      </>
    ),
  },
  {
    id: 'security',
    title: 'How we protect your data',
    body: (
      <>
        <p>Measures we use include:</p>
        <ul>
          <li>Database access rules so that each customer can read only their own records.</li>
          <li>Login by one-time email code. There is no password to steal or reuse.</li>
          <li>On your phone, login and licence tokens are kept in Android’s encrypted storage.</li>
          <li>
            Activation links work once, expire after 15 minutes, and are stored only in scrambled
            (hashed) form.
          </li>
          <li>Payment notifications from Razorpay are checked with a cryptographic signature.</li>
          <li>Data sent to us and to our providers travels over encrypted (HTTPS) connections.</li>
          <li>Backups are encrypted before they are stored.</li>
          <li>Staff access is limited to named people, and changes they make are logged.</li>
        </ul>
        <p>
          No system is completely secure. If a personal data breach affects you, we will tell you
          and report it as the law requires.
        </p>
      </>
    ),
  },
  {
    id: 'your-rights',
    title: 'Your rights',
    body: (
      <>
        <p>You can ask us to:</p>
        <ul>
          <li>
            <strong>Give you a summary</strong> of the personal data we hold about you, what we do
            with it, and who we have shared it with.
          </li>
          <li>
            <strong>Correct or update</strong> anything that is wrong or incomplete, including your
            name, phone number or email address.
          </li>
          <li>
            <strong>Delete</strong> your data (see <a href="#delete-account">section 13</a>).
          </li>
          <li>
            <strong>Withdraw consent</strong> you have given, as easily as you gave it.
          </li>
          <li>
            <strong>Nominate</strong> someone to use these rights for you if you die or become
            unable to act.
          </li>
          <li>
            <strong>Complain</strong> to our grievance officer (section 19).
          </li>
        </ul>
        <p>
          To use any of these rights, email <Email v={K.privacyEmail} /> from the email address on
          your account. We may ask you to confirm it is you. We will reply within{' '}
          <T v={K.privacyResponseTime} />.
        </p>
        <p>
          Some of this you can do yourself. Once you have a licence, the Account screen in the app shows your details. Your
          account page on billing.danlite.in shows your email, phone, country and signed-in phone,
          and lets you sign out of every device.
        </p>
        <p>
          If you are not satisfied with our answer, you can complain to the{' '}
          <strong>Data Protection Board of India</strong>. If you live outside India, see{' '}
          <a href="#outside-india">section 16</a>.
        </p>
      </>
    ),
  },
  {
    id: 'delete-account',
    title: 'Deleting your account',
    body: (
      <>
        <DeletionHowTo />
        <DeletionDetails />
        <p>
          This information is also on its own page:{' '}
          <Link href="/legal/delete-account">Delete your account</Link>.
        </p>
      </>
    ),
  },
  {
    id: 'children',
    title: 'Age limit',
    body: (
      <p>
        The app and the licence are for people aged <T v={cfg.TERMS.minimumAge} /> or over. The
        app does not currently ask for your age or check it. If we learn that someone under that
        age has an account, we will delete it.
      </p>
    ),
  },
  {
    id: 'cookies',
    title: 'Cookies and storage',
    body: (
      <>
        <p>
          <strong>This website</strong> uses cookies only to keep you signed in after you open an
          activation link. They are needed for the site to work and are not used for tracking.
          The policy pages set no cookies. We use no analytics or advertising cookies.
        </p>
        <p>
          When you pay, Razorpay’s payment window loads from Razorpay and follows Razorpay’s own
          cookie practices.
        </p>
        <p>
          <strong>The app</strong> stores data on your phone as described in section 5. Login and
          licence tokens are kept in Android’s encrypted storage. Vehicle profiles, trip history
          and settings are kept in ordinary app storage.
        </p>
      </>
    ),
  },
  {
    id: 'outside-india',
    title: 'If you live outside India',
    body: (
      <>
        <p>
          If you live in the United Kingdom or the European Union, data protection law there
          also gives you the right to restrict or object to our use of your data and to receive
          your data in a portable format. You can also complain to the data protection authority
          where you live. The “why we are allowed to” column in section 6 corresponds to these
          legal bases under that law: providing the contract you entered into, complying with a
          legal obligation, and our legitimate interest in keeping the service secure and
          working.
        </p>
        <p>
          Our representative in the UK and EU: <T v={P.euUkRepresentative} />
        </p>
        <p>Wherever you live, the rights in section 12 apply to you.</p>
      </>
    ),
  },
  {
    id: 'no-data',
    title: 'If you do not give us your data',
    body: (
      <p>
        Without an email address, name and country we cannot create an account. Without an account
        and a licence the app’s features cannot be used. The phone number is optional and leaving
        it out changes nothing about the app.
      </p>
    ),
  },
  {
    id: 'changes',
    title: 'Changes to this policy',
    body: (
      <>
        <p>
          If we change this policy, we will update the version and date at the top and the version
          history at the bottom. If a change affects how we use data you have already given us, we
          will email you before it takes effect.
        </p>
        <p>
          <T v={P.noticeLanguages} />
        </p>
      </>
    ),
  },
  {
    id: 'contact',
    title: 'Contact and grievance officer',
    body: (
      <>
        <p>
          Privacy questions and requests: <Email v={K.privacyEmail} />
        </p>
        <p>
          Grievance officer: <T v={K.grievanceOfficerName} />, <T v={K.grievanceOfficerDesignation} />
          . Email <Email v={K.grievanceOfficerEmail} />. Post: <T v={B.legalName} />,{' '}
          <T v={B.registeredAddress} />.
        </p>
        <p>
          See our <Link href="/legal/contact">Contact page</Link> for every way to reach us and how
          quickly we respond.
        </p>
      </>
    ),
  },
];

export default function PrivacyPolicy() {
  return (
    <LegalDoc
      title="Privacy Policy"
      intro={
        <>
          How {B.productName} handles your personal data in the Android app and on
          billing.danlite.in. The box below lists the points most likely to matter to you. The
          full policy follows.
        </>
      }
      summary={summary}
      sections={sections}
    />
  );
}
