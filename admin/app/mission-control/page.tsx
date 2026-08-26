// ══════════════════════════════════════════════════════════════════════════
// /mission-control — the phase build dashboard.
//
// This screen used to be the billing portal's `/` route. It was moved here
// because it was reachable by anyone who typed the portal's address: the
// portal protects /checkout, /confirmation and /account by prefix, and `/`
// was on nobody's list. robots.txt and X-Robots-Tag kept it out of search
// results, which is not the same thing as keeping it out of a browser.
//
// What it renders is a full description of the system's security posture —
// the names of every Edge Function secret, the RLS and grant model, real
// payment and order ids, and a recorded note about the webhook secret's
// length. That is a briefing document for an attacker, and it belongs behind
// the same lock as every other screen in this tool.
//
// ── HOW THIS PAGE IS GATED, AND WHY IT NEEDS AN EXTRA STEP ───────────────
// Every other page here is gated by the data it asks for: /users, /payments
// and /audit-log render nothing until an admin-* Edge Function answers, and
// each of those re-reads public.admin_users before it does. proxy.ts is NOT
// that gate — it only proves a valid Supabase session exists, and every
// Danlite customer has one of those.
//
// This page reads local JSON files instead of calling an Edge Function, so
// it has no such gate of its own. Left at getAdminSession() alone it would
// render in full for any signed-in customer. So it calls admin-overview
// purely as an authorisation probe and refuses to render anything until that
// call comes back ok — the same allowlist check, performed by the same Edge
// Function, that stands in front of the Overview screen. The response body
// is deliberately unused; only the verdict matters.
// ══════════════════════════════════════════════════════════════════════════

import fs from 'node:fs';
import path from 'node:path';
import type { Metadata } from 'next';
import { callAdminFn, getAdminSession, type Overview } from '@/lib/admin-api';
import { C, MONO } from '@/lib/theme';
import { NOINDEX } from '@/lib/seo';
import { ErrorCard, Shell } from '../shell';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Mission Control — Danlite ELM Admin',
  robots: NOINDEX,
};

// ── Report files ──────────────────────────────────────────────────────────
// They live in admin/reports/ now. Read at request time rather than imported
// so that a missing or malformed file degrades to a muted card instead of
// failing the build — the same behaviour they had in the portal.

const REPORTS_DIR = path.join(process.cwd(), 'reports');

function readReport<T>(file: string): T | null {
  try {
    return JSON.parse(fs.readFileSync(path.join(REPORTS_DIR, file), 'utf8')) as T;
  } catch {
    return null;
  }
}

type Phase = { id: string; name: string; status: string; tag: string; verify: string };
type PhasesFile = { project: string; updated: string; phases: Phase[] };

type Check = { id: number; name: string; result: string };

type Phase1Report = {
  generated: string;
  region: string;
  tables: string[];
  rls_enabled_on: number;
  client_write_paths_to_licences: number;
  client_write_paths_to_payments: number;
  tests: Check[];
};

type Phase2Report = {
  generated: string;
  token_storage_backend: string;
  shared_preferences_for_tokens: boolean;
  pkce_verifier_storage: string;
  otp_routing: string;
  build_note?: string;
  analyze: { new_errors: number; new_warnings: number; pre_existing_issues: number };
  screens: { id: number; name: string; route: string; result: string }[];
  checks: Check[];
};

type Phase3Report = {
  generated: string;
  signature_algorithm: string;
  public_key_base64: string;
  private_key_location: string;
  private_key_sha256_fingerprint: string;
  signing_path_used: string;
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
  checks: Check[];
};

type Phase4Report = {
  generated: string;
  portal_framework: string;
  pages: { route: string; purpose: string; state: string }[];
  noindex_layers: {
    layer_1_robots_txt: string;
    layer_2_meta_tag: string;
    layer_3_http_header: string;
    all_three_verified: boolean;
  };
  gst: { treatment: string; rate_percent: number; WARNING: string };
  razorpay: string;
  session_bridge: { token_ttl_minutes: number };
  app_untouched: { files_changed_under_lib: number; files_changed_under_android: number };
  deviations: string[];
  open_items_for_owner: string[];
  checks: Check[];
};

type Phase5Report = {
  generated: string;
  key_id_prefix_is_rzp_test: boolean;
  what_this_does: string;
  governing_rule: string;
  secrets: {
    installed: string[];
    verified_by: string;
    install_method: string;
    temp_file: string;
    secret_lifetime_minimisation: string;
    repo_sweep: {
      tracked_files_scanned: number;
      on_disk_files_scanned_including_gitignored: number;
      hits_rzp_test: number;
      hits_rzp_live: number;
      hits_webhook_secret: number;
    };
  };
  deployment: { proof: string; fail_closed_confirmed: string };
  the_real_transaction: Record<string, string | number>;
  two_failed_attempts_before_success: Record<string, string>;
  price_integrity_step_5: {
    gst_treatment_current: string;
    gst_rate_percent: number;
    three_readings: Record<string, string | number>;
    all_three_agree: boolean;
    statement: string;
    holds_only_while_inclusive: string;
    why_no_existing_check_would_catch_it: string;
    status: string;
  };
  security_tests: Record<string, Record<string, unknown>>;
  open_items_for_owner: string[];
  test_residue: Record<string, string>;
  deviations: string[];
  checks: Check[];
};

type Phase7Report = {
  generated: string;
  what_this_does: string;
  gating: string;
  atomicity: {
    mechanism: string;
    loser_behaviour: string;
    lock_order: string;
    lock_order_why: string;
    same_device_guard: string;
  };
  the_only_logout_path: { statement: string; cannot_be_reached_by: string[]; reasoning: string };
  how_the_logout_reaches_the_screen: string;
  portal_must_not_claim: { constraint: string; how_it_is_guaranteed: string; verified_live: string };
  backward_compatibility: string;
  canonical_string: string;
  service_role_grants: Record<string, string>;
  escape_hatch: string;
  extra_false_positive_closed: string;
  deviations: string[];
  checks: Check[];
};

