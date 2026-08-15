-- ════════════════════════════════════════════════════════════════════════
-- PHASE 4 — activation-link tokens + a code-level rate-limit log,
--           plus the server-side signup -> activation-email trigger.
--
-- Neither table is ever readable by anon or authenticated — these are pure
-- backend mechanisms, service_role only, same discipline as webhook_events.
--
-- NOTHING in this migration touches the Flutter app. The entire "user
-- finishes signup -> user receives an activation email" chain is server-side:
-- auth.users INSERT -> handle_new_user() -> licences INSERT -> the trigger at
-- the bottom of this file -> net.http_post -> /send-activation -> Resend.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 1. ACTIVATION TOKENS
-- ════════════════════════════════════════════════════════════════════════
create table public.activation_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  -- SHA-256 hash of the raw token, never the raw value. Mirrors how the
  -- Ed25519 private key's identity is proven via fingerprint, not exposure:
  -- even a full read of this table cannot produce a usable activation link.
  token_hash   text not null unique,
  expires_at   timestamptz not null,
  used_at      timestamptz,
  created_at   timestamptz not null default now()
);
create index idx_activation_tokens_user on public.activation_tokens(user_id);
create index idx_activation_tokens_expiry on public.activation_tokens(expires_at);

alter table public.activation_tokens enable row level security;
alter table public.activation_tokens force row level security;
-- No policies at all: zero client roles can read or write this table under
-- any circumstance. Only service_role (Edge Functions) touches it.
revoke all on public.activation_tokens from anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- 2. RATE-LIMIT LOG
-- ════════════════════════════════════════════════════════════════════════
create table public.activation_requests (
  id           uuid primary key default gen_random_uuid(),
  -- Store a hash of the identifier, not the raw email/phone, so this log
  -- itself isn't a second copy of user PII sitting in a rarely-audited table.
  identifier_hash text not null,
  ip           inet,
  created_at   timestamptz not null default now()
);
create index idx_activation_requests_window
  on public.activation_requests(identifier_hash, created_at desc);
create index idx_activation_requests_ip_window
  on public.activation_requests(ip, created_at desc);

alter table public.activation_requests enable row level security;
alter table public.activation_requests force row level security;
revoke all on public.activation_requests from anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════
-- 3. SERVICE_ROLE GRANTS  — REQUIRED, NOT OPTIONAL
--
-- WHY THIS SECTION EXISTS: on this project, a newly created table grants the
-- client roles only `Dxtm` (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) by default
-- privilege — verified live against pg_default_acl before writing this file.
-- service_role therefore has NO SELECT, INSERT or UPDATE on a fresh table.
-- Without the grants below, /send-activation fails with
--   42501: permission denied for table activation_tokens
-- on its very first query.
--
-- This is the same omission that already required three corrective
-- migrations: 20260812140944 (UPDATE for authenticated on profiles),
-- 20260813185001 (DML for service_role on profiles) and 20260814190500
-- (SELECT for service_role on licences). Granting it here, at table-creation
-- time, breaks that pattern rather than repeating it.
--
-- MINIMAL VERBS ONLY, matched to what each function actually does:
--   activation_tokens   — insert (mint), select (look up by hash),
--                         update (mark used). No DELETE: nothing in Phase 4
--                         deletes a token, and withholding it means a bug in
--                         either function cannot destroy the audit trail of
--                         which links were issued.
--   activation_requests — insert (log attempt), select (count the window).
--                         No UPDATE and no DELETE: this is an append-only
--                         rate-limit ledger. If code cannot delete rows, code
--                         cannot erase its own rate-limit history to escape
--                         the window.
--
-- anon and authenticated are granted NOTHING here and were revoked above.
grant select, insert, update on public.activation_tokens   to service_role;
grant select, insert         on public.activation_requests to service_role;


-- ════════════════════════════════════════════════════════════════════════
-- 4. SIGNUP -> ACTIVATION EMAIL  (Database Webhook, hand-rolled)
--
-- Supabase's dashboard "Database Webhooks" feature is a thin wrapper that
-- installs pg_net and generates a trigger calling supabase_functions
-- .http_request. Neither that schema nor pg_net existed on this project
-- (verified: pg_net was not installed, supabase_functions did not exist), so
-- the wrapper is built explicitly here instead. Two advantages:
--
--   • It is reproducible from source control rather than from dashboard
--     clicks that no reviewer can see or diff.
--   • The dashboard's generated trigger stores the auth header as a LITERAL
--     inside the trigger definition, where anyone who can run
--     pg_get_functiondef() reads the shared secret in plaintext. This version
--     reads it from Vault at call time, so the secret is not in this file, is
--     not in git, and is not in the catalog.
-- ════════════════════════════════════════════════════════════════════════

create extension if not exists pg_net;

create or replace function public.notify_activation_on_licence_insert()
returns trigger
language plpgsql
security definer
set search_path = public, net, vault, pg_temp
as $$
declare
  webhook_secret text;
  request_id     bigint;
begin
  -- ── Failure isolation ────────────────────────────────────────────────
  -- This trigger runs inside the signup transaction (auth.users INSERT ->
  -- handle_new_user() -> licences INSERT -> here). An unhandled exception
  -- would abort that transaction and the user could not sign up AT ALL.
  -- An activation email is a convenience; account creation is not. So every
  -- failure path below degrades to "no email sent", never "signup broken".
  begin
    select decrypted_secret into webhook_secret
      from vault.decrypted_secrets
     where name = 'activation_webhook_secret'
     limit 1;

    if webhook_secret is null then
      raise warning 'activation webhook skipped: vault secret not provisioned';
      return new;
    end if;

    -- pg_net queues the request and delivers it AFTER commit, asynchronously.
    -- Signup latency is therefore unaffected, and — importantly — the email
    -- cannot be sent for a signup that later rolls back.
    select net.http_post(
      url     := 'https://uomelinvbqabczhrzhnb.supabase.co/functions/v1/send-activation',
      body    := jsonb_build_object('user_id', new.user_id, 'source', 'signup_trigger'),
      params  := '{}'::jsonb,
      headers := jsonb_build_object(
                   'Content-Type',        'application/json',
                   -- Path A authentication. /send-activation compares this in
                   -- constant time against ACTIVATION_WEBHOOK_SECRET and only
                   -- then trusts the user_id in the body.
                   'x-activation-secret', webhook_secret
                 ),
      timeout_milliseconds := 5000
    ) into request_id;

  exception when others then
    -- Log for operators, swallow for the user.
    raise warning 'activation webhook failed (signup unaffected): %', sqlerrm;
  end;

  return new;
end $$;

-- Fires once per licence row. licences rows are created ONLY by
-- handle_new_user() (no client role holds INSERT on licences), so "a licence
-- row was inserted" is exactly equivalent to "a new user completed signup".
drop trigger if exists on_licence_created_send_activation on public.licences;
create trigger on_licence_created_send_activation
  after insert on public.licences
  for each row execute function public.notify_activation_on_licence_insert();


-- ── Housekeeping note, deliberately NOT automated here ──────────────────
-- Expired/used activation_tokens rows accumulate. They are inert (a used or
-- expired token is unusable by construction), so this is a storage concern,
-- not a security one. pg_cron is available but not enabled on this project;
-- adding a scheduled purge is a Phase 9 (ops) decision, not a Phase 4 one.
