/* ════════════════════════════════════════════════════════════════════════
   SECURITY AUDIT (2026-09-19) — WEBHOOK IDEMPOTENCY / REPLAY REGRESSION

   Exercises the two RPCs that are the only code paths allowed to move money
   state, against the replay and double-delivery scenarios that have actually
   happened on this project.

   TEST 1 replays the 2026-08-16 incident EXACTLY, including the detail that
   caused the damage: a human restoring the licence between the two webhook
   deliveries for one refund. That is the regression test the incident never
   got.

   RUN:  npx supabase db query --linked -f supabase/tests/webhook_idempotency_regression.sql

   SAFETY: one transaction, ends in ROLLBACK, leaves no residue on the
   production database. Verdicts go into a scratch table because this
   transport discards NOTICE output. Re-verify residue afterwards.

   ⚠ ONE SIDE EFFECT THAT THE ROLLBACK DOES *NOT* UNDO — READ BEFORE RUNNING
   AGAINST PRODUCTION. This suite calls the real activate_licence_from_payment
   three times, and that function allocates a GST invoice number with
   nextval('public.invoice_seq'). nextval is exempt from transaction rollback
   by design, so each run permanently advances the live invoice sequence by
   about four and leaves that many gaps in the filed invoice series.

   20260815105545 documents such gaps as expected and truthful ("an invoice
   number was allocated for an attempt that did not complete"), so this is
   within the design's stated tolerance rather than a defect — but GST Rule
   46(b) asks for a consecutive serial number, and every run widens the gap
   an accountant may eventually ask about. Prefer a Supabase branch or a
   shadow database for routine runs, and reserve production runs for
   deliberately verifying a change to these two RPCs.

   The 2026-09-19 audit ran it twice against production, taking invoice_seq
   from 9 to 17 against 7 real payments. Recorded here rather than left for
   somebody to discover in a reconciliation.
   ════════════════════════════════════════════════════════════════════════ */

begin;

create table public._wh_probe (id int primary key, name text, verdict text);
alter table public._wh_probe disable row level security;

do $suite$
declare
  u     uuid := '9b000000-0000-4000-8000-00000000b001';
  inst  uuid := '00000000-0000-0000-0000-000000000000';
  pay   text := 'pay_AUDITPROBE0001';
  ord   text := 'order_AUDITPROBE0001';
  r1    boolean;
  r2    boolean;
  st    text;
  rr    text;
  inv1  text;
  inv2  text;
  dup1  boolean;
  dup2  boolean;
  cnt   int;
  pat   timestamptz;
