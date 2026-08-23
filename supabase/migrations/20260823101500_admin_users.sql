-- ════════════════════════════════════════════════════════════════════════
-- ADMIN PORTAL — Phase 1 (read-only)
--
-- Two tables, both backend-only, both locked down identically to every other
-- money-relevant table in this project:
--
--   public.admin_users         — the allowlist. Membership in this table is
--                                the ONLY thing that grants admin access.
--   public.admin_otp_requests  — append-only rate-limit ledger for
--                                /admin-request-otp.
--
-- ── WHY admin_otp_requests IS A SEPARATE TABLE FROM activation_requests ──
-- The brief says to reuse the Phase 4 rate-limiting PATTERN (a request log
-- keyed by hashed identifier and IP, counted over a rolling window, written
-- whether or not the request is served). It does — the shape and indexes
-- below are deliberately identical. What it does not do is reuse the same
-- TABLE, for two reasons:
--
--   1. Shared budget. activation_requests already carries a per-IP hourly cap
--      for customer activation resends. Pouring admin login attempts into the
--      same ledger means a burst of admin logins could rate-limit a paying
--      customer's activation email, and vice versa. Two unrelated flows must
--      not be able to exhaust each other's budget.
--   2. Blast radius. activation_requests is read by send-activation, a
--      function this phase is forbidden to touch. Adding rows with a
--      different meaning to a table an untouched function counts over is a
--      change to that function's behaviour by the back door.
--
-- ── THE GRANT SECTION IS LOAD-BEARING, NOT BOILERPLATE ──────────────────
-- Verified live against pg_default_acl before writing this file: on this
-- project a table created by `postgres` in `public` grants
--     anon=Dxtm  authenticated=Dxtm  service_role=Dxtm
-- by default privilege — TRUNCATE/REFERENCES/TRIGGER/MAINTAIN and nothing
-- else. service_role therefore has NO SELECT on a fresh table, and every
-- Edge Function below would fail its first query with
--     42501: permission denied for table admin_users
-- This has already cost this project four corrective migrations
-- (20260812140944, 20260813185001, 20260814190500, 20260816120000).
-- Granting explicitly at table-creation time breaks that pattern rather than
-- repeating it a fifth time.
--
-- Note there is no `grant usage on sequence` clause here: both tables use
-- uuid primary keys with gen_random_uuid(), so neither owns a sequence.
-- (audit_log's bigserial DID need one — see 20260816120000.)
--
-- NOTHING IN THIS PHASE WRITES TO audit_log, AND ITS SCHEMA IS UNTOUCHED.
-- ════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════
-- 1. THE ALLOWLIST
--
-- Deliberately minimal. No `role` column, no `permissions` column, no
-- `is_active` flag: this phase is read-only and has exactly one privilege
-- level, so a column that encodes a distinction the code does not enforce
-- would be a lie that a future reader might trust. When actions arrive in a
-- later phase, the column that gates them gets added then, alongside the
-- code that honours it.
--
-- `email` is citext-free by design: Supabase Auth lowercases addresses, and
-- both Edge Functions normalise with .trim().toLowerCase() before every
-- comparison and before this insert. The unique constraint below is
-- therefore on an already-normalised value.
-- ════════════════════════════════════════════════════════════════════════
create table public.admin_users (
  id         uuid primary key default gen_random_uuid(),
  email      text not null unique,
  added_at   timestamptz not null default now()
);

comment on table public.admin_users is
  'Admin portal allowlist. Membership here is the sole grant of admin access. '
  'Read by Edge Functions via service_role only; no client role can see it. '
  'Rows are added by hand via a migration or the SQL editor, never by app code.';

alter table public.admin_users enable row level security;
alter table public.admin_users force row level security;

-- Strips the Dxtm default privilege documented above. Without this, anon and
-- authenticated would retain TRUNCATE on the allowlist — which is not a read
-- of admin data, but is a trivial way to lock every admin out of the tool.
revoke all on public.admin_users from anon, authenticated;

-- SELECT only. The Edge Functions read this table on every single call and
-- never write to it, so INSERT/UPDATE/DELETE would be privilege this phase
-- has no use for. Withholding them means a bug in any of the seven admin
-- functions cannot add an admin, remove an admin, or silently rewrite the
-- allowlist it is supposed to be checking against.
grant select on public.admin_users to service_role;

-- And take back the TRUNCATE that default privilege handed service_role.
-- `grant select` above does not remove it; it has to be revoked by name.
-- Reading admin_users is the only thing any Edge Function needs to do with
-- it, and TRUNCATE is not a read — but it IS a one-statement way to empty
-- the allowlist and lock every admin out of the tool permanently. The
-- allowlist is the single point on which all admin access turns, so the role
-- that consults it should not also be able to destroy it.
revoke truncate on public.admin_users from service_role;


-- ════════════════════════════════════════════════════════════════════════
-- 2. RATE-LIMIT LEDGER FOR /admin-request-otp
--
-- Same shape, same indexes and same append-only discipline as
-- public.activation_requests (20260814204500).
--
-- WHY THE IDENTIFIER IS HASHED EVEN THOUGH THE ALLOWLIST IS PLAINTEXT:
-- rows land here for addresses that are NOT on the allowlist — that is the
-- whole point, it is what catches someone probing the endpoint. Storing
-- those raw would turn this ledger into a log of every stranger's email
-- address who ever touched the admin URL, which is a worse liability than
-- the thing it protects. The hash is peppered, not bare: a bare SHA-256 of
-- an email address is reversible with a dictionary in seconds.
-- ════════════════════════════════════════════════════════════════════════
create table public.admin_otp_requests (
  id              uuid primary key default gen_random_uuid(),
  identifier_hash text not null,
  ip              inet,
  -- Records whether the address was on the allowlist at request time. This is
  -- the operationally useful signal: a run of `false` rows from one IP is
  -- somebody probing for admin addresses, and that is worth being able to see
  -- without being able to see who they were probing for.
  was_allowed     boolean not null default false,
  created_at      timestamptz not null default now()
);

comment on table public.admin_otp_requests is
  'Append-only rate-limit ledger for admin-request-otp. Mirrors '
  'activation_requests. Identifiers are peppered hashes, never raw addresses.';

create index idx_admin_otp_requests_window
  on public.admin_otp_requests(identifier_hash, created_at desc);
create index idx_admin_otp_requests_ip_window
  on public.admin_otp_requests(ip, created_at desc);

alter table public.admin_otp_requests enable row level security;
alter table public.admin_otp_requests force row level security;
revoke all on public.admin_otp_requests from anon, authenticated;

-- INSERT (log the attempt) and SELECT (count the window). No UPDATE, no
-- DELETE: if code cannot delete rows, code cannot erase its own rate-limit
-- history to escape the window.
grant select, insert on public.admin_otp_requests to service_role;


-- ════════════════════════════════════════════════════════════════════════
-- 3. SEED — the owner's own address, confirmed with the owner before this
--    file was written rather than guessed or left as a placeholder.
--
-- Lowercased to match the normalisation both Edge Functions apply to every
-- incoming address before comparing.
-- ════════════════════════════════════════════════════════════════════════
insert into public.admin_users (email) values ('hs0238766@gmail.com');