type Phase8Report = {
  generated: string;
  what_this_does: string;
  unknown_timeout_seconds: number;
  unknown_timeout_why: string;
  decision_table: { state: string; decision: string; note: string }[];
  every_path_that_can_block: {
    statement: string;
    the_six: string[];
    why_no_ambiguous_condition_reaches_them: string;
    verified_live_that_ambiguity_looks_like_this: string[];
  };
  deliberate_leniency: string;
  residual_risk_stated_honestly: string;
  no_purchase_path: {
    constraint: string;
    how_it_is_enforced: string;
    opinion_asked_for: string;
    strings_en: Record<string, string>;
    audit_of_those_strings: string;
    confirm_needed: string;
  };
  emergency_bypass: {
    env_var: string;
    current_state: string;
    proof_it_is_off: string;
    arming_value: string;
    when_it_is_appropriate: string;
    turn_it_off_immediately: string;
    what_it_does_not_change: string;
    audited: string;
  };
  the_missing_grant_found: Record<string, string>;
  pre_existing_hole_closed: Record<string, string>;
  where_the_gate_lives_at_runtime: Record<string, string>;
  grace_banner: Record<string, string>;
  analyze: {
    new_errors: number;
    new_warnings: number;
    pre_existing_issues: number;
    note: string;
  };
  tests: { passed: number; total: number };
  deviations: string[];
  test_hygiene: string;
  phase_5_untouched: string;
  checks: Check[];
};

type AdminReport = {
  generated: string;
  what_this_does: string;
  the_security_claim: { proof_executed_live: string };
  why_admin_login_differs_from_customer_signup: Record<string, string>;
  rate_limiting: { identifier_per_hour: number; ip_per_hour: number };
  observations_flagged_not_changed: { what: string; why_it_matters: string; why_not_changed: string }[];
  deviations: string[];
  build: { errors: number; routes: number };
  checks: Check[];
};

// ── Small presentational pieces ───────────────────────────────────────────
// Factored out of the original file, which repeated each of these blocks
// verbatim eight or nine times. Same rendered output, one definition.

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section
      style={{
        backgroundColor: C.surface,
        border: `1px solid ${C.border}`,
        borderRadius: 12,
        padding: 20,
        marginBottom: 22,
      }}
    >
      <h2 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 4px' }}>{title}</h2>
      {children}
    </section>
  );
}

function NotRun({ file, what }: { file: string; what: string }) {
  return (
    <p style={{ color: C.muted, fontSize: 12.5, margin: '8px 0 0', lineHeight: 1.5 }}>
      Not yet run. <code>{file}</code> will appear here once {what}.
    </p>
  );
}

function Lede({ children }: { children: React.ReactNode }) {
  return (
    <p style={{ color: C.muted, fontSize: 12.5, margin: '0 0 16px', lineHeight: 1.5 }}>
      {children}
    </p>
  );
}

function Badges({ items }: { items: { label: string; value: string }[] }) {
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginBottom: 14 }}>
      {items.map((b) => (
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
  );
}

/** The ✓/✗ assertion list every phase report ends with. */
function Checks({ items }: { items: Check[] }) {
  return (
    <ul style={{ listStyle: 'none', margin: '16px 0 0', padding: 0 }}>
      {items.map((t) => {
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
              style={{ width: 16, textAlign: 'center', color: ok ? C.green : C.red, fontWeight: 700 }}
            >
              {ok ? '✓' : '✗'}
            </span>
            <span style={{ color: C.muted, fontFamily: MONO, fontSize: 12, minWidth: 18 }}>
              {t.id}
            </span>
            <span style={{ color: ok ? C.text : C.red }}>{t.name}</span>
          </li>
        );
      })}
    </ul>
  );
}

/** `titleColour` defaults to the border colour, which is right for the amber
 *  and red callouts where the border IS the signal. The neutral boxes pass it
 *  explicitly — C.border is nearly black and unreadable as heading text. */
function Callout({
  colour,
  titleColour,
  title,
  children,
}: {
  colour: string;
  titleColour?: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div
      style={{
        border: `1px solid ${colour}`,
        borderRadius: 8,
        padding: '12px 14px',
        marginBottom: 14,
      }}
    >
      <div
        style={{
          color: titleColour ?? colour,
          fontSize: 11,
          fontWeight: 700,
          letterSpacing: 0.8,
          textTransform: 'uppercase',
          marginBottom: 7,
        }}
      >
        {title}
      </div>
      {children}
    </div>
  );
}

function Bullets({ items }: { items: (string | undefined)[] }) {
  return (
    <>
      {items
        .filter((l): l is string => typeof l === 'string' && l.length > 0)
        .map((line, i) => (
          <p key={i} style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 6px' }}>
            • {line}
          </p>
        ))}
    </>
  );
}

function Titled({ title, items }: { title: string; items: string[] }) {
  if (items.length === 0) return null;
  return (
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
        {title}
      </div>
      <Bullets items={items} />
    </div>
  );
}

/** "key: value" narrative rows. */
function KV({ rows }: { rows: [string, string | undefined][] }) {
  return (
    <div style={{ marginBottom: 14 }}>
      {rows.map(([k, v]) => (
        <p key={k} style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 6px' }}>
          <span style={{ color: C.text, fontWeight: 600 }}>{k}: </span>
          {v ?? '—'}
        </p>
      ))}
    </div>
  );
}

