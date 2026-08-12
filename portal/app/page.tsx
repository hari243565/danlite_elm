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
