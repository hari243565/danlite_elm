import fs from 'fs';
import path from 'path';

export const dynamic = 'force-dynamic';

const C = {
  bg: '#07090E',
  surface: '#0D1117',
  card: '#131922',
  border: '#1C2A3A',
  text: '#EEF2F8',
  muted: '#607080',
  cyan: '#00CAFF',
  green: '#00E39C',
  amber: '#FF8A00',
  red: '#FF3D3D',
} as const;

type Phase = {
  id: string;
  name: string;
  status: string;
  tag: string;
  verify: string;
};

type PhasesFile = {
  project: string;
  updated: string;
  phases: Phase[];
};

const ENV_VARS = [
  'NEXT_PUBLIC_SUPABASE_URL',
  'NEXT_PUBLIC_SUPABASE_ANON_KEY',
  'RAZORPAY_KEY_ID',
  'RAZORPAY_KEY_SECRET',
  'RAZORPAY_WEBHOOK_SECRET',
  'RESEND_API_KEY',
  'MSG91_AUTH_KEY',
] as const;

// Only ever leaks a boolean. The value itself never crosses the server boundary.
function isSet(name: string): boolean {
  const v = process.env[name];
  return typeof v === 'string' && v.length > 0;
}

function readPhases(): { data: PhasesFile | null; error: string | null } {
  try {
    const file = path.join(process.cwd(), 'phases.json');
    const raw = fs.readFileSync(file, 'utf8');
    return { data: JSON.parse(raw) as PhasesFile, error: null };
  } catch (e) {
    return { data: null, error: e instanceof Error ? e.message : String(e) };
  }
}

type Phase1Test = {
  id: number;
  name: string;
  result: string;
};

type Phase1Report = {
  phase: string;
  name: string;
  generated: string;
  region: string;
  tables: string[];
  rls_enabled_on: number;
  client_write_paths_to_licences: number;
  client_write_paths_to_payments: number;
  tests: Phase1Test[];
};

function readPhase1(): Phase1Report | null {
  try {
    const file = path.join(process.cwd(), 'phase1-report.json');
    const raw = fs.readFileSync(file, 'utf8');
    return JSON.parse(raw) as Phase1Report;
  } catch {
    // Absent until the phase has been run — the panel renders a muted card.
    return null;
  }
}

type Phase2Check = {
  id: number;
  name: string;
  result: string;
};

type Phase2Screen = {
  id: number;
  name: string;
  route: string;
  result: string;
};

type Phase2Report = {
  phase: string;
  name: string;
  generated: string;
  token_storage_backend: string;
  shared_preferences_for_tokens: boolean;
  pkce_verifier_storage: string;
  otp_routing: string;
  build_note?: string;
  analyze: { new_errors: number; new_warnings: number; pre_existing_issues: number };
  screens: Phase2Screen[];
  checks: Phase2Check[];
};

function readPhase2(): Phase2Report | null {
  try {
    const file = path.join(process.cwd(), 'phase2-report.json');
    const raw = fs.readFileSync(file, 'utf8');
    return JSON.parse(raw) as Phase2Report;
  } catch {
    // Absent until the phase has been run — the panel renders a muted card.
    return null;
  }
}

type Phase3Check = {
  id: number;
  name: string;
  result: string;
};

type Phase3Report = {
  phase: string;
  name: string;
  generated: string;
  signature_algorithm: string;
  public_key_base64: string;
  private_key_location: string;
  private_key_sha256_fingerprint: string;
  signing_path_used: string;
  signing_path_note: string;
  function_url: string;
  token_ttl_seconds: number;
  canonical_signing_string: string;
  canonical_note: string;
  row_counts: {
    auth_users: number;
    profiles: number;
    licences: number;
    parity: boolean;
    users_missing_licence: number;
  };
  offline_grace_explained: string;
  clock_tamper_explained: string;
  gating: string;
  analyze: { new_errors: number; new_warnings: number; pre_existing_issues: number };
  deviations: string[];
  checks: Phase3Check[];
};

