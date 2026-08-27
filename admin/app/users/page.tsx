// ══════════════════════════════════════════════════════════════════════════
// /users — searchable, paginated customer list.
//
// Search state lives in the URL, not in component state. That is deliberate:
// an admin who finds the right customer can send that URL to the other admin,
// or bookmark it, or hit reload without losing the search. A useState search
// box would be marginally snappier and lose all three.
//
// NOTE ON searchParams: in the installed Next.js (16.3.0) it is a Promise and
// must be awaited. Verified against the installed docs rather than assumed —
// the same change caught the billing portal in Phase 4.
// ══════════════════════════════════════════════════════════════════════════

import Link from 'next/link';
import type { Metadata } from 'next';
import { callAdminFn, getAdminSession, type UserList } from '@/lib/admin-api';
import { C, FONT, fullName, inputStyle, MONO, when } from '@/lib/theme';
import { NOINDEX } from '@/lib/seo';
import { ErrorCard, Section, Shell, StatusPill, Table, tdStyle } from '../shell';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Users — Danlite ELM Admin',
  robots: NOINDEX,
};

const STATUSES = ['', 'active', 'inactive', 'revoked', 'refunded'];

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const session = await getAdminSession();
  if (!session) return null;

  const sp = await searchParams;
  const search = typeof sp.q === 'string' ? sp.q : '';
  const status = typeof sp.status === 'string' ? sp.status : '';
  const page = Math.max(0, Number(typeof sp.page === 'string' ? sp.page : 0) || 0);

  const result = await callAdminFn<UserList>('admin-list-users', {
    search,
    status: status || undefined,
    page,
  });

  if (!result.ok) {
    return (
      <Shell email={session.email} active="/users">
        <ErrorCard status={result.status} message={result.error} />
      </Shell>
    );
  }

  const { users, total, has_more, page_size } = result.data;
  const from = total === 0 ? 0 : page * page_size + 1;
  const to = page * page_size + users.length;

  const pageHref = (p: number) => {
    const qs = new URLSearchParams();
    if (search) qs.set('q', search);
    if (status) qs.set('status', status);
    if (p > 0) qs.set('page', String(p));
    const s = qs.toString();
    return s ? `/users?${s}` : '/users';
  };

  return (
    <Shell email={session.email} active="/users">
      <Section
        title="Users"
        subtitle={
          total === 0
            ? 'No matching users.'
            : `Showing ${from}–${to} of ${total} matching user${total === 1 ? '' : 's'}.`
        }
      >
        {/* A plain GET form. No JavaScript needed to search, and the result
            is a shareable URL. */}
        <form
          method="get"
          style={{ display: 'flex', gap: 9, marginBottom: 14, flexWrap: 'wrap' }}
        >
          <input
            type="search"
            name="q"
            defaultValue={search}
            placeholder="Search name, email, phone or country…"
            style={{ ...inputStyle, flex: '1 1 260px', width: 'auto', fontSize: 13.5 }}
          />
          <select
            name="status"
            defaultValue={status}
            style={{
              ...inputStyle,
              width: 'auto',
              flex: '0 0 auto',
              fontSize: 13.5,
              cursor: 'pointer',
            }}
          >
            {STATUSES.map((s) => (
              <option key={s || 'any'} value={s}>
                {s === '' ? 'Any licence status' : s}
              </option>
            ))}
          </select>
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
            Search
          </button>
          {search || status ? (
            <Link
              href="/users"
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
          headers={['Name', 'Email', 'Phone', 'Country', 'Licence', 'Purchased', 'Signed up', '']}
          isEmpty={users.length === 0}
          empty={
            search || status
              ? 'No users match that search.'
              : 'No users yet.'
          }
        >
          {users.map((u) => (
            <tr key={u.id}>
              {/* Name first: it is what an operator handling a support email
                  actually has in front of them. Accounts created before this
                  field existed have none, and show an em-dash rather than a
                  guess — their email is in the next column either way. */}
              <td style={tdStyle}>{fullName(u) ?? '—'}</td>
              <td style={tdStyle}>
                <Link href={`/users/${u.id}`} style={{ color: C.cyan, textDecoration: 'none' }}>
                  {u.email ?? '—'}
                </Link>
                {u.deleted_at ? (
                  <span style={{ color: C.red, fontSize: 10.5, marginLeft: 7, fontWeight: 700 }}>
                    DELETED
                  </span>
                ) : null}
              </td>
              <td style={{ ...tdStyle, fontFamily: MONO, color: C.muted }}>{u.phone ?? '—'}</td>
              <td style={tdStyle}>{u.country_code ?? '—'}</td>
              <td style={tdStyle}>
                <StatusPill status={u.licence_status} />
              </td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(u.purchased_at)}
              </td>
              <td style={{ ...tdStyle, color: C.muted, whiteSpace: 'nowrap' }}>
                {when(u.created_at)}
              </td>
              <td style={tdStyle}>
                <Link
                  href={`/users/${u.id}`}
                  style={{ color: C.muted, textDecoration: 'none', fontSize: 12 }}
                >
                  View →
                </Link>
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
