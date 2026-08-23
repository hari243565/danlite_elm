'use client';

// ══════════════════════════════════════════════════════════════════════════
// ConfirmAction — the one component every destructive admin control goes
// through. Phase 1 had nothing like it, because Phase 1 had no destructive
// controls; this is the first.
//
// ── WHAT IT IS ACTUALLY FOR ──────────────────────────────────────────────
// Not "are you sure?". That question is worthless — it is answered "yes"
// reflexively, and a dialog that only needs a click is barely slower than the
// button behind it. This component asks for something a reflex cannot supply:
// a typed sentence explaining WHY. Confirm stays disabled until it exists.
//
// That single design choice does two jobs at once:
//   • It makes an accidental action essentially impossible. A misclick opens
//     a dialog; it cannot complete one.
//   • It produces the audit trail. The reason typed here is the reason stored
//     in audit_log and, for a revocation, in licences.revoke_reason. There is
//     no path in this UI that reaches a licence change without producing one.
//
// ── WHAT THIS COMPONENT IS *NOT* ─────────────────────────────────────────
// It is not a security control, and nothing here should ever be mistaken for
// one. The disabled button, the minimum length, the whitespace trim — all of
// it is courtesy to the person using the tool, and all of it evaporates the
// moment somebody calls the endpoint directly. The real enforcement is in
// admin_grant_licence() and admin_revoke_licence(), which RAISE on an empty
// reason, and in requireAdmin(), which re-checks the allowlist on every call.
// This is the friendly outer layer of a rule enforced three layers down.
//
// ── WHY A MODAL RATHER THAN THE PORTAL'S INLINE TWO-STEP ─────────────────
// The billing portal confirms "sign out all devices" with an inline panel and
// a ?devices=confirm link. That pattern is right there: one destructive
// action, on the user's own account, on a page with nothing else on it. This
// page is a dense operator screen covered in other people's data, and the
// action needs a free-text field. Dimming everything else and taking focus is
// the appropriate weight for "take away the licence of the customer whose
// record happens to be on screen". The button language — red outline for
// destructive, muted Cancel — is carried over from that portal pattern
// deliberately, so the two still look like the same product.
// ══════════════════════════════════════════════════════════════════════════

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { C, FONT } from '@/lib/theme';

/** Short enough not to be a hurdle, long enough that "x" or "." will not do.
 *  The database only insists the reason is non-empty; this asks for slightly
 *  more, because a one-character reason is technically a reason and
 *  practically useless to whoever reads the audit log later. */
const MIN_REASON = 6;
const MAX_REASON = 500;

export type ActionResult = { ok: true } | { ok: false; error: string };