function readPhase3(): Phase3Report | null {
  try {
    const file = path.join(process.cwd(), 'phase3-report.json');
    const raw = fs.readFileSync(file, 'utf8');
    return JSON.parse(raw) as Phase3Report;
  } catch {
    // Absent until the phase has been run — the panel renders a muted card.
    return null;
  }
}

type Phase4Check = {
  id: number;
  name: string;
  result: string;
};

type Phase4Page = {
  route: string;
  purpose: string;
  state: string;
};

type Phase4Report = {
  phase: string;
  name: string;
  generated: string;
  portal_framework: string;
  supabase_ssr_package: string;
  pages: Phase4Page[];
  noindex_layers: {
    layer_1_robots_txt: string;
    layer_2_meta_tag: string;
    layer_3_http_header: string;
    all_three_verified: boolean;
  };
  rate_limiting: {
    primary_db_backed: string;
    logs_blocked_attempts_too: boolean;
    identifier_storage: string;
    secondary_in_process: string;
    independent_of_cloudflare: boolean;
  };
  gst: {
    treatment: string;
    rate_percent: number;
    exports_zero_rated: boolean;
    WARNING: string;
  };
  razorpay: string;
  session_bridge: {
    mechanism: string;
    token_ttl_minutes: number;
    token_storage: string;
    supabase_auth_emails_untouched: boolean;
    email_transport: string;
  };
  app_untouched: {
    files_changed_under_lib: number;
    files_changed_under_android: number;
    statement: string;
  };
  deviations: string[];
  open_items_for_owner: string[];
  checks: Phase4Check[];
};

function readPhase4(): Phase4Report | null {
  try {
    const file = path.join(process.cwd(), 'phase4-report.json');
    const raw = fs.readFileSync(file, 'utf8');
    return JSON.parse(raw) as Phase4Report;
  } catch {
    // Absent until the phase has been run — the panel renders a muted card.
    return null;
  }
}

function statusPill(status: string) {
  const map: Record<string, { fg: string; label: string }> = {
    done: { fg: C.green, label: 'done' },
    in_progress: { fg: C.amber, label: 'in progress' },
    pending: { fg: C.muted, label: 'pending' },
  };
  const s = map[status] ?? { fg: C.muted, label: status };
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '3px 10px',
        borderRadius: 999,
        fontSize: 12,
        fontWeight: 600,
        letterSpacing: 0.3,
        color: s.fg,
        // 12% alpha of the pill's own colour
        backgroundColor: `${s.fg}1F`,
        whiteSpace: 'nowrap',
      }}
    >
      {s.label}
    </span>
  );
}

