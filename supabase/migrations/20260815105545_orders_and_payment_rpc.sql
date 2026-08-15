-- ════════════════════════════════════════════════════════════════════════
-- PHASE 5 — orders (reconciliation only, never authoritative for
-- entitlement) + the single atomic function that is the ONLY code path
-- allowed to activate a licence from a payment.
--
-- THE GOVERNING RULE OF THIS PHASE, restated where it is enforced:
-- a licence becomes active only when a Razorpay webhook's HMAC-SHA256
-- signature has verified against the RAW request body. Nothing in this file
-- is reachable by anon or authenticated. The two functions below are
-- SECURITY DEFINER and granted to service_role ONLY, and service_role exists
-- solely inside Edge Functions. A fully compromised browser, a patched APK
-- and a stolen anon key still cannot reach either of them.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 1. ORDERS — reconciliation, and a second independent witness
--
-- An order row is NOT evidence of payment and never activates anything. It
-- exists for two reasons:
--   • reconciliation: "we asked Razorpay for N orders, we captured M";
--   • as the independent cross-check the webhook uses. Razorpay echoes the
--     notes we set at order creation, but notes travel in the webhook body.
--     The orders row does not. Comparing the two means an attacker would have
--     to forge a signature AND match a row they cannot see or influence.
-- ════════════════════════════════════════════════════════════════════════
create table public.orders (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  gateway_order_id  text not null unique,
  amount_minor      bigint not null check (amount_minor > 0),
  currency          text not null check (currency in ('INR','USD')),
  status            text not null default 'created'
                      check (status in ('created','paid','expired')),
  created_at        timestamptz not null default now()
);
create index idx_orders_user on public.orders(user_id);
-- The webhook's hot path is a lookup by gateway_order_id. Already covered by
-- the UNIQUE constraint's implicit index; stated here so nobody "optimises"
-- the constraint away later and silently loses the index with it.

alter table public.orders enable row level security;
alter table public.orders force row level security;
revoke all on public.orders from anon, authenticated;
-- No policies at all, deliberately: zero client roles read or write this
-- table under any circumstance. Reconciliation is a backend concern, not a
-- UI feature in this phase. /confirmation polls payments + licences, both of
-- which already have per-user SELECT policies from Phase 1.


-- ════════════════════════════════════════════════════════════════════════
-- 2. GST INVOICE NUMBERING
--
-- A real sequence, NOT count(*)+1. Two concurrent captures under count(*)+1
-- produce the same invoice number, which then collides on the
-- payments.gst_invoice_no UNIQUE constraint and fails one of the two
-- payments outright. nextval() is atomic and non-blocking.
--
-- Sequence gaps are expected and are NOT a defect: nextval is exempt from
-- transaction rollback by design. A gap means "an invoice number was
-- allocated for an attempt that did not complete", which is exactly the
-- truthful record.
--
-- ── FORMAT IS A PLACEHOLDER — CONFIRM WITH THE ACCOUNTANT ──────────────
-- Emitted as  INV/2026-27/000001  (Indian financial year, April-March).
-- CONFIRM THE ACTUAL FORMAT BEFORE THIS IS RELIED ON FOR FILED INVOICES.
-- It is functionally correct and collision-free either way; only the
-- string's shape is in question.
-- ════════════════════════════════════════════════════════════════════════
create sequence public.invoice_seq;

-- Deliberately NOT granted to service_role. The sequence is advanced only
-- from inside the SECURITY DEFINER function below, which runs with the
-- function owner's privileges. Withholding the direct grant means no Edge
-- Function bug can burn invoice numbers outside a real payment.


