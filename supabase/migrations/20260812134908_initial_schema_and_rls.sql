-- ════════════════════════════════════════════════════════════════════════
-- DANLITE ELM — INITIAL SCHEMA + ROW LEVEL SECURITY
-- Architecture v2: Android-only, Razorpay-only, one-time lifetime licence.
--
-- SECURITY MODEL (three independent layers):
--   1. GRANTS   — anon/authenticated are stripped to the minimum, so even a
--                 policy mistake cannot expose a table they have no grant on.
--   2. RLS      — every table has RLS enabled and per-user SELECT policies.
--   3. NO WRITE — licences and payments have NO insert/update/delete policy
--                 for any client role. Only the service_role (Edge Functions)
--                 can write them. This is the core anti-fraud control: a fully
--                 compromised client still cannot grant itself a licence.
-- ════════════════════════════════════════════════════════════════════════

-- ── Extensions ─────────────────────────────────────────────────────────
create extension if not exists "pgcrypto";   -- gen_random_uuid()

-- ── updated_at trigger helper ─────────────────────────────────────────
-- SECURITY DEFINER functions MUST pin search_path. Without it, a role able to
-- create objects in an earlier schema on the search path can hijack function
-- resolution and execute code with the function owner's privileges.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ════════════════════════════════════════════════════════════════════════
-- PROFILES — 1:1 with auth.users
-- country_code drives OTP routing: 'IN' -> SMS (Rs0.20), else -> EMAIL.
-- International SMS costs ~Rs6 = 6% of a $1.10 sale, so email-only for
-- non-India is an economic requirement, not a preference.
-- ════════════════════════════════════════════════════════════════════════
create table public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  email            text unique,
  phone            text unique,
  country_code     text not null default 'IN'
                     check (country_code ~ '^[A-Z]{2}$'),
  signup_platform  text not null default 'android'
                     check (signup_platform in ('android','web')),
  -- DPDP Act 2023: right to erasure. Soft-delete marker; a scheduled job
  -- performs hard deletion after the retention window.
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- ════════════════════════════════════════════════════════════════════════
-- LICENCES — the entitlement source of truth
-- UNIQUE(user_id) enforces "one purchase = one user" at the database level,
-- not merely in application logic.
-- ════════════════════════════════════════════════════════════════════════
create table public.licences (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null unique
                       references auth.users(id) on delete cascade,
  status             text not null default 'inactive'
                       check (status in ('inactive','active','revoked','refunded')),
  product_code       text not null default 'LIFETIME_V1',
  purchase_rail      text check (purchase_rail in ('razorpay_in','razorpay_intl')),
  purchased_at       timestamptz,
  -- Single-active-session enforcement (Phase 7 uses these).
  active_session_id  uuid,
  active_device_id   uuid,
  revoked_at         timestamptz,
  revoke_reason      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create trigger licences_updated_at before update on public.licences
  for each row execute function public.set_updated_at();

-- ════════════════════════════════════════════════════════════════════════
-- PAYMENTS — immutable ledger
-- amount_minor is BIGINT (paise/cents). Never float: floating point money
-- causes reconciliation drift.
-- UNIQUE(gateway, gateway_payment_id) is the replay-protection guarantee.
-- ════════════════════════════════════════════════════════════════════════
create table public.payments (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete restrict,
  gateway             text not null default 'razorpay'
                        check (gateway in ('razorpay')),
  gateway_order_id    text,
  gateway_payment_id  text not null,
  amount_minor        bigint not null check (amount_minor > 0),
  -- Constrained: a lowercase 'inr' typo would silently break reconciliation.
  currency            text not null check (currency in ('INR','USD')),
  status              text not null
                        check (status in ('created','authorized','captured','failed','refunded')),
  gst_invoice_no      text unique,
  raw_payload         jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  unique (gateway, gateway_payment_id)
);

-- ════════════════════════════════════════════════════════════════════════
-- DEVICES — registry for session binding and user-initiated remote logout
-- ════════════════════════════════════════════════════════════════════════
create table public.devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  fingerprint   text not null,
  platform      text not null default 'android'
                  check (platform in ('android','web')),
  model         text,
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  unique (user_id, fingerprint)
);

-- ════════════════════════════════════════════════════════════════════════
-- SESSIONS — issued and revocable; supersession is how sharing is blocked
-- ════════════════════════════════════════════════════════════════════════
create table public.sessions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  device_id      uuid not null references public.devices(id) on delete cascade,
  issued_at      timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  revoked_at     timestamptz,
  revoke_reason  text
);

-- ════════════════════════════════════════════════════════════════════════
-- WEBHOOK_EVENTS — hard idempotency for gateway callbacks
-- A replayed Razorpay webhook must never create a second licence. The unique
-- constraint makes double-processing impossible at the database level rather
-- than relying on application-code checks.
-- ════════════════════════════════════════════════════════════════════════
create table public.webhook_events (
  id            uuid primary key default gen_random_uuid(),
  gateway       text not null default 'razorpay',
  event_id      text not null,
  event_type    text,
  processed_at  timestamptz not null default now(),
  unique (gateway, event_id)
);

-- ════════════════════════════════════════════════════════════════════════
-- CONSENT_RECORDS — DPDP Act 2023 requires provable, versioned consent
-- ════════════════════════════════════════════════════════════════════════
create table public.consent_records (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  policy_version  text not null,
  consented_at    timestamptz not null default now(),
  ip              inet,
  user_agent      text
);