export default function MissionControl() {
  const { data, error } = readPhases();
  const p1 = readPhase1();
  const p2 = readPhase2();
  const p3 = readPhase3();
  const p4 = readPhase4();

  const shell = (children: React.ReactNode) => (
    <main
      style={{
        minHeight: '100vh',
        width: '100%',
        backgroundColor: C.bg,
        color: C.text,
        fontFamily:
          'ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif',
        padding: '40px 24px 64px',
        boxSizing: 'border-box',
      }}
    >
      <div style={{ maxWidth: 1080, margin: '0 auto' }}>{children}</div>
    </main>
  );

  if (!data) {
    return shell(
      <div
        style={{
          backgroundColor: C.card,
          border: `1px solid ${C.red}`,
          borderRadius: 12,
          padding: 24,
        }}
      >
        <h1 style={{ color: C.red, fontSize: 20, fontWeight: 700, margin: 0 }}>
          Could not read phases.json
        </h1>
        <p style={{ color: C.text, marginTop: 12, marginBottom: 0, fontSize: 14 }}>
          Expected the file at <code>{path.join(process.cwd(), 'phases.json')}</code>. The build
          progress table cannot be rendered until it is readable and valid JSON.
        </p>
        <p
          style={{
            color: C.muted,
            marginTop: 12,
            marginBottom: 0,
            fontSize: 13,
            fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
          }}
        >
          {error}
        </p>
      </div>
    );
  }

  const phases = Array.isArray(data.phases) ? data.phases : [];
  const total = phases.length;
  const complete = phases.filter((p) => p.status === 'done').length;
  const pct = total > 0 ? Math.round((complete / total) * 100) : 0;

  return shell(
    <>
      {/* ---------------- Header ---------------- */}
      <header style={{ marginBottom: 32 }}>
        <h1 style={{ fontSize: 26, fontWeight: 700, margin: 0, letterSpacing: -0.2 }}>
          {data.project}
        </h1>
        <p style={{ color: C.muted, fontSize: 13, margin: '6px 0 0' }}>
          Updated {data.updated}
        </p>

        <div style={{ marginTop: 20 }}>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'baseline',
              fontSize: 13,
              marginBottom: 8,
            }}
          >
            <span style={{ color: C.muted }}>
              {complete} of {total} phases complete
            </span>
            <span style={{ color: C.green, fontWeight: 700 }}>{pct}%</span>
          </div>
          <div
            style={{
              height: 8,
              width: '100%',
              backgroundColor: C.border,
              borderRadius: 999,
              overflow: 'hidden',
            }}
          >
            <div
              style={{
                height: '100%',
                width: `${pct}%`,
                backgroundColor: C.green,
                borderRadius: 999,
              }}
            />
          </div>
        </div>
      </header>

      {/* ---------------- Phase table ---------------- */}
      <section
        style={{
          backgroundColor: C.surface,
          border: `1px solid ${C.border}`,
          borderRadius: 12,
          overflowX: 'auto',
          marginBottom: 28,
        }}
      >
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14 }}>
          <thead>
            <tr>
              {['ID', 'Phase', 'Status', 'Git tag', 'Verified by'].map((h) => (
                <th
                  key={h}
                  style={{
                    textAlign: 'left',
                    padding: '14px 16px',
                    color: C.cyan,
                    fontSize: 11,
                    fontWeight: 700,
                    letterSpacing: 0.8,
                    textTransform: 'uppercase',
                    borderBottom: `1px solid ${C.border}`,
                    whiteSpace: 'nowrap',
                  }}
                >
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {phases.map((p, i) => (
              <tr
                key={p.id}
                style={{
                  borderTop: i === 0 ? 'none' : `1px solid ${C.border}`,
                  backgroundColor: p.status === 'done' ? C.card : 'transparent',
                }}
              >
                <td
                  style={{
                    padding: '14px 16px',
                    color: C.muted,
                    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                    whiteSpace: 'nowrap',
                    verticalAlign: 'top',
                  }}
                >
                  {p.id}
                </td>
                <td style={{ padding: '14px 16px', fontWeight: 600, verticalAlign: 'top' }}>
                  {p.name}
                </td>
                <td style={{ padding: '14px 16px', verticalAlign: 'top' }}>
                  {statusPill(p.status)}
                </td>
                <td
                  style={{
                    padding: '14px 16px',
                    color: C.cyan,
                    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                    fontSize: 13,
                    whiteSpace: 'nowrap',
                    verticalAlign: 'top',
                  }}
                >
                  {p.tag}
                </td>
                <td
                  style={{
                    padding: '14px 16px',
                    color: C.muted,
                    fontSize: 12.5,
                    lineHeight: 1.5,
                    minWidth: 260,
                    verticalAlign: 'top',
                  }}
                >
                  {p.verify}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      {/* ---------------- Environment ---------------- */}
      <section
        style={{
          backgroundColor: C.surface,
          border: `1px solid ${C.border}`,
          borderRadius: 12,
          padding: 20,
          marginBottom: 28,
        }}
      >
        <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 4px' }}>Environment</h2>
        <p style={{ color: C.muted, fontSize: 12.5, margin: '0 0 16px', lineHeight: 1.5 }}>
          Presence only — values are never read into the page. All of these are expected empty
          until Phase 1 (Supabase) and Phase 5 (Razorpay).
        </p>
        <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
          {ENV_VARS.map((name) => {
            const set = isSet(name);
            return (
              <li
                key={name}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 12,
                  padding: '9px 0',
                  borderTop: `1px solid ${C.border}`,
                  fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                  fontSize: 13,
                }}
              >
                <span
                  style={{
                    width: 16,
                    textAlign: 'center',
                    color: set ? C.green : C.muted,
                    fontWeight: 700,
                  }}
                >
                  {set ? '✓' : '–'}
                </span>
                <span style={{ color: set ? C.text : C.muted }}>{name}</span>
              </li>
            );
          })}
        </ul>
      </section>

      {/* ---------------- Phase 1 — Database Security ---------------- */}
      <section
        style={{
          backgroundColor: C.surface,
          border: `1px solid ${C.border}`,
          borderRadius: 12,
          padding: 20,
          marginBottom: 28,
        }}
      >
        <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 4px' }}>
          Phase 1 — Database Security
        </h2>

        {!p1 ? (
          <p style={{ color: C.muted, fontSize: 12.5, margin: '8px 0 0', lineHeight: 1.5 }}>
            Not yet run. <code>phase1-report.json</code> will appear here once the Supabase schema
            and RLS verification have been executed.
          </p>
        ) : (
          <>
            <p style={{ color: C.muted, fontSize: 12.5, margin: '0 0 16px', lineHeight: 1.5 }}>
              Row Level Security verified against the live project on {p1.generated}.
            </p>

            {/* Region + table-count badges */}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 14 }}>
              {[
                { label: 'Region', value: p1.region },
                { label: 'Tables', value: `${p1.tables.length}` },
                { label: 'RLS enabled on', value: `${p1.rls_enabled_on} of ${p1.tables.length}` },
              ].map((b) => (
                <span
                  key={b.label}
                  style={{
                    display: 'inline-block',
                    padding: '5px 11px',
                    borderRadius: 8,
                    border: `1px solid ${C.border}`,
                    backgroundColor: C.card,
                    fontSize: 12,
                    color: C.muted,
                    whiteSpace: 'nowrap',
                  }}
                >
                  {b.label}{' '}
                  <span style={{ color: C.text, fontWeight: 700 }}>{b.value}</span>
                </span>
              ))}
            </div>

            {/* The anti-fraud invariant: no client can write money or entitlement */}
            {[
              { label: 'licences', n: p1.client_write_paths_to_licences },
              { label: 'payments', n: p1.client_write_paths_to_payments },
            ].map((w) => (
              <p
                key={w.label}
                style={{
                  margin: '0 0 6px',
                  fontSize: 13,
                  fontWeight: 600,
                  color: w.n === 0 ? C.green : C.red,
                  fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                }}
              >
                Client write paths to {w.label}: {w.n}
              </p>
            ))}

            {/* Eight RLS assertions */}
            <ul style={{ listStyle: 'none', margin: '16px 0 0', padding: 0 }}>
              {p1.tests.map((t) => {
                const ok = t.result === 'pass';
                return (
                  <li
                    key={t.id}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 12,
                      padding: '9px 0',
                      borderTop: `1px solid ${C.border}`,
                      fontSize: 13,
                    }}
                  >
                    <span
                      style={{
                        width: 16,
                        textAlign: 'center',
                        color: ok ? C.green : C.red,
                        fontWeight: 700,
                      }}
                    >
                      {ok ? '✓' : '✗'}
                    </span>
                    <span
                      style={{
                        color: C.muted,
                        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                        fontSize: 12,
                        minWidth: 18,
                      }}
                    >
                      {t.id}
                    </span>
                    <span style={{ color: ok ? C.text : C.red }}>{t.name}</span>
                  </li>
                );
              })}
            </ul>
          </>
        )}
      </section>

      {/* ---------------- Phase 2 — Authentication ---------------- */}
      <section
        style={{
          backgroundColor: C.surface,
          border: `1px solid ${C.border}`,
          borderRadius: 12,
          padding: 20,
          marginBottom: 28,
        }}
      >
        <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 4px' }}>
          Phase 2 — Authentication
        </h2>

        {!p2 ? (
          <p style={{ color: C.muted, fontSize: 12.5, margin: '8px 0 0', lineHeight: 1.5 }}>
            Not yet run. <code>phase2-report.json</code> will appear here once the auth screens
            and secure token storage have been built.
          </p>
        ) : (
          <>
            <p style={{ color: C.muted, fontSize: 12.5, margin: '0 0 16px', lineHeight: 1.5 }}>
              Sign-up, log-in and OTP verification wired to Supabase on {p2.generated}.{' '}
              {p2.otp_routing}.
            </p>

            {/* Storage + analyze badges */}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 14 }}>
              {[
                { label: 'Screens', value: `${p2.screens.length}` },
                { label: 'Token store', value: p2.token_storage_backend },
                { label: 'New analyze errors', value: `${p2.analyze.new_errors}` },
              ].map((b) => (
                <span
                  key={b.label}
                  style={{
                    display: 'inline-block',
                    padding: '5px 11px',
                    borderRadius: 8,
                    border: `1px solid ${C.border}`,
                    backgroundColor: C.card,
                    fontSize: 12,
                    color: C.muted,
                    whiteSpace: 'nowrap',
                  }}
                >
                  {b.label} <span style={{ color: C.text, fontWeight: 700 }}>{b.value}</span>
                </span>
              ))}
            </div>

            {/* The Phase 2 invariant: no auth token in plaintext preferences */}
            <p
              style={{
                margin: '0 0 6px',
                fontSize: 13,
                fontWeight: 600,
                color: p2.shared_preferences_for_tokens ? C.red : C.green,
                fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
              }}
            >
              Tokens in shared_preferences: {String(p2.shared_preferences_for_tokens)}
            </p>
            <p
              style={{
                margin: '0 0 6px',
                fontSize: 13,
                fontWeight: 600,
                color: C.green,
                fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
              }}
            >
              PKCE verifier store: {p2.pkce_verifier_storage}
            </p>

            {p2.build_note && (
              <p
                style={{
                  margin: '12px 0 0',
                  padding: '10px 12px',
                  borderRadius: 8,
                  border: `1px solid ${C.amber}`,
                  color: C.amber,
                  fontSize: 12.5,
                  lineHeight: 1.5,
                }}
              >
                {p2.build_note}
              </p>
            )}

            {/* Screens delivered */}
            <ul style={{ listStyle: 'none', margin: '16px 0 0', padding: 0 }}>
              {p2.screens.map((s) => (
                <li
                  key={s.id}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 12,
                    padding: '9px 0',
                    borderTop: `1px solid ${C.border}`,
                    fontSize: 13,
                  }}
                >
                  <span style={{ width: 16, textAlign: 'center', color: C.green, fontWeight: 700 }}>
                    ✓
                  </span>
                  <span
                    style={{
                      color: C.cyan,
                      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                      fontSize: 12,
                      minWidth: 62,
                    }}
                  >
                    {s.route}
                  </span>
                  <span style={{ color: C.text }}>{s.name}</span>
                </li>
              ))}
            </ul>

            {/* Security assertions */}
            <ul style={{ listStyle: 'none', margin: '16px 0 0', padding: 0 }}>
              {p2.checks.map((t) => {
                const ok = t.result === 'pass';
                return (
                  <li
                    key={t.id}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 12,
                      padding: '9px 0',
                      borderTop: `1px solid ${C.border}`,
                      fontSize: 13,
                    }}
                  >
                    <span
                      style={{
                        width: 16,
                        textAlign: 'center',
                        color: ok ? C.green : C.red,
                        fontWeight: 700,
                      }}
                    >
                      {ok ? '✓' : '✗'}
                    </span>
                    <span
                      style={{
                        color: C.muted,
                        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                        fontSize: 12,
                        minWidth: 18,
                      }}
                    >
                      {t.id}
                    </span>
                    <span style={{ color: ok ? C.text : C.red }}>{t.name}</span>
                  </li>
                );
              })}
            </ul>
          </>
        )}
      </section>

      {/* ---------------- Phase 3 — Entitlement Token ---------------- */}
      <section
        style={{
          backgroundColor: C.surface,
          border: `1px solid ${C.border}`,
          borderRadius: 12,
          padding: 20,
          marginBottom: 28,
        }}
      >
        <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 4px' }}>
          Phase 3 — Entitlement Token
        </h2>

        {!p3 ? (
          <p style={{ color: C.muted, fontSize: 12.5, margin: '8px 0 0', lineHeight: 1.5 }}>
            Not yet run. <code>phase3-report.json</code> will appear here once the signed
            entitlement token and its offline grace window have been built.
          </p>
        ) : (
          <>
            <p style={{ color: C.muted, fontSize: 12.5, margin: '0 0 16px', lineHeight: 1.5 }}>
              Signed licence statements issued and verified on {p3.generated}. {p3.gating}
            </p>

            {/* Algorithm + grace + signing-path badges */}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 14 }}>
              {[
                { label: 'Algorithm', value: p3.signature_algorithm },
                {
                  label: 'Offline grace',
                  value: `${Math.round(p3.token_ttl_seconds / 86400)} days`,
                },
                { label: 'Signing path', value: p3.signing_path_used },
                { label: 'New analyze errors', value: `${p3.analyze.new_errors}` },
              ].map((b) => (
                <span
                  key={b.label}
                  style={{
                    display: 'inline-block',
                    padding: '5px 11px',
                    borderRadius: 8,
                    border: `1px solid ${C.border}`,
                    backgroundColor: C.card,
                    fontSize: 12,
                    color: C.muted,
                    whiteSpace: 'nowrap',
                  }}
                >
                  {b.label} <span style={{ color: C.text, fontWeight: 700 }}>{b.value}</span>
                </span>
              ))}
            </div>

            {/* Key material. The public key is safe to show — that is its whole
                purpose. The private key is represented ONLY by its fingerprint. */}
            <div
              style={{
                border: `1px solid ${C.border}`,
                backgroundColor: C.card,
                borderRadius: 8,
                padding: '12px 14px',
                marginBottom: 14,
              }}
            >
              {[
                { k: 'Public key (safe to publish)', v: p3.public_key_base64, c: C.green },
                { k: 'Private key SHA-256', v: p3.private_key_sha256_fingerprint, c: C.muted },
                { k: 'Private key location', v: p3.private_key_location, c: C.muted },
              ].map((row) => (
                <div key={row.k} style={{ marginBottom: 8 }}>
                  <div style={{ color: C.muted, fontSize: 11, marginBottom: 3 }}>{row.k}</div>
                  <div
                    style={{
                      color: row.c,
                      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                      fontSize: 12,
                      wordBreak: 'break-all',
                      lineHeight: 1.5,
                    }}
                  >
                    {row.v}
                  </div>
                </div>
              ))}
            </div>

            {/* Row-count parity: every user must own exactly one licence row */}
            <p
              style={{
                margin: '0 0 6px',
                fontSize: 13,
                fontWeight: 600,
                color: p3.row_counts.parity ? C.green : C.red,
                fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
              }}
            >
              profiles {p3.row_counts.profiles} = licences {p3.row_counts.licences}
              {'  ·  '}users missing a licence: {p3.row_counts.users_missing_licence}
            </p>
            <p
              style={{
                margin: '0 0 6px',
                fontSize: 13,
                fontWeight: 600,
                color: C.green,
                fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
              }}
            >
              Canonical signing string: {p3.canonical_signing_string}
            </p>

            {/* The two mechanisms the owner needs to be able to explain */}
            {[
              { title: 'Working offline', body: p3.offline_grace_explained },
              { title: 'Turning the clock back', body: p3.clock_tamper_explained },
              { title: 'Why not sign the JSON', body: p3.canonical_note },
            ].map((b) => (
              <div key={b.title} style={{ marginTop: 14 }}>
                <div
                  style={{
                    color: C.cyan,
                    fontSize: 11,
                    fontWeight: 700,
                    letterSpacing: 0.8,
                    textTransform: 'uppercase',
                    marginBottom: 5,
                  }}
                >
                  {b.title}
                </div>
                <p
                  style={{
                    color: C.muted,
                    fontSize: 12.5,
                    lineHeight: 1.6,
                    margin: 0,
                  }}
                >
                  {b.body}
                </p>
              </div>
            ))}

            {/* Anything that did not go exactly to plan */}
            {p3.deviations.length > 0 && (
              <div style={{ marginTop: 16 }}>
                {p3.deviations.map((d, i) => (
                  <p
                    key={i}
                    style={{
                      margin: '0 0 8px',
                      padding: '10px 12px',
                      borderRadius: 8,
                      border: `1px solid ${C.amber}`,
                      color: C.amber,
                      fontSize: 12.5,
                      lineHeight: 1.5,
                    }}
                  >
                    {d}
                  </p>
                ))}
              </div>
            )}

            {/* Verification assertions */}
            <ul style={{ listStyle: 'none', margin: '16px 0 0', padding: 0 }}>
              {p3.checks.map((t) => {
                const ok = t.result === 'pass';
                return (
                  <li
                    key={t.id}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 12,
                      padding: '9px 0',
                      borderTop: `1px solid ${C.border}`,
                      fontSize: 13,
                    }}
                  >
                    <span
                      style={{
                        width: 16,
                        textAlign: 'center',
                        color: ok ? C.green : C.red,
                        fontWeight: 700,
                      }}
                    >
                      {ok ? '✓' : '✗'}
                    </span>
                    <span
                      style={{
                        color: C.muted,
                        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                        fontSize: 12,
                        minWidth: 18,
                      }}
                    >
                      {t.id}
                    </span>
                    <span style={{ color: ok ? C.text : C.red }}>{t.name}</span>
                  </li>
                );
              })}
            </ul>
          </>
        )}
      </section>

      {/* ---------------- Phase 4 — Billing Portal ---------------- */}
      <section
        style={{
          backgroundColor: C.surface,
          border: `1px solid ${C.border}`,
          borderRadius: 12,
          padding: 20,
          marginBottom: 28,
        }}
      >
        <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 4px' }}>
          Phase 4 — Billing Portal
        </h2>

        {!p4 ? (
          <p style={{ color: C.muted, fontSize: 12.5, margin: '8px 0 0', lineHeight: 1.5 }}>
            Not yet run. <code>phase4-report.json</code> will appear here once the billing portal
            and activation links have been built.
          </p>
        ) : (
          <>
            <p style={{ color: C.muted, fontSize: 12.5, margin: '0 0 16px', lineHeight: 1.5 }}>
              Activation links, session bridging and the four portal pages verified on{' '}
              {p4.generated}. {p4.portal_framework}.
            </p>

            {/* Headline badges */}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 14 }}>
              {[
                { label: 'Pages', value: `${p4.pages.length}` },
                { label: 'Link TTL', value: `${p4.session_bridge.token_ttl_minutes} min` },
                {
                  label: 'noindex layers',
                  value: p4.noindex_layers.all_three_verified ? '3 of 3' : 'INCOMPLETE',
                },
                { label: 'GST', value: `${p4.gst.treatment} ${p4.gst.rate_percent}%` },
              ].map((b) => (
                <span
                  key={b.label}
                  style={{
                    display: 'inline-block',
                    padding: '5px 11px',
                    borderRadius: 8,
                    border: `1px solid ${C.border}`,
                    backgroundColor: C.card,
                    fontSize: 12,
                    color: C.muted,
                    whiteSpace: 'nowrap',
                  }}
                >
                  {b.label} <span style={{ color: C.text, fontWeight: 700 }}>{b.value}</span>
                </span>
              ))}
            </div>

            {/* The headline constraint of this phase */}
            <p
              style={{
                margin: '0 0 6px',
                fontSize: 13,
                fontWeight: 600,
                color: p4.app_untouched.files_changed_under_lib === 0 ? C.green : C.red,
                fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
              }}
            >
              Flutter files changed under lib/: {p4.app_untouched.files_changed_under_lib}
              {'  ·  '}android/: {p4.app_untouched.files_changed_under_android}
            </p>

            {/* Routes delivered */}
            <ul style={{ listStyle: 'none', margin: '16px 0 0', padding: 0 }}>
              {p4.pages.map((pg) => (
                <li
                  key={pg.route}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 12,
                    padding: '9px 0',
                    borderTop: `1px solid ${C.border}`,
                    fontSize: 13,
                  }}
                >
                  <span
                    style={{
                      width: 16,
                      textAlign: 'center',
                      color: pg.state === 'draft' ? C.amber : C.green,
                      fontWeight: 700,
                    }}
                  >
                    {pg.state === 'draft' ? '~' : '✓'}
                  </span>
                  <span
                    style={{
                      color: C.cyan,
                      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                      fontSize: 12,
                      minWidth: 118,
                    }}
                  >
                    {pg.route}
                  </span>
                  <span style={{ color: C.text }}>{pg.purpose}</span>
                </li>
              ))}
            </ul>

            {/* Three search-invisibility layers */}
            <div style={{ marginTop: 16 }}>
              <div
                style={{
                  color: C.cyan,
                  fontSize: 11,
                  fontWeight: 700,
                  letterSpacing: 0.8,
                  textTransform: 'uppercase',
                  marginBottom: 5,
                }}
              >
                Search invisibility
              </div>
              {[
                p4.noindex_layers.layer_1_robots_txt,
                p4.noindex_layers.layer_2_meta_tag,
                p4.noindex_layers.layer_3_http_header,
              ].map((l, i) => (
                <p
                  key={i}
                  style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 5px' }}
                >
                  <span style={{ color: C.green, fontWeight: 700 }}>✓</span> {l}
                </p>
              ))}
            </div>

            {/* Razorpay honesty + GST warning */}
            {[
              { title: 'Razorpay', body: p4.razorpay, colour: C.amber },
              { title: 'GST — unconfirmed', body: p4.gst.WARNING, colour: C.amber },
            ].map((b) => (
              <p
                key={b.title}
                style={{
                  margin: '12px 0 0',
                  padding: '10px 12px',
                  borderRadius: 8,
                  border: `1px solid ${b.colour}`,
                  color: b.colour,
                  fontSize: 12.5,
                  lineHeight: 1.5,
                }}
              >
                <strong>{b.title}:</strong> {b.body}
              </p>
            ))}

            {/* Things the owner still has to decide */}
            <div style={{ marginTop: 16 }}>
              <div
                style={{
                  color: C.cyan,
                  fontSize: 11,
                  fontWeight: 700,
                  letterSpacing: 0.8,
                  textTransform: 'uppercase',
                  marginBottom: 5,
                }}
              >
                Needs a decision from you
              </div>
              {p4.open_items_for_owner.map((d, i) => (
                <p
                  key={i}
                  style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 6px' }}
                >
                  • {d}
                </p>
              ))}
            </div>

            {/* Anything that did not go exactly to plan */}
            {p4.deviations.length > 0 && (
              <div style={{ marginTop: 16 }}>
                <div
                  style={{
                    color: C.cyan,
                    fontSize: 11,
                    fontWeight: 700,
                    letterSpacing: 0.8,
                    textTransform: 'uppercase',
                    marginBottom: 5,
                  }}
                >
                  Deviations from the written plan
                </div>
                {p4.deviations.map((d, i) => (
                  <p
                    key={i}
                    style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 6px' }}
                  >
                    • {d}
                  </p>
                ))}
              </div>
            )}

            {/* Verification assertions */}
            <ul style={{ listStyle: 'none', margin: '16px 0 0', padding: 0 }}>
              {p4.checks.map((t) => {
                const ok = t.result === 'pass';
                return (
                  <li
                    key={t.id}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 12,
                      padding: '9px 0',
                      borderTop: `1px solid ${C.border}`,
                      fontSize: 13,
                    }}
                  >
                    <span
                      style={{
                        width: 16,
                        textAlign: 'center',
                        color: ok ? C.green : C.red,
                        fontWeight: 700,
                      }}
                    >
                      {ok ? '✓' : '✗'}
                    </span>
                    <span
                      style={{
                        color: C.muted,
                        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
                        fontSize: 12,
                        minWidth: 18,
                      }}
                    >
                      {t.id}
                    </span>
                    <span style={{ color: ok ? C.text : C.red }}>{t.name}</span>
                  </li>
                );
              })}
            </ul>
          </>
        )}
      </section>

      {/* ---------------- Footer ---------------- */}
      <footer
        style={{
          border: `1px solid ${C.red}`,
          borderRadius: 12,
          padding: '14px 18px',
          color: C.red,
          fontSize: 13,
          fontWeight: 600,
          letterSpacing: 0.2,
          textAlign: 'center',
        }}
      >
        DEV ONLY — this page is never deployed. Local diagnostics for the Danlite build.
      </footer>
    </>
  );
}
