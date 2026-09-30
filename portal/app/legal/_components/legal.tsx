// Shared building blocks for the /legal/* pages.
//
// Two rules these components exist to enforce:
//   1. A placeholder can never look like real text. Every string from
//      lib/legal-config.ts goes through <T>, which renders an unresolved
//      token as a highlighted box naming the OPEN_QUESTIONS item that
//      answers it.
//   2. The table of contents cannot drift from the headings. A page passes
//      one array of sections; the contents list and the headings are both
//      rendered from it.

import type { Metadata } from 'next';
import Link from 'next/link';
import * as cfg from '@/lib/legal-config';
import s from './legal.module.css';

/**
 * The /legal/* pages are the only indexable pages on this portal (Razorpay
 * reviews them and Google Play links to them). Every other route keeps
 * NOINDEX from lib/seo.ts.
 */
export const INDEXABLE: Metadata['robots'] = { index: true, follow: true };

/** Every legal page, in footer order. Paths are stable: the app and Play link to them. */
export const LEGAL_PAGES = [
  { href: '/legal', label: 'All policies' },
  { href: '/legal/terms', label: 'Terms and Conditions' },
  { href: '/legal/privacy', label: 'Privacy Policy' },
  { href: '/legal/refund', label: 'Cancellation and Refunds' },
  { href: '/legal/delivery', label: 'Delivery Policy' },
  { href: '/legal/pricing', label: 'Pricing' },
  { href: '/legal/contact', label: 'Contact Us' },
  { href: '/legal/delete-account', label: 'Delete your account' },
] as const;

function tokenRe() {
  // Fresh instance each call: a shared /g regex keeps lastIndex between uses.
  return new RegExp(cfg.TODO_TOKEN.source, 'g');
}

/** Text from the config, with any unresolved token rendered as a highlight. */
export function T({ v }: { v: string }) {
  const parts: React.ReactNode[] = [];
  let last = 0;
  for (const m of v.matchAll(tokenRe())) {
    const i = m.index ?? 0;
    if (i > last) parts.push(v.slice(last, i));
    const q = cfg.PLACEHOLDER_QUESTIONS[m[1]] ?? 'no question mapped';
    parts.push(
      <mark key={i} className={s.todo} title={`Unresolved placeholder — ${q}`}>
        {m[0]} ({q})
      </mark>,
    );
    last = i + m[0].length;
  }
  if (last < v.length) parts.push(v.slice(last));
  return <>{parts}</>;
}

export function isResolved(v: string): boolean {
  return !tokenRe().test(v);
}

/** An email address: a mailto link once resolved, a highlight until then. */
export function Email({ v }: { v: string }) {
  return isResolved(v) ? <a href={`mailto:${v}`}>{v}</a> : <T v={v} />;
}

/** A phone number: a tel link once resolved, a highlight until then. */
export function Tel({ v }: { v: string }) {
  return isResolved(v) ? <a href={`tel:${v.replace(/[^+\d]/g, '')}`}>{v}</a> : <T v={v} />;
}

/** Every string value in the config, for the banner count. */
function allConfigStrings(): string[] {
  const out: string[] = [];
  const walk = (x: unknown) => {
    if (typeof x === 'string') out.push(x);
    else if (Array.isArray(x)) x.forEach(walk);
    else if (x && typeof x === 'object' && !(x instanceof RegExp)) Object.values(x).forEach(walk);
  };
  walk([
    cfg.LAST_UPDATED,
    cfg.BUSINESS,
    cfg.CONTACT,
    cfg.TERMS,
    cfg.REFUND,
    cfg.TAX,
    cfg.PRIVACY,
    cfg.SALES_COUNTRIES_CONFIRMED,
  ]);
  return out;
}

export function unresolvedTokenNames(): string[] {
  const names = new Set<string>();
  for (const v of allConfigStrings()) for (const m of v.matchAll(tokenRe())) names.add(m[1]);
  return [...names].sort();
}