function Invariant({ ok, children }: { ok: boolean; children: React.ReactNode }) {
  return (
    <p
      style={{
        margin: '0 0 6px',
        fontSize: 13,
        fontWeight: 600,
        color: ok ? C.green : C.red,
        fontFamily: MONO,
      }}
    >
      {children}
    </p>
  );
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
        backgroundColor: `${s.fg}1F`,
        whiteSpace: 'nowrap',
      }}
    >
      {s.label}
    </span>
  );
}

// ══════════════════════════════════════════════════════════════════════════

export default async function MissionControlPage() {
  const session = await getAdminSession();
  if (!session) return null; // proxy.ts redirects to /login before this renders

  // THE GATE. See the header comment — this page reads files, not an Edge
  // Function, so without this probe a signed-in customer would see all of it.
  const probe = await callAdminFn<Overview>('admin-overview');
  if (!probe.ok) {
    return (
      <Shell email={session.email} active="/mission-control">
        <ErrorCard status={probe.status} message={probe.error} />
      </Shell>
    );
  }

  const data = readReport<PhasesFile>('phases.json');
  const p1 = readReport<Phase1Report>('phase1-report.json');
  const p2 = readReport<Phase2Report>('phase2-report.json');
  const p3 = readReport<Phase3Report>('phase3-report.json');
  const p4 = readReport<Phase4Report>('phase4-report.json');
  const p5 = readReport<Phase5Report>('phase5-report.json');
  const p7 = readReport<Phase7Report>('phase7-report.json');
  const p8 = readReport<Phase8Report>('phase8-report.json');
  const adm = readReport<AdminReport>('phase-admin1-report.json');

  if (!data) {
    return (
      <Shell email={session.email} active="/mission-control">
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
            Expected the file at <code>{path.join(REPORTS_DIR, 'phases.json')}</code>. The build
            progress table cannot be rendered until it is readable and valid JSON.
          </p>
        </div>
      </Shell>
    );
  }

  const phases = Array.isArray(data.phases) ? data.phases : [];
  const total = phases.length;
  const complete = phases.filter((p) => p.status === 'done').length;
  const pct = total > 0 ? Math.round((complete / total) * 100) : 0;

  return (
    <Shell email={session.email} active="/mission-control">
      {/* ---------------- Header ---------------- */}
      <header style={{ marginBottom: 26 }}>
        <h1 style={{ fontSize: 24, fontWeight: 800, margin: 0, letterSpacing: -0.2 }}>
          {data.project}
        </h1>
        <p style={{ color: C.muted, fontSize: 13, margin: '6px 0 0' }}>Updated {data.updated}</p>

        <div style={{ marginTop: 18 }}>
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
              style={{ height: '100%', width: `${pct}%`, backgroundColor: C.green, borderRadius: 999 }}
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
          marginBottom: 22,
        }}
      >
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14, minWidth: 680 }}>
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
                    fontFamily: MONO,
                    whiteSpace: 'nowrap',
                    verticalAlign: 'top',
                  }}
                >
                  {p.id}
                </td>
                <td style={{ padding: '14px 16px', fontWeight: 600, verticalAlign: 'top' }}>
                  {p.name}
                </td>
                <td style={{ padding: '14px 16px', verticalAlign: 'top' }}>{statusPill(p.status)}</td>
                <td
                  style={{
                    padding: '14px 16px',
                    color: C.cyan,
                    fontFamily: MONO,
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

      {/* ---------------- Phase 1 — Database Security ---------------- */}
      <Panel title="Phase 1 — Database Security">
        {!p1 ? (
          <NotRun
            file="phase1-report.json"
            what="the Supabase schema and RLS verification have been executed"
          />
        ) : (
          <>
            <Lede>Row Level Security verified against the live project on {p1.generated}.</Lede>
            <Badges
              items={[
                { label: 'Region', value: p1.region },
                { label: 'Tables', value: `${p1.tables.length}` },
                { label: 'RLS enabled on', value: `${p1.rls_enabled_on} of ${p1.tables.length}` },
              ]}
            />
            {/* The anti-fraud invariant: no client can write money or entitlement */}
            {[
              { label: 'licences', n: p1.client_write_paths_to_licences },
              { label: 'payments', n: p1.client_write_paths_to_payments },
            ].map((w) => (
              <Invariant key={w.label} ok={w.n === 0}>
                Client write paths to {w.label}: {w.n}
              </Invariant>
            ))}
            <Checks items={p1.tests} />
          </>
        )}
      </Panel>

      {/* ---------------- Phase 2 — Authentication ---------------- */}
      <Panel title="Phase 2 — Authentication">
        {!p2 ? (
          <NotRun
            file="phase2-report.json"
            what="the auth screens and secure token storage have been built"
          />
        ) : (
          <>
            <Lede>
              Sign-up, log-in and OTP verification wired to Supabase on {p2.generated}.{' '}
              {p2.otp_routing}.
            </Lede>
            <Badges
              items={[
                { label: 'Screens', value: `${p2.screens.length}` },
                { label: 'Token store', value: p2.token_storage_backend },
                { label: 'New analyze errors', value: `${p2.analyze.new_errors}` },
              ]}
            />
            <Invariant ok={!p2.shared_preferences_for_tokens}>
              Tokens in shared_preferences: {String(p2.shared_preferences_for_tokens)}
            </Invariant>
            <Invariant ok>PKCE verifier store: {p2.pkce_verifier_storage}</Invariant>

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
                  <span style={{ color: C.cyan, fontFamily: MONO, fontSize: 12, minWidth: 62 }}>
                    {s.route}
                  </span>
                  <span style={{ color: C.text }}>{s.name}</span>
                </li>
              ))}
            </ul>

            <Checks items={p2.checks} />
          </>
        )}
      </Panel>

      {/* ---------------- Phase 3 — Entitlement Token ---------------- */}
      <Panel title="Phase 3 — Entitlement Token">
        {!p3 ? (
          <NotRun
            file="phase3-report.json"
            what="the signed entitlement token and its offline grace window have been built"
          />
        ) : (
          <>
            <Lede>
              Signed licence statements issued and verified on {p3.generated}. {p3.gating}
            </Lede>
            <Badges
              items={[
                { label: 'Algorithm', value: p3.signature_algorithm },
                { label: 'Offline grace', value: `${Math.round(p3.token_ttl_seconds / 86400)} days` },
                { label: 'Signing path', value: p3.signing_path_used },
                { label: 'New analyze errors', value: `${p3.analyze.new_errors}` },
              ]}
            />

            {/* The public key is safe to show — that is its whole purpose. The
                private key is represented ONLY by its fingerprint. */}
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
                      fontFamily: MONO,
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

            <Invariant ok={p3.row_counts.parity}>
              profiles {p3.row_counts.profiles} = licences {p3.row_counts.licences}
              {'  ·  '}users missing a licence: {p3.row_counts.users_missing_licence}
            </Invariant>
            <Invariant ok>Canonical signing string: {p3.canonical_signing_string}</Invariant>

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
                <p style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: 0 }}>{b.body}</p>
              </div>
            ))}

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

            <Checks items={p3.checks} />
          </>
        )}
      </Panel>

      {/* ---------------- Phase 4 — Billing Portal ---------------- */}
      <Panel title="Phase 4 — Billing Portal">
        {!p4 ? (
          <NotRun
            file="phase4-report.json"
            what="the billing portal and activation links have been built"
          />
        ) : (
          <>
            <Lede>
              Activation links, session bridging and the four portal pages verified on {p4.generated}.{' '}
              {p4.portal_framework}.
            </Lede>
            <Badges
              items={[
                { label: 'Pages', value: `${p4.pages.length}` },
                { label: 'Link TTL', value: `${p4.session_bridge.token_ttl_minutes} min` },
                {
                  label: 'noindex layers',
                  value: p4.noindex_layers.all_three_verified ? '3 of 3' : 'INCOMPLETE',
                },
                { label: 'GST', value: `${p4.gst.treatment} ${p4.gst.rate_percent}%` },
              ]}
            />

            <Invariant ok={p4.app_untouched.files_changed_under_lib === 0}>
              Flutter files changed under lib/: {p4.app_untouched.files_changed_under_lib}
              {'  ·  '}android/: {p4.app_untouched.files_changed_under_android}
            </Invariant>

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
                  <span style={{ color: C.cyan, fontFamily: MONO, fontSize: 12, minWidth: 118 }}>
                    {pg.route}
                  </span>
                  <span style={{ color: C.text }}>{pg.purpose}</span>
                </li>
              ))}
            </ul>

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
                <p key={i} style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 5px' }}>
                  <span style={{ color: C.green, fontWeight: 700 }}>✓</span> {l}
                </p>
              ))}
            </div>

            {[
              { title: 'Razorpay', body: p4.razorpay },
              { title: 'GST — unconfirmed', body: p4.gst.WARNING },
            ].map((b) => (
              <p
                key={b.title}
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
                <strong>{b.title}:</strong> {b.body}
              </p>
            ))}

            <Titled title="Needs a decision from you" items={p4.open_items_for_owner} />
            <Titled title="Deviations from the written plan" items={p4.deviations} />
            <Checks items={p4.checks} />
          </>
        )}
      </Panel>

      {/* ---------------- Phase 5 — Razorpay ---------------- */}
      <Panel title="Phase 5 — Razorpay (Test Mode)">
        {!p5 ? (
          <NotRun
            file="phase5-report.json"
            what="the Razorpay rail has been verified against a real transaction"
          />
        ) : (
          (() => {
            const isTest = p5.key_id_prefix_is_rzp_test;
            const tx = p5.the_real_transaction;
            const pi = p5.price_integrity_step_5;
            return (
              <>
                <Lede>
                  {p5.what_this_does} Verified on {p5.generated}.
                </Lede>

                {/* The single most important thing on this panel: are we taking
                    real money? Renders a boolean only — never the key. */}
                <div
                  style={{
                    border: `2px solid ${isTest ? C.amber : C.red}`,
                    borderRadius: 8,
                    padding: '14px 16px',
                    marginBottom: 16,
                    backgroundColor: `${isTest ? C.amber : C.red}14`,
                  }}
                >
                  <div
                    style={{
                      color: isTest ? C.amber : C.red,
                      fontSize: 15,
                      fontWeight: 800,
                      letterSpacing: 0.4,
                      marginBottom: 6,
                    }}
                  >
                    {isTest
                      ? 'TEST MODE — not accepting real payments'
                      : 'LIVE MODE — REAL PAYMENTS ARE BEING ACCEPTED'}
                  </div>
                  <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: 0 }}>
                    Derived from whether RAZORPAY_KEY_ID begins with{' '}
                    <code style={{ color: C.text }}>rzp_test_</code>, verified at install time and
                    recorded in phase5-report.json. Only this boolean is rendered; the key itself
                    lives in the Supabase Edge Function secret store and never reaches this page.
                  </p>
                </div>

                <Badges
                  items={[
                    { label: 'Price', value: `${String(tx.amount_minor)} ${String(tx.currency)}` },
                    { label: 'GST', value: `${pi.gst_treatment_current} ${pi.gst_rate_percent}%` },
                    { label: 'Prices agree', value: pi.all_three_agree ? '3 of 3' : 'DIVERGENT' },
                    {
                      label: 'Checks',
                      value: `${p5.checks.filter((c) => c.result === 'pass').length} of ${p5.checks.length}`,
                    },
                  ]}
                />

                <Callout colour={C.red} title="Governing rule — the only way a licence turns on">
                  <p style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: 0 }}>
                    {p5.governing_rule}
                  </p>
                </Callout>

                <div
                  style={{
                    border: `1px solid ${C.border}`,
                    backgroundColor: C.card,
                    borderRadius: 8,
                    padding: '12px 14px',
                    marginBottom: 14,
                  }}
                >
                  <div
                    style={{
                      color: C.cyan,
                      fontSize: 11,
                      fontWeight: 700,
                      letterSpacing: 0.8,
                      textTransform: 'uppercase',
                      marginBottom: 8,
                    }}
                  >
                    The real test-mode transaction
                  </div>
                  {[
                    ['Payment', String(tx.gateway_payment_id)],
                    ['Order', String(tx.gateway_order_id)],
                    ['Amount', `${String(tx.amount_minor)} minor (${String(tx.currency)})`],
                    ['Status', String(tx.status)],
                    ['GST invoice', String(tx.gst_invoice_no)],
                    ['Method', String(tx.method)],
                    ['Webhook delivery', String(tx.webhook_events_row)],
                  ].map(([k, v]) => (
                    <div key={k} style={{ marginBottom: 6 }}>
                      <span style={{ color: C.muted, fontSize: 11 }}>{k}</span>
                      <div
                        style={{
                          color: C.text,
                          fontFamily: MONO,
                          fontSize: 12,
                          wordBreak: 'break-all',
                          lineHeight: 1.5,
                        }}
                      >
                        {v}
                      </div>
                    </div>
                  ))}
                </div>

                <Callout
                  colour={pi.all_three_agree ? C.green : C.red}
                  title="Price integrity — three independent readings"
                >
                  {Object.entries(pi.three_readings).map(([k, v]) => (
                    <p key={k} style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 5px' }}>
                      <span style={{ color: pi.all_three_agree ? C.green : C.red, fontWeight: 700 }}>
                        {pi.all_three_agree ? '✓' : '✗'}
                      </span>{' '}
                      {String(v)}
                    </p>
                  ))}
                  {[
                    pi.statement,
                    pi.holds_only_while_inclusive,
                    pi.why_no_existing_check_would_catch_it,
                    pi.status,
                  ].map((line, i) => (
                    <p key={i} style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '8px 0 0' }}>
                      {line}
                    </p>
                  ))}
                </Callout>

                <KV
                  rows={[
                    ['Secrets installed', p5.secrets.installed.join(', ')],
                    ['Verified by', p5.secrets.verified_by],
                    ['Install method', p5.secrets.install_method],
                    ['Temp file', p5.secrets.temp_file],
                    ['Secret lifetime', p5.secrets.secret_lifetime_minimisation],
                    [
                      'Repo sweep',
                      `${p5.secrets.repo_sweep.tracked_files_scanned} tracked and ${p5.secrets.repo_sweep.on_disk_files_scanned_including_gitignored} on-disk files scanned — ${p5.secrets.repo_sweep.hits_rzp_test} rzp_test_ hits, ${p5.secrets.repo_sweep.hits_rzp_live} rzp_live_ hits, ${p5.secrets.repo_sweep.hits_webhook_secret} webhook-secret hits`,
                    ],
                    ['Deploy integrity', p5.deployment.proof],
                    ['Fail-closed proof', p5.deployment.fail_closed_confirmed],
                  ]}
                />

                <Callout colour={C.amber} title="Security tests — executed against a real gateway">
                  {Object.entries(p5.security_tests).map(([key, body]) => {
                    const rec = body as Record<string, unknown>;
                    const ok = rec.result === 'pass';
                    const lines: [string, string][] = [];
                    const walk = (o: Record<string, unknown>, prefix: string) => {
                      for (const [k, v] of Object.entries(o)) {
                        if (k === 'result') continue;
                        if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
                          lines.push([prefix + k, String(v)]);
                        } else if (v && typeof v === 'object') {
                          walk(v as Record<string, unknown>, `${prefix}${k}.`);
                        }
                      }
                    };
                    walk(rec, '');
                    return (
                      <div key={key} style={{ marginBottom: 12 }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                          <span style={{ color: ok ? C.green : C.red, fontWeight: 700 }}>
                            {ok ? '✓' : '✗'}
                          </span>
                          <span
                            style={{ color: C.text, fontWeight: 700, fontSize: 12.5, fontFamily: MONO }}
                          >
                            {key}
                          </span>
                        </div>
                        {lines.map(([k, v]) => (
                          <p
                            key={k}
                            style={{
                              color: C.muted,
                              fontSize: 12,
                              lineHeight: 1.6,
                              margin: '0 0 3px',
                              paddingLeft: 20,
                            }}
                          >
                            <span style={{ color: C.cyan, fontFamily: MONO, fontSize: 11 }}>{k}</span>{' '}
                            {v}
                          </p>
                        ))}
                      </div>
                    );
                  })}
                </Callout>

                <KV rows={Object.entries(p5.two_failed_attempts_before_success)} />
                <Titled title="Needs a decision from you" items={p5.open_items_for_owner} />
                <Titled
                  title="Test residue left in the database"
                  items={Object.entries(p5.test_residue).map(([k, v]) => `${k}: ${v}`)}
                />
                <Titled title="Deviations from the written plan" items={p5.deviations} />
                <Checks items={p5.checks} />
              </>
            );
          })()
        )}
      </Panel>

      {/* ---------------- Phase 7 — Single Active Session ---------------- */}
      <Panel title="Phase 7 — Single Active Session">
        {!p7 ? (
          <NotRun
            file="phase7-report.json"
            what="single-session enforcement has been built"
          />
        ) : (
          <>
            <Lede>
              {p7.what_this_does} Verified on {p7.generated}.
            </Lede>

            <Callout
              colour={C.border}
              titleColour={C.cyan}
              title="Atomicity — two logins at the same instant"
            >
              <Bullets
                items={[
                  p7.atomicity.mechanism,
                  p7.atomicity.loser_behaviour,
                  `Lock order: ${p7.atomicity.lock_order}. ${p7.atomicity.lock_order_why}`,
                  p7.atomicity.same_device_guard,
                ]}
              />
            </Callout>

            <Callout colour={C.amber} title="The only path that can force a logout">
              <p style={{ color: C.text, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 8px' }}>
                {p7.the_only_logout_path.statement}
              </p>
              <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: '0 0 6px' }}>
                It cannot be reached by:
              </p>
              <Bullets items={p7.the_only_logout_path.cannot_be_reached_by} />
              <p style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '8px 0 0' }}>
                {p7.the_only_logout_path.reasoning}
              </p>
            </Callout>

            <Callout colour={C.red} title="Hard constraint — the portal must never claim a session">
              <Bullets
                items={[
                  p7.portal_must_not_claim.constraint,
                  p7.portal_must_not_claim.how_it_is_guaranteed,
                  p7.portal_must_not_claim.verified_live,
                ]}
              />
            </Callout>

            <KV
              rows={[
                ['Backward compatibility', p7.backward_compatibility],
                ['Canonical signing string', p7.canonical_string],
                ['Forced logout reaches the screen', p7.how_the_logout_reaches_the_screen],
                ['service_role grants', p7.service_role_grants.why_select_only],
                ['Escape hatch', p7.escape_hatch],
                ['False positive found and closed', p7.extra_false_positive_closed],
                ['Gating', p7.gating],
              ]}
            />

            <Titled title="Deviations from the written plan" items={p7.deviations} />
            <Checks items={p7.checks} />
          </>
        )}
      </Panel>

      {/* ---------------- Phase 8 — Paywall Gate ---------------- */}
      <Panel title="Phase 8 — Paywall Gate">
        {!p8 ? (
          <NotRun file="phase8-report.json" what="the paywall gate has been built" />
        ) : (
          <>
            <Lede>
              {p8.what_this_does} Verified on {p8.generated}.
            </Lede>

            {/* Bypass status — the single most important thing on this panel */}
            <div
              style={{
                border: `1px solid ${p8.emergency_bypass.current_state === 'OFF' ? C.green : C.red}`,
                borderRadius: 8,
                padding: '12px 14px',
                marginBottom: 14,
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6 }}>
                <span
                  style={{
                    color: C.muted,
                    fontSize: 11,
                    fontWeight: 700,
                    letterSpacing: 0.8,
                    textTransform: 'uppercase',
                  }}
                >
                  Emergency bypass ({p8.emergency_bypass.env_var})
                </span>
                {statusPill(p8.emergency_bypass.current_state === 'OFF' ? 'done' : 'in_progress')}
                <span
                  style={{
                    color: p8.emergency_bypass.current_state === 'OFF' ? C.green : C.red,
                    fontWeight: 700,
                    fontSize: 13,
                  }}
                >
                  {p8.emergency_bypass.current_state}
                </span>
              </div>
              <Bullets
                items={[
                  p8.emergency_bypass.proof_it_is_off,
                  p8.emergency_bypass.arming_value,
                  p8.emergency_bypass.when_it_is_appropriate,
                  p8.emergency_bypass.turn_it_off_immediately,
                  p8.emergency_bypass.audited,
                  p8.emergency_bypass.what_it_does_not_change,
                ]}
              />
            </div>

            <Callout
              colour={C.border}
              titleColour={C.cyan}
              title={`The decision table — unknown timeout ${p8.unknown_timeout_seconds}s`}
            >
              <div style={{ overflowX: 'auto' }}>
                <table style={{ borderCollapse: 'collapse', width: '100%', minWidth: 560 }}>
                  <tbody>
                    {p8.decision_table.map((row) => {
                      const blocks = row.decision.startsWith('BLOCK');
                      return (
                        <tr key={row.state}>
                          <td
                            style={{
                              borderTop: `1px solid ${C.border}`,
                              padding: '8px 10px 8px 0',
                              color: C.text,
                              fontSize: 12.5,
                              verticalAlign: 'top',
                            }}
                          >
                            {row.state}
                          </td>
                          <td
                            style={{
                              borderTop: `1px solid ${C.border}`,
                              padding: '8px 10px',
                              color: blocks ? C.amber : C.green,
                              fontSize: 12.5,
                              fontWeight: 700,
                              whiteSpace: 'nowrap',
                              verticalAlign: 'top',
                            }}
                          >
                            {row.decision}
                          </td>
                          <td
                            style={{
                              borderTop: `1px solid ${C.border}`,
                              padding: '8px 0 8px 10px',
                              color: C.muted,
                              fontSize: 12,
                              lineHeight: 1.5,
                              verticalAlign: 'top',
                            }}
                          >
                            {row.note}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              <p style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '10px 0 0' }}>
                {p8.unknown_timeout_why}
              </p>
            </Callout>

            <Callout colour={C.amber} title="Every path that can block a user">
              <p style={{ color: C.text, fontSize: 12.5, lineHeight: 1.6, margin: '0 0 8px' }}>
                {p8.every_path_that_can_block.statement}
              </p>
              {p8.every_path_that_can_block.the_six.map((d, i) => (
                <p
                  key={i}
                  style={{ color: C.muted, fontFamily: MONO, fontSize: 11.5, lineHeight: 1.7, margin: 0 }}
                >
                  {d}
                </p>
              ))}
              <p style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '10px 0 6px' }}>
                {p8.every_path_that_can_block.why_no_ambiguous_condition_reaches_them}
              </p>
              <Bullets items={p8.every_path_that_can_block.verified_live_that_ambiguity_looks_like_this} />
              <p style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '10px 0 0' }}>
                <span style={{ color: C.text, fontWeight: 600 }}>Residual risk: </span>
                {p8.residual_risk_stated_honestly}
              </p>
            </Callout>

            <Callout colour={C.red} title="Hard constraint — no purchase path in the app">
              <Bullets
                items={[
                  p8.no_purchase_path.constraint,
                  p8.no_purchase_path.how_it_is_enforced,
                  p8.no_purchase_path.audit_of_those_strings,
                  p8.no_purchase_path.opinion_asked_for,
                  p8.no_purchase_path.confirm_needed,
                ]}
              />
              <div
                style={{
                  marginTop: 8,
                  border: `1px solid ${C.border}`,
                  borderRadius: 6,
                  padding: '10px 12px',
                }}
              >
                {Object.entries(p8.no_purchase_path.strings_en).map(([k, v]) => (
                  <p key={k} style={{ margin: '0 0 5px', fontSize: 12, lineHeight: 1.55, color: C.muted }}>
                    <span style={{ color: C.cyan, fontFamily: MONO, fontSize: 11.5 }}>{k}</span>
                    {'  '}
                    <span style={{ color: C.text }}>&ldquo;{v}&rdquo;</span>
                  </p>
                ))}
              </div>
            </Callout>

            <KV
              rows={[
                ['Deliberate leniency', p8.deliberate_leniency],
                ['Where the gate lives at runtime', p8.where_the_gate_lives_at_runtime.mechanism],
                ['OBD disconnect on withdrawal', p8.where_the_gate_lives_at_runtime.obd_disconnect],
                ['Offline-grace banner placement', p8.grace_banner.placement],
                ['Missing grant found and fixed', p8.the_missing_grant_found.fix],
                ['Phase 5 side effect, stated', p8.the_missing_grant_found.phase_5_side_effect_stated],
                ['Pre-existing hole closed', p8.pre_existing_hole_closed.fix],
                ['Phase 5 untouched', p8.phase_5_untouched],
                ['Test hygiene', p8.test_hygiene],
              ]}
            />

            <Titled title="Deviations from the written plan" items={p8.deviations} />

            <p style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.6, margin: '16px 0 0' }}>
              <span style={{ color: C.text, fontWeight: 600 }}>Regression: </span>
              flutter analyze — {p8.analyze.new_errors} new errors, {p8.analyze.new_warnings} new
              warnings, {p8.analyze.pre_existing_issues} pre-existing. flutter test —{' '}
              {p8.tests.passed}/{p8.tests.total} pass. {p8.analyze.note}
            </p>

            <Checks items={p8.checks} />
          </>
        )}
      </Panel>

      {/* ---------------- Admin Portal — Phase 1 + Phase 2 ---------------- */}
      <Panel title="Admin Portal — Phase 1 (Read-Only) + Phase 2 (Actions)">
        {!adm ? (
          <NotRun file="phase-admin1-report.json" what="the internal admin tool has been built" />
        ) : (
          <>
            <Lede>
              {adm.what_this_does} Verified on {adm.generated}.
            </Lede>

            {/* The security claim is the headline here, the way TEST/LIVE mode is
                the headline on the Phase 5 panel. This tool sees every customer's
                data, so the only thing worth leading with is how that is gated. */}
            <div
              style={{
                border: `2px solid ${C.green}`,
                borderRadius: 8,
                padding: '14px 16px',
                marginBottom: 16,
                backgroundColor: `${C.green}12`,
              }}
            >
              <div
                style={{
                  color: C.green,
                  fontSize: 13.5,
                  fontWeight: 800,
                  letterSpacing: 0.3,
                  marginBottom: 7,
                }}
              >
                ALLOWLIST RE-CHECKED ON EVERY REQUEST — PROVEN LIVE
              </div>
              <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: 0 }}>
                {adm.the_security_claim.proof_executed_live}
              </p>
            </div>

            <Badges
              items={[
                { label: 'Read-only', value: 'no action buttons' },
                {
                  label: 'Rate limit',
                  value: `${adm.rate_limiting.identifier_per_hour}/addr · ${adm.rate_limiting.ip_per_hour}/IP per hr`,
                },
                { label: 'Build', value: `${adm.build.errors} errors · ${adm.build.routes} routes` },
                {
                  label: 'Checks',
                  value: `${adm.checks.filter((c) => c.result === 'pass').length} of ${adm.checks.length}`,
                },
              ]}
            />

            <Callout
              colour={C.border}
              titleColour={C.muted}
              title="Admin login is deliberately NOT enumeration-safe"
            >
              <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: 0 }}>
                {adm.why_admin_login_differs_from_customer_signup.why_that_is_correct_here}{' '}
                <span style={{ color: C.amber }}>
                  {adm.why_admin_login_differs_from_customer_signup.do_not_copy_back}
                </span>
              </p>
            </Callout>

            {adm.observations_flagged_not_changed.length > 0 && (
              <div
                style={{
                  border: `1px solid ${C.amber}55`,
                  backgroundColor: `${C.amber}0E`,
                  borderRadius: 8,
                  padding: '12px 14px',
                  marginBottom: 14,
                }}
              >
                <div
                  style={{
                    color: C.amber,
                    fontSize: 11,
                    fontWeight: 700,
                    letterSpacing: 0.8,
                    textTransform: 'uppercase',
                    marginBottom: 8,
                  }}
                >
                  Flagged for you — found, not changed
                </div>
                {adm.observations_flagged_not_changed.map((o) => (
                  <p key={o.what} style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: '0 0 8px' }}>
                    <span style={{ color: C.text }}>{o.what}</span> {o.why_it_matters}{' '}
                    <span style={{ color: C.muted }}>({o.why_not_changed})</span>
                  </p>
                ))}
              </div>
            )}

            <Checks items={adm.checks} />

            {adm.deviations.length > 0 && (
              <p
                style={{
                  color: C.muted,
                  fontSize: 11.5,
                  lineHeight: 1.6,
                  margin: '12px 0 0',
                  borderTop: `1px solid ${C.border}`,
                  paddingTop: 12,
                }}
              >
                <span style={{ color: C.text, fontWeight: 700 }}>{adm.deviations.length} deviations</span>{' '}
                recorded in <code>phase-admin1-report.json</code>, including three migrations
                (allowlist, audit_log SELECT grant, audit_log TRUNCATE revoke) and the robots.txt fix.
              </p>
            )}
          </>
        )}

        {/* ---- Phase 2 (Actions) ----------------------------------------
            Kept inside the same panel rather than given its own, because it
            is the same tool: the Phase 1 read surface with three writes added.
            Phase 1's headline was how access is gated; Phase 2's headline is
            that nothing can be done without a name and a reason attached, so
            that is what leads here. Hardcoded rather than read from a report
            file — this phase added no phase-admin2-report.json. */}
        <div style={{ borderTop: `1px solid ${C.border}`, marginTop: 18, paddingTop: 16 }}>
          <div
            style={{
              border: `2px solid ${C.green}`,
              borderRadius: 8,
              padding: '14px 16px',
              marginBottom: 14,
              backgroundColor: `${C.green}12`,
            }}
          >
            <div
              style={{
                color: C.green,
                fontSize: 13.5,
                fontWeight: 800,
                letterSpacing: 0.3,
                marginBottom: 7,
              }}
            >
              NO ACTION WITHOUT A NAMED ACTOR AND A REASON — ENFORCED IN THE DATABASE
            </div>
            <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: 0 }}>
              <code>admin_grant_licence</code> and <code>admin_revoke_licence</code> raise on a null,
              empty or whitespace-only reason, and refuse a call with no identified actor. Proven live
              by calling both directly with an empty reason and confirming nothing changed — not
              argued from the disabled button in the browser, which is courtesy only. The acting admin
              is taken from the verified JWT and never from the request body; a grant sent with a
              forged <code>actor_email</code> was recorded against the real caller.
            </p>
          </div>

          <Badges
            items={[
              { label: 'Actions', value: 'grant · revoke · force sign-out' },
              { label: 'Audit', value: 'actor_user_id + actor_email' },
              { label: 'Grant rail', value: 'admin_grant, never razorpay' },
              { label: 'Escalation test', value: '403 for a real customer JWT' },
            ]}
          />

          <Callout
            colour={C.border}
            titleColour={C.muted}
            title="An admin grant is not recorded as a payment"
          >
            <p style={{ color: C.muted, fontSize: 12, lineHeight: 1.6, margin: 0 }}>
              <code>licences.purchase_rail</code> was widened from{' '}
              <code>razorpay_in | razorpay_intl</code> to also allow <code>admin_grant</code>. Stamping
              a gifted licence as a Razorpay sale would fabricate payment provenance that never
              happened and would corrupt revenue reconciliation.{' '}
              <span style={{ color: C.amber }}>
                Revocations are likewise distinguishable: an admin writes &ldquo;admin_revoke: …&rdquo;
                into revoke_reason, where the refund webhook writes &ldquo;refund.created
                refund_id=… &rdquo;.
              </span>
            </p>
          </Callout>

          <ul
            style={{ listStyle: 'none', padding: 0, margin: 0, display: 'grid', gap: 7, fontSize: 12.5 }}
          >
            {[
              'audit_log gains actor_user_id (FK, ON DELETE SET NULL) + actor_email (flat copy, survives allowlist removal)',
              'admin-grant-licence, admin-revoke-licence, admin-force-signout deployed; all re-check the allowlist per call',
              'Force sign-out reuses Phase 7 sign_out_all_devices unchanged — no new session logic written',
              'Grant/Revoke shown contextually, never both; each behind a modal needing a typed reason',
              'admin-audit-log widened to return the two new actor columns (its select list was hardcoded)',
            ].map((line) => (
              <li key={line} style={{ display: 'flex', gap: 9, alignItems: 'flex-start' }}>
                <span style={{ color: C.green, fontWeight: 700 }}>✓</span>
                <span style={{ color: C.text }}>{line}</span>
              </li>
            ))}
          </ul>

          <p
            style={{
              color: C.muted,
              fontSize: 11.5,
              lineHeight: 1.6,
              margin: '12px 0 0',
              borderTop: `1px solid ${C.border}`,
              paddingTop: 12,
            }}
          >
            <span style={{ color: C.text, fontWeight: 700 }}>Carried forward:</span> the /audit-log page
            still renders Phase 1&apos;s columns, so the new actor is in the API response but not yet on
            that screen — that file was out of scope this phase. Force sign-out&apos;s reason is enforced
            at the Edge Function, not the database, because its RPC is Phase 7&apos;s and was
            deliberately not modified.
          </p>
        </div>
      </Panel>

      {/* ---------------- Footer ---------------- */}
      <footer
        style={{
          border: `1px solid ${C.border}`,
          borderRadius: 12,
          padding: '14px 18px',
          color: C.muted,
          fontSize: 12.5,
          lineHeight: 1.6,
        }}
      >
        <span style={{ color: C.text, fontWeight: 700 }}>Internal build record.</span> Read from
        JSON files in <code>admin/reports/</code> at request time. This page was the billing
        portal&apos;s <code>/</code> route until it was moved here — on the portal it was reachable
        by anyone, and it describes the system in enough detail to be worth reading twice by
        somebody attacking it.
      </footer>
    </Shell>
  );
}
