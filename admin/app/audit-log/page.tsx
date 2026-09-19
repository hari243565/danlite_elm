// ══════════════════════════════════════════════════════════════════════════
// /audit-log — a readable rendering of the existing audit_log table.
//
// READ ONLY. audit_log's schema is untouched by this phase and nothing in
// this app writes to it. The action filter is built from the actions actually
// present in the log rather than a hardcoded list, so it stays correct as
// other functions start logging new action types.
// ══════════════════════════════════════════════════════════════════════════

import Link from 'next/link';
import type { Metadata } from 'next';
import { callAdminFn, getAdminSession, type AuditList } from '@/lib/admin-api';
import { C, FONT, inputStyle, MONO, when } from '@/lib/theme';
import { NOINDEX } from '@/lib/seo';
import { ErrorCard, Section, Shell, Table, tdStyle } from '../shell';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Audit log — Danlite ELM Admin',
  robots: NOINDEX,
};

/** Renders the jsonb `detail` column compactly. Long payloads are clipped —
 *  the full row is one click away in the SQL editor, and a 4KB blob in a
 *  table cell makes the whole log unreadable. */
function Detail({ value }: { value: unknown }) {
  if (value === null || value === undefined) return <span style={{ color: C.muted }}>—</span>;

  let text: string;
  try {
    text = typeof value === 'string' ? value : JSON.stringify(value);
  } catch {
    text = String(value);
  }

  const clipped = text.length > 220;
  return (
    <span
      style={{ fontFamily: MONO, fontSize: 11, color: C.muted, wordBreak: 'break-word' }}
      title={clipped ? text : undefined}
    >
      {clipped ? `${text.slice(0, 220)}…` : text}
    </span>
  );
}

export default async function AuditLogPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const session = await getAdminSession();
  if (!session) return null;

  const sp = await searchParams;
  const action = typeof sp.action === 'string' ? sp.action : '';
  const userId = typeof sp.user_id === 'string' ? sp.user_id : '';
  const page = Math.max(0, Number(typeof sp.page === 'string' ? sp.page : 0) || 0);

  const result = await callAdminFn<AuditList>('admin-audit-log', {
    action,
    user_id: userId || undefined,
    page,
  });

  if (!result.ok) {
    return (
      <Shell email={session.email} active="/audit-log">
        <ErrorCard status={result.status} message={result.error} />
      </Shell>
    );
  }

  const { entries, known_actions, total, has_more, page_size } = result.data;
  const from = total === 0 ? 0 : page * page_size + 1;
  const to = page * page_size + entries.length;

  const pageHref = (p: number) => {
    const qs = new URLSearchParams();
    if (action) qs.set('action', action);
    if (userId) qs.set('user_id', userId);
    if (p > 0) qs.set('page', String(p));
    const s = qs.toString();
    return s ? `/audit-log?${s}` : '/audit-log';
  };

  return (
    <Shell email={session.email} active="/audit-log">
      <Section
        title="Audit log"
        subtitle={
          total === 0
            ? 'No matching entries.'
            : `Showing ${from}–${to} of ${total} entr${total === 1 ? 'y' : 'ies'}, newest first.`
        }
      >
        <form
          method="get"
          style={{ display: 'flex', gap: 9, marginBottom: 14, flexWrap: 'wrap' }}
        >
          <input
            type="search"
            name="action"
            defaultValue={action}
            placeholder="Filter by action…"
            list="known-actions"
            style={{ ...inputStyle, flex: '1 1 240px', width: 'auto', fontSize: 13.5 }}
          />
          <datalist id="known-actions">
            {known_actions.map((a) => (
              <option key={a} value={a} />
            ))}
          </datalist>
          <input
            type="search"
            name="user_id"
            defaultValue={userId}
            placeholder="Filter by user id…"
            style={{
              ...inputStyle,
              flex: '1 1 240px',
              width: 'auto',
              fontSize: 13,
              fontFamily: MONO,
            }}
          />
          <button
            type="submit"
            style={{
              padding: '12px 20px',
              borderRadius: 8,
              border: 'none',
              backgroundColor: C.cyan,
              color: C.bg,
              fontWeight: 700,
              fontSize: 13.5,
              fontFamily: FONT,
              cursor: 'pointer',
            }}
          >
            Filter
          </button>
          {action || userId ? (
            <Link
              href="/audit-log"
              style={{
                padding: '12px 16px',
                borderRadius: 8,
                border: `1px solid ${C.border}`,
                color: C.muted,
                fontSize: 13.5,
                textDecoration: 'none',
              }}
            >
              Clear
            </Link>
          ) : null}
        </form>

        <Table
          headers={['When', 'Action', 'User', 'Actor', 'IP', 'Detail']}
          isEmpty={entries.length === 0}
          empty={action || userId ? 'No entries match that filter.' : 'The audit log is empty.'}
        >
          {entries.map((e) => (
            <tr key={e.id}>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(e.created_at)}
              </td>
              <td style={{ ...tdStyle, fontFamily: MONO, fontSize: 11.5, color: C.cyan }}>
                {e.action}
              </td>
              <td style={tdStyle}>
                {e.user_id ? (
                  <Link href={`/users/${e.user_id}`} style={{ color: C.cyan, textDecoration: 'none' }}>
                    {e.email ?? e.user_id}
                  </Link>
                ) : (
                  <span style={{ color: C.muted }}>—</span>
                )}
              </td>
              {/* WHO DID IT, as distinct from who it was about. Null here
                  means the system acted (a webhook, the entitlement
                  function); an address means a named human did. Rendered
                  from actor_email rather than actor_user_id on purpose —
                  the email is the denormalised historical record and
                  survives that person leaving the allowlist, which is the
                  whole reason 20260823160000 stored both. */}
              <td style={{ ...tdStyle, fontSize: 12 }}>
                {e.actor_email ? (
                  <span style={{ color: C.text }}>{e.actor_email}</span>
                ) : (
                  <span style={{ color: C.muted }}>system</span>
                )}
              </td>
              <td style={{ ...tdStyle, fontFamily: MONO, fontSize: 11, color: C.muted }}>
                {e.ip ?? '—'}
              </td>
              <td style={{ ...tdStyle, maxWidth: 420 }}>
                <Detail value={e.detail} />
              </td>
            </tr>
          ))}
        </Table>

        {(page > 0 || has_more) && (
          <div style={{ display: 'flex', gap: 9, marginTop: 14, alignItems: 'center' }}>
            {page > 0 ? (
              <Link
                href={pageHref(page - 1)}
                style={{
                  padding: '8px 14px',
                  borderRadius: 8,
                  border: `1px solid ${C.border}`,
                  color: C.text,
                  fontSize: 12.5,
                  textDecoration: 'none',
                }}
              >
                ← Previous
              </Link>
            ) : null}
            {has_more ? (
              <Link
                href={pageHref(page + 1)}
                style={{
                  padding: '8px 14px',
                  borderRadius: 8,
                  border: `1px solid ${C.border}`,
                  color: C.text,
                  fontSize: 12.5,
                  textDecoration: 'none',
                }}
              >
                Next →
              </Link>
            ) : null}
            <span style={{ color: C.muted, fontSize: 12 }}>Page {page + 1}</span>
          </div>
        )}
      </Section>
    </Shell>
  );
}