/** Shown on every legal page until the texts are approved and complete. */
export function DraftBanner() {
  const open = unresolvedTokenNames().length;
  if (cfg.APPROVED_FOR_PUBLICATION && open === 0) return null;
  return (
    <div className={s.draft} role="note">
      <p>
        <strong>DRAFT, for review by the client and their lawyer or accountant.</strong> Not yet
        approved. It is not legal advice and must not be relied on as final.
      </p>
      <p>
        {open > 0
          ? `${open} item${open === 1 ? '' : 's'} still to be supplied ${open === 1 ? 'is' : 'are'} shown highlighted in yellow.`
          : 'All items are filled in; awaiting final approval.'}
      </p>
    </div>
  );
}

export type Section = { id: string; title: string; body: React.ReactNode };

/**
 * A data table that scrolls inside its own box on a narrow phone. Without
 * `head` it is a label/value table and the first cell of each row is a row
 * header.
 */
export function Table({ head, rows }: { head?: string[]; rows: React.ReactNode[][] }) {
  return (
    <div className={s.tableWrap}>
      <table className={s.table}>
        {head && (
          <thead>
            <tr>
              {head.map((h, i) => (
                <th key={i} scope="col">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
        )}
        <tbody>
          {rows.map((r, i) => (
            <tr key={i}>
              {r.map((c, j) =>
                !head && j === 0 ? (
                  <th key={j} scope="row">
                    {c}
                  </th>
                ) : (
                  <td key={j}>{c}</td>
                ),
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function SafetyBox({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <aside className={s.safety} aria-label={title}>
      <p className={s.boxTitle}>{title}</p>
      {children}
    </aside>
  );
}

export function Price({ children }: { children: React.ReactNode }) {
  return <span className={s.price}>{children}</span>;
}

/**
 * The document shell: title, version line, summary box, contents, sections,
 * version history.
 */
export function LegalDoc({
  title,
  intro,
  summaryTitle = 'The short version',
  summary,
  afterSummary,
  sections,
}: {
  title: string;
  intro: React.ReactNode;
  summaryTitle?: string;
  summary: React.ReactNode;
  afterSummary?: React.ReactNode;
  sections: Section[];
}) {
  return (
    <article className={s.doc}>
      <h1 className={s.h1}>{title}</h1>
      <p className={s.meta}>
        Version {cfg.LEGAL_VERSION} · Last updated <T v={cfg.LAST_UPDATED} />
      </p>
      <p>{intro}</p>

      <section className={s.summary} aria-label={summaryTitle}>
        <h2 className={s.boxTitle}>{summaryTitle}</h2>
        {summary}
      </section>

      {afterSummary}

      <nav className={s.toc} aria-label="Contents">
        <ol>
          {sections.map((sec, i) => (
            <li key={sec.id}>
              <a href={`#${sec.id}`}>
                {i + 1}. {sec.title}
              </a>
            </li>
          ))}
        </ol>
      </nav>

      {sections.map((sec, i) => (
        <section key={sec.id} aria-labelledby={`h-${sec.id}`}>
          <h2 id={sec.id} className={s.h2}>
            <span id={`h-${sec.id}`}>
              {i + 1}. {sec.title}
            </span>
          </h2>
          {sec.body}
        </section>
      ))}

      <h2 id="version-history" className={s.h2}>
        Version history
      </h2>
      <ul>
        {cfg.CHANGELOG.map((c) => (
          <li key={c.version}>
            <strong>{c.version}</strong> ({c.date}): {c.note}
          </li>
        ))}
      </ul>
    </article>
  );
}

export function H3({ children }: { children: React.ReactNode }) {
  return <h3 className={s.h3}>{children}</h3>;
}

/** Footer navigation across every legal page. */
export function LegalNav() {
  return (
    <nav className={s.nav} aria-label="Policies">
      {LEGAL_PAGES.map((p) => (
        <Link key={p.href} href={p.href}>
          {p.label}
        </Link>
      ))}
    </nav>
  );
}

export { s as legalStyles };
