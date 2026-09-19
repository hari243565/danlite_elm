-- ════════════════════════════════════════════════════════════════════════
-- revoke_licence_from_refund — close the remaining TOCTOU in the 2026-08-16
-- incident fix.
--
-- ── WHAT 20260818163000 GOT RIGHT, AND WHAT IT LEFT OPEN ────────────────
-- That migration added the idempotency guard this function was missing: if
-- payments.status is already 'refunded', change nothing — above all not the
-- licence, whose current value may since have been set deliberately by a
-- human. Verified still present on the live database during the 2026-09-19
-- audit, and it is correct.
--
-- What it did not do is make the guard atomic. The body reads
--
--     select p.user_id, p.status into v_user, v_status from payments …
--     …
--     update payments set status = 'refunded' …
--     update licences  set status = 'revoked' …
--
-- a plain check-then-act with no lock between the read and the writes. Two
-- deliveries of the same refund arriving close enough together — which is
-- exactly what the incident was, `refund.created` and `refund.processed` for
-- one refund — can both read status = 'captured', both pass the guard, and
-- both run the licence UPDATE.
--
-- ── WHY THAT IS NOT MERELY UNTIDY ───────────────────────────────────────
-- For the ordinary case the second write is harmless: it sets the same row to
-- the same values. The incident was not the ordinary case. Its harm came from
-- a human restoring the licence to 'active' BETWEEN the two events, and the
-- second event silently overwriting that restore. The guard exists to make
-- the second event a no-op — and a guard that two concurrent callers can both
-- pass is not a guard, it is a narrower window. The 30 minutes between those
-- two real deliveries happened to be wide; nothing guarantees the next pair
-- will be, and Razorpay retries can arrive milliseconds apart.
--
-- ── THE FIX ─────────────────────────────────────────────────────────────
-- `for update` on the payments row, so the status read and the two writes are
-- one critical section per payment. The second caller blocks until the first
-- commits, then re-reads status = 'refunded' and returns early — which is
-- what the guard was always supposed to do.
--
-- ── LOCK ORDER ──────────────────────────────────────────────────────────
-- This takes a lock on `payments`, a table none of the session functions
-- touch. claim_session / sign_out_all_devices / admin_grant_licence /
-- admin_revoke_licence all order licences -> devices -> sessions; this
-- function is the only one that locks payments, and it acquires that lock
-- FIRST and then writes licences without locking it, so it cannot form a
-- cycle with them. activate_licence_from_payment writes payments (via an
-- ON CONFLICT insert) and then licences — the same payments-before-licences
-- direction. No new deadlock cycle is introduced.
--
-- ── EVERYTHING ELSE IS DELIBERATELY BYTE-FOR-BYTE UNCHANGED ─────────────
-- Same signature, same SECURITY DEFINER, same pinned search_path, same
-- grants, same return-value contract (`true` for an already-handled refund,
-- `false` only for a payment this system has no record of — see
-- 20260818163000 for why that distinction matters to the caller's log line).
-- Partial refunds still revoke in full: that is a product question, still
-- open, and still not this migration's business to change.
-- ════════════════════════════════════════════════════════════════════════

create or replace function public.revoke_licence_from_refund(
  p_gateway_payment_id text,
  p_reason             text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user   uuid;
  v_status text;
begin
  -- `for update` added 2026-09-19. Everything below now runs inside this
  -- row lock, so two deliveries of the same refund are serialized by
  -- Postgres rather than racing.
  select p.user_id, p.status into v_user, v_status
    from public.payments p
   where p.gateway = 'razorpay'
     and p.gateway_payment_id = p_gateway_payment_id
     for update;

  -- Unknown payment: report it plainly and change nothing. Refunds for
  -- payments this system never recorded are possible (a manual dashboard
  -- refund of a test payment, for instance) and must not be an error.
  if v_user is null then
    return false;
  end if;

  -- Already handled by an earlier event in this refund's lifecycle. Change
  -- nothing: not the payment, and above all not the licence, whose current
  -- status may since have been set deliberately by a human.
  if v_status = 'refunded' then
    return true;
  end if;

  update public.payments set status = 'refunded'
   where gateway = 'razorpay'
     and gateway_payment_id = p_gateway_payment_id;

  update public.licences
     set status        = 'revoked',
         revoked_at    = now(),
         revoke_reason = p_reason
   where user_id = v_user;

  return true;
end $$;

-- Restated for parity with 20260815105545 and 20260818163000. `create or
-- replace` preserves existing privileges, so these are belt-and-braces.
revoke all on function public.revoke_licence_from_refund(text, text)
  from public, anon, authenticated;
grant execute on function public.revoke_licence_from_refund(text, text)
  to service_role;