-- ════════════════════════════════════════════════════════════════════════
-- 3. activate_licence_from_payment
--    The single, sole, atomic entry point for turning a verified payment
--    into an active licence.
-- ════════════════════════════════════════════════════════════════════════
create or replace function public.activate_licence_from_payment(
  p_user_id            uuid,
  p_gateway_order_id   text,
  p_gateway_payment_id text,
  p_amount_minor       bigint,
  p_currency           text,
  p_raw_payload        jsonb
)
returns table (already_processed boolean, invoice_no text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invoice     text;
  v_fy_start    int;
  v_ist_date    date;
  -- GET DIAGNOSTICS ... ROW_COUNT yields an integer; it cannot be assigned
  -- to a boolean. Typed correctly here rather than relying on a cast.
  v_rows        int  := 0;
begin
  -- ── Invoice number, allocated before the insert that consumes it ─────
  -- Financial year computed in Asia/Kolkata, not UTC. now() is UTC on this
  -- project: a sale at 02:00 IST on 1 April is 20:30 UTC on 31 March, which
  -- naive UTC arithmetic would file into the PREVIOUS financial year. For a
  -- GST invoice series that is a real filing error, not a cosmetic one.
  v_ist_date := (now() at time zone 'Asia/Kolkata')::date;
  v_fy_start := case
                  when extract(month from v_ist_date) >= 4
                    then extract(year from v_ist_date)::int
                  else extract(year from v_ist_date)::int - 1
                end;

  -- ── Idempotency at the PAYMENT level ─────────────────────────────────
  -- Distinct from webhook_events, which guards DELIVERY-level idempotency.
  --
  -- This is written as INSERT ... ON CONFLICT DO NOTHING rather than
  -- "SELECT first, then INSERT if absent". The select-then-insert shape has
  -- a genuine race: two concurrent deliveries of the same payment both see
  -- no row, both insert, and one dies on the
  -- payments_gateway_gateway_payment_id_key UNIQUE constraint — turning a
  -- harmless duplicate into a 500 and an endless Razorpay retry loop.
  -- ON CONFLICT makes the UNIQUE constraint itself the concurrency control,
  -- so exactly one caller inserts and the other is told so calmly.
  v_invoice := 'INV/' || v_fy_start::text || '-'
               || lpad(((v_fy_start + 1) % 100)::text, 2, '0') || '/'
               || lpad(nextval('public.invoice_seq')::text, 6, '0');

  insert into public.payments
    (user_id, gateway, gateway_order_id, gateway_payment_id,
     amount_minor, currency, status, gst_invoice_no, raw_payload)
  values
    (p_user_id, 'razorpay', p_gateway_order_id, p_gateway_payment_id,
     p_amount_minor, p_currency, 'captured', v_invoice, p_raw_payload)
  on conflict (gateway, gateway_payment_id) do nothing;

  get diagnostics v_rows = row_count;

  if v_rows = 0 then
    -- Redelivery, or a race we lost. Report the ALREADY-STORED invoice
    -- number, not the one just allocated — the customer must keep seeing the
    -- same invoice number forever. Note this reads gst_invoice_no by row
    -- existence, not by "is the invoice column non-null": conflating those
    -- two would let a hypothetical null-invoice row fall through to a second
    -- insert attempt.
    select p.gst_invoice_no into v_invoice
      from public.payments p
     where p.gateway = 'razorpay'
       and p.gateway_payment_id = p_gateway_payment_id;

    return query select true, v_invoice;
    return;
  end if;

  -- ── The licence itself ───────────────────────────────────────────────
  -- Reached ONLY on the delivery that actually inserted the payment row.
  -- A redelivery returned above, so purchased_at cannot be bumped by a
  -- replay — which is precisely what the Step 6 replay test asserts.
  --
  -- on conflict (user_id) targets licences_user_id_key. Every user already
  -- has an 'inactive' row from handle_new_user(), so in practice this is
  -- always the UPDATE branch; the INSERT branch is there so a user somehow
  -- lacking a row still gets one rather than silently not being activated.
  --
  -- revoked_at / revoke_reason are cleared: a fresh paid purchase after an
  -- earlier refund is a clean slate, and leaving a stale revoke reason on an
  -- active licence would be an outright lie in the audit trail.
  insert into public.licences
    (user_id, status, product_code, purchase_rail, purchased_at)
  values
    (p_user_id, 'active', 'LIFETIME_V1', 'razorpay_in', now())
  on conflict (user_id) do update
    set status        = 'active',
        product_code  = 'LIFETIME_V1',
        purchase_rail = 'razorpay_in',
        purchased_at  = now(),
        revoked_at    = null,
        revoke_reason = null;

  -- Reconciliation only. Not load-bearing: if this row were missing the
  -- licence above is still correctly active.
  update public.orders set status = 'paid'
   where gateway_order_id = p_gateway_order_id;

  return query select false, v_invoice;
end $$;

revoke all on function public.activate_licence_from_payment(
  uuid, text, text, bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.activate_licence_from_payment(
  uuid, text, text, bigint, text, jsonb) to service_role;


-- ════════════════════════════════════════════════════════════════════════
-- 4. revoke_licence_from_refund — the refund counterpart. Same discipline.
--
-- PARTIAL REFUNDS, stated rather than silently ignored: this revokes on ANY
-- refund. The product is a single ₹109 lifetime licence with nothing to
-- partially un-sell, so a partial refund has no defined product meaning
-- here. p_reason carries the refund id and amount so an operator can see
-- exactly what happened. If partial refunds ever become a real workflow this
-- is the function that has to change.
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
  v_user uuid;
begin
  select p.user_id into v_user
    from public.payments p
   where p.gateway = 'razorpay'
     and p.gateway_payment_id = p_gateway_payment_id;

  -- Unknown payment: report it plainly and change nothing. Refunds for
  -- payments this system never recorded are possible (a manual dashboard
  -- refund of a test payment, for instance) and must not be an error.
  if v_user is null then
    return false;
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

revoke all on function public.revoke_licence_from_refund(text, text)
  from public, anon, authenticated;
grant execute on function public.revoke_licence_from_refund(text, text)
  to service_role;


-- ════════════════════════════════════════════════════════════════════════
-- 5. SERVICE_ROLE GRANTS — REQUIRED, NOT OPTIONAL
--
-- VERIFIED LIVE against pg_default_acl and information_schema.role_table_
-- grants immediately before writing this file, exactly as Phase 4 had to.
-- What service_role actually held on 2026-08-15, before this migration:
--
--     payments        REFERENCES, TRIGGER, TRUNCATE          <- no DML AT ALL
--     webhook_events  REFERENCES, TRIGGER, TRUNCATE          <- no DML AT ALL
--     audit_log       REFERENCES, TRIGGER, TRUNCATE          <- no DML AT ALL
--     licences        REFERENCES, SELECT, TRIGGER, TRUNCATE  <- read only
--     orders          (did not exist)
--
-- The default ACL for tables owned by `postgres` on this project is
--     service_role=Dxtm/postgres
-- i.e. TRUNCATE/REFERENCES/TRIGGER/MAINTAIN and nothing else. A newly
-- created table therefore gives service_role NO read or write path.
--
-- WITHOUT THIS SECTION the razorpay-webhook function fails with
--     42501: permission denied for table webhook_events
-- on its very first statement — after the signature has already verified,
-- meaning a genuinely paid customer would never be activated. This is the
-- same omission class that already required four corrective migrations
-- (20260812140944, 20260813185001, 20260814190500, and the pre-emptive
-- grants block in 20260814204500). Granting at table-creation time here
-- continues to break the pattern rather than repeat it.
--
-- MINIMAL VERBS ONLY, matched to what the code actually does:
--
--   orders          select, insert, update — created at /create-order,
--                   read by the webhook as the independent cross-check,
--                   updated to 'paid'. No DELETE: nothing deletes an order,
--                   and withholding it means no bug can erase the
--                   reconciliation trail.
--
--   payments        select, insert, update — insert on capture, select for
--                   idempotency, update on refund. NO DELETE, deliberately:
--                   payments is an immutable ledger. If code cannot delete a
--                   payment row, no bug and no injection can make a sale
--                   disappear.
--
--   licences        select, insert, update — the entitlement write path.
--                   Phase 3 granted SELECT only and explicitly deferred
--                   INSERT/UPDATE to "Phase 5/6 ... as an explicit and
--                   reviewable decision". This is that decision.
--                   No DELETE: a licence is revoked, never erased.
--
--   webhook_events  select, insert, delete — select+insert for delivery
--                   idempotency. DELETE is the one non-obvious verb and it
--                   is load-bearing: the webhook claims an event id BEFORE
--                   processing (so two concurrent deliveries cannot both
--                   proceed), and if processing then fails it must release
--                   that claim, or Razorpay's retry would be suppressed as
--                   a "duplicate" and a paying customer would never be
--                   activated. That silent-loss failure mode is far worse
--                   than the narrow risk this grant carries.
--                   No UPDATE: an event record is never edited.
--
--   audit_log       insert only — append-only by construction. No SELECT
--                   (nothing in this phase reads it back), no UPDATE, no
--                   DELETE: code that cannot rewrite the audit log cannot
--                   cover its own tracks.
--
-- anon and authenticated are granted NOTHING here and gain no new
-- capability from this migration whatsoever.
-- ════════════════════════════════════════════════════════════════════════
grant select, insert, update         on public.orders         to service_role;
grant select, insert, update         on public.payments       to service_role;
grant select, insert, update         on public.licences       to service_role;
grant select, insert, delete         on public.webhook_events to service_role;
grant insert                         on public.audit_log      to service_role;