export function ConfirmAction({
  label,
  title,
  consequence,
  tone,
  confirmLabel,
  reasonHint,
  action,
}: {
  /** Text on the button that opens the dialog. */
  label: string;
  /** Dialog heading. */
  title: string;
  /** Plain language, naming the actual person and the actual effect — e.g.
   *  "This will grant hs0238766@gmail.com a lifetime licence." A vague
   *  confirmation is how the wrong customer's licence gets revoked from a
   *  screen the operator thought was showing somebody else. */
  consequence: React.ReactNode;
  tone: 'danger' | 'primary';
  confirmLabel: string;
  reasonHint: string;
  /** Server Action. It re-authenticates and re-authorises server-side; this
   *  component's job is only to collect the reason and report the outcome. */
  action: (reason: string) => Promise<ActionResult>;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const accent = tone === 'danger' ? C.red : C.cyan;
  const trimmed = reason.trim();
  const canConfirm = trimmed.length >= MIN_REASON && trimmed.length <= MAX_REASON && !busy;

  useEffect(() => {
    if (open) textareaRef.current?.focus();
  }, [open]);

  // Escape closes — but never mid-flight, when closing would leave the
  // operator unsure whether the action went through.
  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape' && !busy) close();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, busy]);

  function close() {
    setOpen(false);
    setReason('');
    setError(null);
  }

  async function confirm() {
    if (!canConfirm) return;
    setBusy(true);
    setError(null);
    try {
      const result = await action(trimmed);
      if (result.ok) {
        close();
        // The page is a Server Component reading through an uncached fetch,
        // so re-running it is all that is needed for the new licence state,
        // the new session list and the audit trail to appear. The operator
        // must never have to press F5 to find out whether their own action
        // worked.
        router.refresh();
      } else {
        setError(result.error);
      }
    } catch {
      setError('The action could not be completed. Nothing was changed.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        style={{
          padding: '8px 15px',
          borderRadius: 8,
          border: `1px solid ${accent}`,
          backgroundColor: 'transparent',
          color: accent,
          fontSize: 12.5,
          fontWeight: 700,
          fontFamily: FONT,
          cursor: 'pointer',
        }}
      >
        {label}
      </button>

      {open ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={title}
          onMouseDown={(e) => {
            if (e.target === e.currentTarget && !busy) close();
          }}
          style={{
            position: 'fixed',
            inset: 0,
            backgroundColor: '#000000B0',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: 20,
            zIndex: 100,
          }}
        >
          <div
            style={{
              backgroundColor: C.surface,
              border: `1px solid ${C.border}`,
              borderRadius: 12,
              padding: 22,
              width: '100%',
              maxWidth: 470,
              boxSizing: 'border-box',
            }}
          >
            <h3 style={{ margin: '0 0 10px', fontSize: 15.5, fontWeight: 800, color: accent }}>
              {title}
            </h3>

            <p style={{ color: C.text, fontSize: 13, lineHeight: 1.6, margin: '0 0 16px' }}>
              {consequence}
            </p>

            <label
              htmlFor="confirm-reason"
              style={{
                display: 'block',
                color: C.muted,
                fontSize: 10.5,
                fontWeight: 700,
                letterSpacing: 0.5,
                textTransform: 'uppercase',
                marginBottom: 6,
              }}
            >
              Reason (recorded in the audit log)
            </label>
            <textarea
              id="confirm-reason"
              ref={textareaRef}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder={reasonHint}
              rows={3}
              maxLength={MAX_REASON}
              disabled={busy}
              style={{
                width: '100%',
                padding: '10px 12px',
                borderRadius: 8,
                border: `1px solid ${C.border}`,
                backgroundColor: C.card,
                color: C.text,
                fontSize: 13,
                fontFamily: FONT,
                resize: 'vertical',
                boxSizing: 'border-box',
              }}
            />

            <div style={{ color: C.muted, fontSize: 11, margin: '6px 0 14px' }}>
              {trimmed.length < MIN_REASON
                ? `Type at least ${MIN_REASON} characters to enable the button. This is stored against your email address.`
                : `${trimmed.length}/${MAX_REASON} characters, attributed to your email address.`}
            </div>

            {error ? (
              <div
                style={{
                  border: `1px solid ${C.red}`,
                  backgroundColor: `${C.red}12`,
                  borderRadius: 8,
                  padding: '10px 12px',
                  color: C.red,
                  fontSize: 12.5,
                  marginBottom: 14,
                }}
              >
                {error}
              </div>
            ) : null}

            <div style={{ display: 'flex', gap: 10 }}>
              <button
                type="button"
                onClick={confirm}
                disabled={!canConfirm}
                style={{
                  flex: 1,
                  padding: '11px 18px',
                  borderRadius: 8,
                  border: `1px solid ${canConfirm ? accent : C.border}`,
                  backgroundColor: 'transparent',
                  color: canConfirm ? accent : C.muted,
                  fontSize: 13.5,
                  fontWeight: 700,
                  fontFamily: FONT,
                  cursor: canConfirm ? 'pointer' : 'not-allowed',
                }}
              >
                {busy ? 'Working…' : confirmLabel}
              </button>
              <button
                type="button"
                onClick={close}
                disabled={busy}
                style={{
                  flex: 1,
                  padding: '11px 18px',
                  borderRadius: 8,
                  border: `1px solid ${C.border}`,
                  backgroundColor: 'transparent',
                  color: C.muted,
                  fontSize: 13.5,
                  fontWeight: 600,
                  fontFamily: FONT,
                  cursor: busy ? 'default' : 'pointer',
                }}
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