-- ════════════════════════════════════════════════════════════════════════
-- AUDIT_LOG — append-only; readable by nobody but service_role
-- ════════════════════════════════════════════════════════════════════════
create table public.audit_log (
  id          bigserial primary key,
  user_id     uuid,
  action      text not null,
  detail      jsonb not null default '{}'::jsonb,
  ip          inet,
  created_at  timestamptz not null default now()
);

-- ── Indexes on every FK lookup column ─────────────────────────────────
create index idx_payments_user        on public.payments(user_id);
create index idx_devices_user         on public.devices(user_id);
create index idx_sessions_user        on public.sessions(user_id);
create index idx_sessions_device      on public.sessions(device_id);
create index idx_consent_user         on public.consent_records(user_id);
create index idx_audit_user           on public.audit_log(user_id);
create index idx_audit_created        on public.audit_log(created_at desc);
create index idx_profiles_country     on public.profiles(country_code);

-- ════════════════════════════════════════════════════════════════════════
-- LAYER 1 — GRANTS
-- Strip everything from client roles, then grant back only what is needed.
-- RLS is layer 2; if a policy is ever wrong, a missing grant still blocks it.
-- ════════════════════════════════════════════════════════════════════════
revoke all on all tables in schema public from anon, authenticated;

-- Users may READ their own rows in these tables (rows filtered by RLS below).
grant select on public.profiles        to authenticated;
grant select on public.licences        to authenticated;
grant select on public.payments        to authenticated;
grant select on public.sessions        to authenticated;
grant select on public.consent_records to authenticated;

-- Devices is the one table a user may write: registering their own device and
-- updating last_seen. Still row-filtered by RLS.
grant select, insert, update on public.devices to authenticated;

-- anon (unauthenticated) gets NOTHING. Signup happens through Supabase Auth,
-- not through direct table access.
-- webhook_events and audit_log: no client grants at all — service_role only.

-- ════════════════════════════════════════════════════════════════════════
-- LAYER 2 — ROW LEVEL SECURITY
-- ════════════════════════════════════════════════════════════════════════
alter table public.profiles        enable row level security;
alter table public.licences        enable row level security;
alter table public.payments        enable row level security;
alter table public.devices         enable row level security;
alter table public.sessions        enable row level security;
alter table public.consent_records enable row level security;
alter table public.webhook_events  enable row level security;
alter table public.audit_log       enable row level security;

-- Force RLS even for the table owner, so a future misconfiguration of the
-- owning role cannot silently bypass policies.
alter table public.licences        force row level security;
alter table public.payments        force row level security;

-- ── SELECT: own rows only ─────────────────────────────────────────────
create policy profiles_select_own on public.profiles
  for select to authenticated using (auth.uid() = id);

create policy licences_select_own on public.licences
  for select to authenticated using (auth.uid() = user_id);

create policy payments_select_own on public.payments
  for select to authenticated using (auth.uid() = user_id);

create policy sessions_select_own on public.sessions
  for select to authenticated using (auth.uid() = user_id);

create policy consent_select_own on public.consent_records
  for select to authenticated using (auth.uid() = user_id);

-- ── DEVICES: users manage only their own device rows ──────────────────
create policy devices_select_own on public.devices
  for select to authenticated using (auth.uid() = user_id);
create policy devices_insert_own on public.devices
  for insert to authenticated with check (auth.uid() = user_id);
create policy devices_update_own on public.devices
  for update to authenticated
    using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── PROFILES: user may update only non-privileged fields of own row ───
-- country_code and signup_platform are intentionally NOT updatable by the
-- client: country_code determines pricing rail and OTP channel, so allowing
-- the client to change it would let a user pick the cheaper price.
create policy profiles_update_own on public.profiles
  for update to authenticated
    using (auth.uid() = id) with check (auth.uid() = id);

-- ════════════════════════════════════════════════════════════════════════
-- LAYER 3 — NO CLIENT WRITE PATH TO MONEY OR ENTITLEMENT
-- Deliberately absent: any insert/update/delete policy on licences,
-- payments, webhook_events, or audit_log for anon or authenticated.
-- Only service_role (which bypasses RLS) writes these, from Edge Functions,
-- and only after verifying a Razorpay webhook HMAC signature.
-- A rooted device, a stolen anon key, and a patched APK combined still cannot
-- create a licence.
-- ════════════════════════════════════════════════════════════════════════

-- ── Guard: block client-side privilege escalation on profiles ──────────
create or replace function public.protect_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Only service_role may change pricing/routing-relevant fields.
  -- NOTE: reads the modern PostgREST GUC `request.jwt.claims` (a JSON blob).
  -- The legacy singular `request.jwt.claim.role` is no longer populated, so
  -- testing it would return NULL for EVERY caller — including service_role —
  -- and would silently discard legitimate Edge Function writes.
  if nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role'
       is distinct from 'service_role' then
    new.country_code    := old.country_code;
    new.signup_platform := old.signup_platform;
    new.deleted_at      := old.deleted_at;
  end if;
  return new;
end $$;

create trigger profiles_protect_fields before update on public.profiles
  for each row execute function public.protect_profile_fields();
