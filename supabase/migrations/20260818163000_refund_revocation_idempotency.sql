-- ════════════════════════════════════════════════════════════════════════
-- revoke_licence_from_refund — IDEMPOTENCY GUARD
--
-- WHY THIS EXISTS (incident, 2026-08-16, user 2d3fcc83…):
--
-- One refund produced TWO legitimate Razorpay webhook events for the same
-- underlying refund (rfnd_TQZZIxXaF43SDe), thirty minutes apart:
--
--   20:27:27.708  refund.created    (event TQZZs07AOvvFio)  -> revoked
--   [a human restored the licence to 'active' by direct SQL in between]
--   20:57:34.965  refund.processed  (event TQa5gezdfgAEEz)  -> revoked AGAIN
--
-- The second event silently overwrote the manual restore. The licence read
-- 'revoked' for two days and the paywall correctly — and confusingly — told a
-- paying user they had no licence.
--
-- razorpay-webhook/index.ts deliberately handles BOTH event names, because
-- which one an account emits depends on dashboard configuration. Its comment
-- asserted that "the payment-level guard makes handling both harmless". No
-- such guard existed: the previous body ran the UPDATE unconditionally, its
-- only early return being `v_user is null` (unknown payment), which is not an
-- idempotency check. The assertion was wrong twice over — there was no guard,
-- and a re-revocation is only harmless while nothing has legitimately changed
-- the state in between. Here something had: a human.
--
-- THE GUARD: payments.status is the durable record that this payment's refund
-- has already been handled, and the first event sets it. Any later lifecycle
-- event for that payment is therefore a no-op. This mirrors the idempotency
-- already proven on the activation side.
--
-- RETURN VALUE: `true`, not `false`. The caller documents `false` as meaning
-- "no such payment on record" and logs it as `no_matching_payment`. An
-- already-handled refund IS on record and its licence IS revoked, so `true`
-- keeps that log line truthful without touching the Edge Function. `false`
-- would send the next person reading these logs down exactly the wrong path —
-- which is the failure mode this whole migration exists to prevent.
--
-- UNCHANGED, deliberately: security definer, `search_path` pinned to
-- public, pg_temp, the signature, and the grants. Nothing here touches
-- entitlement signing, the Ed25519 key, or the canonical token format.
--
-- STILL TRUE, and still a separate question: this revokes on ANY refund
-- regardless of amount. The incident refund was PARTIAL — 9000 minor units
-- against a 10900 payment. The original note in 20260815105545 stands: a
-- partial refund has no defined product meaning for a single lifetime
-- licence, and if partial refunds ever become a real workflow this is the
-- function that has to change. This migration does not change that
-- behaviour; it only stops the same refund being processed twice.
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
  select p.user_id, p.status into v_user, v_status
    from public.payments p
   where p.gateway = 'razorpay'
     and p.gateway_payment_id = p_gateway_payment_id;

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

-- Restated for parity with 20260815105545. `create or replace` preserves
-- existing privileges, so these are belt-and-braces rather than required.
revoke all on function public.revoke_licence_from_refund(text, text)
  from public, anon, authenticated;
grant execute on function public.revoke_licence_from_refund(text, text)
  to service_role;
