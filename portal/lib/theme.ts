// ══════════════════════════════════════════════════════════════════════════
// The Mission Control palette, shared by the customer-facing portal pages.
//
// Lifted verbatim from portal/app/page.tsx so the billing pages are visibly
// the same product. Extracted to one module rather than copied into each of
// the seven pages: a hex code duplicated seven times is a hex code that will
// eventually differ in one of them.
//
// DESIGN INTENT: these pages should read like a bank's checkout, not a landing
// page. Dark, plain, dense, no marketing navigation, no imagery, nothing to
// click that isn't the task at hand. A customer who arrives here has already
// decided to buy; the only job is to not lose them.
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

/** Full-page dark shell, centred, narrow. Narrow is deliberate: a checkout. */
export const pageStyle: React.CSSProperties = {
  minHeight: '100vh',
  width: '100%',
  backgroundColor: C.bg,
  color: C.text,
  fontFamily: FONT,
  padding: '48px 20px 64px',
  boxSizing: 'border-box',
};

export const cardStyle: React.CSSProperties = {
  backgroundColor: C.surface,
  border: `1px solid ${C.border}`,
  borderRadius: 12,
  padding: 24,
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

/** Small footer with the legal links. The only navigation these pages carry. */
export const legalLinkStyle: React.CSSProperties = {
  color: C.muted,
  fontSize: 12,
  textDecoration: 'none',
};