begin

  /* A real signup, through the real trigger chain. */
  insert into auth.users (id, instance_id, aud, role, email)
    values (u, inst, 'authenticated', 'authenticated', 'whprobe-audit@test.local');

  insert into public.orders (user_id, gateway_order_id, amount_minor, currency, status)
    values (u, ord, 12900, 'INR', 'created');

  /* ── The capture. This is the only call that may activate a licence. ── */
  select already_processed, invoice_no into dup1, inv1
    from public.activate_licence_from_payment(
      u, ord, pay, 12900, 'INR', '{"probe":true}'::jsonb);

  select status, purchased_at into st, pat from public.licences where user_id = u;
  insert into public._wh_probe values (1, 'capture activates once',
    case when st = 'active' and dup1 = false and inv1 is not null
         then 'OK - active, invoice ' || inv1
         else 'FAIL - status=' || coalesce(st,'null')
              || ' already_processed=' || coalesce(dup1::text,'null') end);

  /* ── TEST 2 — REPLAY of the same capture. Razorpay retries; a redelivery
     must not mint a second payment row, a second invoice number, or move
     purchased_at. ── */
  select already_processed, invoice_no into dup2, inv2
    from public.activate_licence_from_payment(
      u, ord, pay, 12900, 'INR', '{"probe":"replay"}'::jsonb);

  select count(*) into cnt from public.payments
   where gateway = 'razorpay' and gateway_payment_id = pay;

  insert into public._wh_probe values (2, 'capture replay is idempotent',
    case when dup2 = true and cnt = 1 and inv2 = inv1
              and (select purchased_at from public.licences where user_id = u) = pat
         then 'BLOCKED - 1 payment row, same invoice, purchased_at unmoved'
         else 'EXPLOITABLE - rows=' || cnt || ' already_processed='
              || coalesce(dup2::text,'null') || ' invoice_changed='
              || (inv2 is distinct from inv1)::text end);

  /* ── TEST 3 — the refund revokes. ── */
  select public.revoke_licence_from_refund(pay, 'refund.created refund_id=rfnd_PROBE amount_minor=12900')
    into r1;
  select status into st from public.licences where user_id = u;
  insert into public._wh_probe values (3, 'refund revokes the licence',
    case when r1 = true and st = 'revoked' then 'OK - revoked'
         else 'FAIL - returned ' || coalesce(r1::text,'null')
              || ' status=' || coalesce(st,'null') end);

  /* ── TEST 4 — THE 2026-08-16 INCIDENT, REPLAYED.
     One refund produced refund.created and refund.processed 30 minutes
     apart. In between, a human restored the licence to 'active' by direct
     SQL. The second event overwrote that restore and a paying customer was
     told for two days that they had no licence.

     So: restore by hand, then deliver the second event. The licence MUST
     still be active afterwards. ── */
  update public.licences
     set status = 'active', revoked_at = null,
         revoke_reason = null
   where user_id = u;

  select public.revoke_licence_from_refund(pay, 'refund.processed refund_id=rfnd_PROBE amount_minor=12900')
    into r2;

  select status, coalesce(revoke_reason,'none') into st, rr
    from public.licences where user_id = u;

  insert into public._wh_probe values (4, 'second refund event cannot clobber a human restore',
    case when st = 'active' and r2 = true
         then 'BLOCKED - human restore survived, RPC still reported true'
         when st = 'active' and r2 is distinct from true
         then 'PARTIAL - restore survived but RPC returned '
              || coalesce(r2::text,'null') || ' (caller would log no_matching_payment)'
         else 'EXPLOITABLE - licence clobbered back to ' || st
              || ' reason=' || rr end);

  /* ── TEST 5 — REPLAY OF THE CAPTURE *AFTER* THE REFUND.
     The nastiest ordering, and the one worth being certain about: a refunded
     customer's original payment.captured being redelivered (a dashboard
     replay, or a retry whose first delivery 500'd and released its claim).
     It must NOT resurrect entitlement. The payment-level guard is what stops
     it — the payments row already exists, so the function returns before it
     reaches the licence upsert. ── */
  update public.licences set status = 'revoked', revoked_at = now(),
         revoke_reason = 'refund.created refund_id=rfnd_PROBE'
   where user_id = u;

  select already_processed into dup2
    from public.activate_licence_from_payment(
      u, ord, pay, 12900, 'INR', '{"probe":"post-refund replay"}'::jsonb);

  select status into st from public.licences where user_id = u;
  insert into public._wh_probe values (5, 'capture replay after refund cannot re-activate',
    case when st = 'revoked' and dup2 = true
         then 'BLOCKED - licence stayed revoked'
         else 'EXPLOITABLE - refunded customer re-activated, status=' || st end);

  /* ── TEST 6 — a refund for a payment this system never recorded must be a
     reported non-event, not an error and not a revocation of somebody. ── */
  select public.revoke_licence_from_refund('pay_DOES_NOT_EXIST_AUDIT', 'refund.created probe')
    into r1;
  insert into public._wh_probe values (6, 'refund for unknown payment is a no-op',
    case when r1 = false then 'OK - returned false, nothing changed'
         else 'FAIL - returned ' || coalesce(r1::text,'null') end);

  /* ── TEST 7 — invoice numbers come from a real sequence, so two captures
     can never collide on the gst_invoice_no unique constraint. ── */
  insert into public.orders (user_id, gateway_order_id, amount_minor, currency, status)
    values (u, ord || '_B', 12900, 'INR', 'created');
  select invoice_no into inv2
    from public.activate_licence_from_payment(
      u, ord || '_B', pay || '_B', 12900, 'INR', '{"probe":"second sale"}'::jsonb);
  insert into public._wh_probe values (7, 'invoice numbers are collision-free',
    case when inv2 is distinct from inv1 then 'OK - ' || inv1 || ' then ' || inv2
         else 'FAIL - duplicate invoice number ' || inv2 end);

  /* ── TEST 8 — no client role can execute either money RPC directly. The
     grants are service_role-only; this proves it rather than trusting it. ── */
  insert into public._wh_probe values (8, 'money RPCs not executable by clients',
    case when (select count(*) from information_schema.role_routine_grants
                where routine_schema = 'public'
                  and routine_name in ('activate_licence_from_payment',
                                       'revoke_licence_from_refund',
                                       'admin_grant_licence',
                                       'admin_revoke_licence')
                  and grantee in ('anon','authenticated','PUBLIC')) = 0
         then 'BLOCKED - 0 grants to anon/authenticated/PUBLIC'
         else 'EXPLOITABLE - a client role holds EXECUTE on a money RPC' end);

end $suite$;

select id, name, verdict from public._wh_probe order by id;

rollback;
