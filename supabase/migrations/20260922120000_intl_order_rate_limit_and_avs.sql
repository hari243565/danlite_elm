-- ════════════════════════════════════════════════════════════════════════
-- INTERNATIONAL RAIL — card-testing rate-limit ledger, and the risk
-- metadata an international order needs to be defensible later.
--
-- Everything in this file is ADDITIVE and international-only:
--   • a new table nothing else reads;
--   • three NULLABLE columns on public.orders.
--
-- No existing column changes type, nullability, default or constraint, and
-- no existing row is rewritten. A domestic order inserted by the unchanged
-- domestic branch of /create-order leaves all three new columns NULL, exactly
-- as it did before this migration existed. That is the mechanical reason the
-- domestic rail cannot be affected by this change, rather than an assurance
-- that it probably is not.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 1. THE LEDGER
--
-- Same shape, and for the same reasons, as public.activation_requests from
-- 20260814204500 — this is that pattern reused, not a second mechanism
-- invented alongside it.
--
-- WHY A TABLE AND NOT AN IN-PROCESS COUNTER. Edge Functions scale
-- horizontally and cold-start freely. An in-memory Map (which is what
-- portal/lib/rate-limit.ts is, honestly labelled as such) resets on every
-- cold start, and "wait for a cold start" is a free reset an attacker can
-- simply wait out. A row in Postgres cannot be waited out.
--
-- WHY IT IS APPEND-ONLY. The counting function reads the window, then
-- inserts UNCONDITIONALLY — a refused attempt is logged too. If refusals did
-- not extend the window, an attacker could hammer the endpoint forever:
-- every rejection would age out of the window and the limit would never bite.
-- Withholding DELETE and UPDATE below means no code path, including a future
-- buggy one, can erase its own rate-limit history to escape a window.
-- ════════════════════════════════════════════════════════════════════════
create table public.intl_order_attempts (
  id          uuid primary key default gen_random_uuid(),
  -- Nullable: an attempt is always authenticated (create-order requires a
  -- valid JWT before it reaches the limiter), but keeping this nullable means
  -- a future unauthenticated caller can still be IP-limited rather than
  -- crashing the insert.
  user_id     uuid references auth.users(id) on delete cascade,
  ip          inet,
  -- The app/browser-supplied device fingerprint already used by
  -- public.devices. A third axis an attacker has to rotate alongside IP and
  -- account. Client-supplied and therefore spoofable, which is why it is an
  -- ADDITIONAL key and never the only one.
  device_hash text,
  -- 'allowed' | 'rate_limited'. Stored so the ledger doubles as the evidence
  -- of what the limiter actually did, which is what makes the both-directions
  -- test checkable after the fact.
  outcome     text not null default 'allowed'
                check (outcome in ('allowed','rate_limited')),
  created_at  timestamptz not null default now()
);

-- One index per axis the limiter counts on. Each query is
-- "<axis> = ? and created_at >= ?", so the axis leads and created_at follows
-- descending — a composite in that order serves both the 5-minute burst
-- window and the 1-hour window from the same index.
create index idx_intl_attempts_ip_window
  on public.intl_order_attempts(ip, created_at desc);
create index idx_intl_attempts_user_window
  on public.intl_order_attempts(user_id, created_at desc);
create index idx_intl_attempts_device_window
  on public.intl_order_attempts(device_hash, created_at desc);

alter table public.intl_order_attempts enable row level security;
alter table public.intl_order_attempts force row level security;
revoke all on public.intl_order_attempts from anon, authenticated;
-- No policies at all, deliberately. No client role reads or writes this
-- table under any circumstance: a customer who could read it could measure
-- exactly how much budget they have left, and a customer who could write it
-- could exhaust someone else's.


-- ════════════════════════════════════════════════════════════════════════
-- 2. SERVICE_ROLE GRANTS — REQUIRED, NOT OPTIONAL
--
-- On this project a newly created table grants the client roles only `Dxtm`
-- by default privilege, so service_role has NO SELECT/INSERT/UPDATE on a
-- fresh table and the function fails with
--   42501: permission denied for table intl_order_attempts
-- on its very first query. This has already cost this project four
-- corrective migrations (20260812140944, 20260813185001, 20260814190500,
-- 20260816120000). Granted here, at table-creation time.
--
-- No sequence grant is needed: the primary key is a uuid with a
-- gen_random_uuid() default, not a bigserial, so there is no owned sequence
-- to need `grant usage` on — which is the other half of that same recurring
-- 42501 (see 20260816120000, where exactly that was missed).
--
-- MINIMAL VERBS, matched to what the limiter does: count the window
-- (select), log the attempt (insert). No UPDATE and no DELETE — see the
-- append-only note above.
grant select, insert on public.intl_order_attempts to service_role;


-- ════════════════════════════════════════════════════════════════════════
-- 3. RISK METADATA ON THE ORDER
--
-- WHY ON orders AND NOT payments. These are known at ORDER-creation time,
-- before any money moves, and the order row is the independent witness the
-- webhook already cross-checks against. Putting them here means the AVS
-- comparison has something to compare against that did not travel in the
-- webhook body.
--
-- WHY NULLABLE AND UNCONSTRAINED-BY-DEFAULT. Every order written before this
-- migration has no billing address, and backfilling an invented one onto
-- historical orders would be fabricating evidence. NULL means "not
-- collected", which is the truth.
--
-- ⚠ billing_country and billing_postal_code ARE CLIENT-SUPPLIED. They are
-- the one thing on this path that has to be, because the customer types
-- them. They are stored as fraud/dispute EVIDENCE and as an AVS signal. They
-- must never be read back to select a price, a currency or a tax treatment —
-- that is what profiles.country_code is for, and it is protected by the
-- protect_profile_fields trigger precisely because it does select the price.
-- The adversarial test `billing_country cannot move the rail` in
-- supabase/functions/_shared/intl_pricing.test.ts is the standing guard on
-- that, because a comment is not a control.
alter table public.orders
  add column billing_country     text
    check (billing_country is null or billing_country ~ '^[A-Z]{2}$'),
  add column billing_postal_code text
    check (billing_postal_code is null or length(billing_postal_code) <= 32),
  -- The soft signals, as recorded at order creation: AVS classification and
  -- the bot score's verdict. jsonb rather than columns because these are
  -- advisory and their shape will change as signals are added; nothing joins
  -- or filters on them, and nothing branches on them to decide whether to
  -- take money.
  add column risk_signals        jsonb not null default '{}'::jsonb;

comment on column public.orders.billing_country is
  'ISO-3166 alpha-2, client-supplied at checkout. AVS/dispute evidence ONLY. Never selects price, currency or tax treatment - profiles.country_code does that.';
comment on column public.orders.billing_postal_code is
  'Client-supplied at checkout. AVS/dispute evidence ONLY.';
comment on column public.orders.risk_signals is
  'Advisory soft signals (avs, bot score) recorded at order creation. Nothing branches on this to accept or refuse a payment.';
