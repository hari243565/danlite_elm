// ══════════════════════════════════════════════════════════════════════════
// The Mission Control palette — the same one used by the Flutter app, the
// billing portal and the phase dashboard. Copied here rather than imported
// across apps, for the same build-independence reason as lib/supabase/server.ts.
//
// DESIGN INTENT: this is an internal tool that two or three people will ever
// open. It needs no visual language of its own, no marketing surface and no
// onboarding. It should look like the rest of the product and then get out of
// the way. Dense tables, monospace for anything an operator might need to
// copy (ids, invoice numbers, payment references), and colour used only where
// it carries meaning — status, and test-vs-live.
// ══════════════════════════════════════════════════════════════════════════

export const C = {
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

export const FONT =
  'ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif';

export const MONO = 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace';

/** Full-page dark shell. Wide, unlike the billing portal's deliberately
 *  narrow checkout: this tool's job is showing tables, not focusing a
 *  purchase. */
export const pageStyle: React.CSSProperties = {
  minHeight: '100vh',
  width: '100%',
  backgroundColor: C.bg,
  color: C.text,
  fontFamily: FONT,
};

export const cardStyle: React.CSSProperties = {
  backgroundColor: C.surface,
  border: `1px solid ${C.border}`,
  borderRadius: 12,
  padding: 20,
};

export const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '12px 14px',
  borderRadius: 8,
  border: `1px solid ${C.border}`,
  backgroundColor: C.card,
  color: C.text,
  fontSize: 15,
  fontFamily: FONT,
  boxSizing: 'border-box',
};

export const buttonStyle: React.CSSProperties = {
  display: 'inline-block',
  width: '100%',
  padding: '13px 20px',
  borderRadius: 8,
  border: 'none',
  backgroundColor: C.cyan,
  color: C.bg,
  fontSize: 15,
  fontWeight: 700,
  fontFamily: FONT,
  cursor: 'pointer',
};

/** Colour for a licence or payment status. Anything unrecognised renders
 *  muted rather than green — an unknown status is not a good status. */
export function statusColor(status: string | null | undefined): string {
  switch (status) {
    case 'active':
    case 'captured':
      return C.green;
    case 'created':
    case 'authorized':
    case 'partially_refunded':
      return C.amber;
    case 'revoked':
    case 'refunded':
    case 'failed':
      return C.red;
    default:
      return C.muted;
  }
}

/** Minor units -> a display string. Money is formatted, never arithmetic'd,
 *  as a float: the division happens once, here, at the very end. */
export function money(minor: number | null | undefined, currency = 'INR'): string {
  const n = Number(minor) || 0;
  const symbol = currency === 'INR' ? '₹' : `${currency} `;
  return `${symbol}${(n / 100).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

/** Timestamps are rendered in IST, because the person reading this screen is
 *  in India and reconciling against Razorpay's dashboard, which also shows
 *  IST. A UTC string here would mean doing timezone arithmetic by hand
 *  during an incident. */
export function when(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('en-IN', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}
