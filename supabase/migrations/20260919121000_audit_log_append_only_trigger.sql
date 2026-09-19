-- ════════════════════════════════════════════════════════════════════════
-- AUDIT TRAIL INTEGRITY — enforce append-only in the DATABASE, not in the
-- privilege table alone.
--
-- ── WHERE THIS STOOD BEFORE ─────────────────────────────────────────────
-- Read live from information_schema.role_table_grants, not assumed:
--
--     audit_log  service_role  INSERT, REFERENCES, SELECT, TRIGGER
--     audit_log  postgres      DELETE, INSERT, REFERENCES, SELECT,
--                              TRIGGER, TRUNCATE, UPDATE
--
-- service_role is correct and already hardened: 20260823113000 added SELECT,
-- 20260823124500 took TRUNCATE back, and DML beyond INSERT was never
-- granted. No Edge Function can rewrite or remove an entry. That work stands
-- and nothing here changes it.
--
-- What it does NOT cover is the role that matters most in an incident.
-- `postgres` holds UPDATE, DELETE and TRUNCATE, and `postgres` is the role
-- behind the Supabase SQL Editor, `supabase db query --linked`, and any
-- holder of the database connection string. One statement —
--
--     delete from public.audit_log where actor_email = 'me@example.com';
--
-- — removed the record of an admin's own actions, silently, leaving no trace
-- of the deletion anywhere. An audit log whose subject can quietly edit it is
-- not evidence, and "even elevated access cannot quietly edit past entries"
-- is exactly the property this table is supposed to have.
--
-- Privileges alone cannot deliver it. Revoking UPDATE/DELETE from `postgres`
-- is ineffective: it owns the table, so it can grant them straight back.
--
-- ── WHY A TRIGGER IS THE RIGHT INSTRUMENT ───────────────────────────────
-- A BEFORE trigger is checked for EVERY caller, owner included, and is not
-- bypassed by ownership or by BYPASSRLS the way a policy is. The two ways
-- round it are both loud:
--
--   • `alter table public.audit_log disable trigger …` — DDL, requires
--     ownership, and is a deliberate, separate, named act rather than a
--     side effect of the DELETE itself;
--   • `set session_replication_role = 'replica'` — superuser-only, and the
--     Supabase `postgres` role is not a superuser, so this door is shut on
--     this project.
--
-- So this does not make tampering mathematically impossible for whoever owns
-- the database — nothing inside that database could. It converts a silent
-- one-liner into an explicit, conspicuous, separately-logged schema change,
-- which is the real difference between a trail that can be quietly edited
-- and one that cannot.
--
-- ── SAFE BY CONSTRUCTION ────────────────────────────────────────────────
-- Verified before writing this file:
--   • No UPDATE or DELETE of audit_log exists anywhere in supabase/functions,
--     lib/, portal/ or admin/. Every consumer either INSERTs (webhook,
--     entitlement, admin actions) or SELECTs (admin-audit-log).
--   • service_role holds no UPDATE, DELETE or TRUNCATE to begin with, so for
--     the Edge Functions this trigger is unreachable and changes nothing.
-- The fastest way to be sure this breaks nothing is that it forbids only
-- operations that no code performs.
--
-- ── A NOTE FOR WHOEVER ADDS RETENTION LATER ─────────────────────────────
-- A DPDP erasure job or a retention sweep that genuinely needs to remove old
-- audit rows will hit this trigger, and that is intended, not an oversight.
-- The correct shape for that work is an explicit, reviewed, time-boxed
-- `alter table public.audit_log disable trigger audit_log_no_rewrite`,
-- the purge, then re-enable — leaving a visible record that rows were
-- removed on purpose. Do not weaken this trigger to make a cron job tidier.
--
-- No column, constraint, index, grant, policy or RLS setting is touched, and
-- no existing row is read or written.
-- ════════════════════════════════════════════════════════════════════════

create or replace function public.audit_log_reject_mutation()
returns trigger
language plpgsql
-- Pinned for the same reason every other function in this project pins it:
-- an unpinned search_path lets anyone who can create objects in an earlier
-- schema hijack resolution. This body resolves nothing, but the rule is not
-- conditional on the body staying that simple.
set search_path = pg_catalog, pg_temp
as $$
begin
  raise exception
    'public.audit_log is append-only: % is not permitted', tg_op
    using errcode = 'insufficient_privilege',
          hint = 'Entries are never edited or removed. If a retention or '
                 'erasure sweep genuinely requires it, disable trigger '
                 'audit_log_no_rewrite explicitly and re-enable it after.';
end $$;

comment on function public.audit_log_reject_mutation() is
  'Guard for public.audit_log. Raises on UPDATE/DELETE/TRUNCATE so the audit '
  'trail is append-only for every role including the table owner, not merely '
  'for service_role by privilege.';

-- Row-level, for the two statements that can rewrite history one row at a
-- time. BEFORE, so the raise happens before any row is touched.
drop trigger if exists audit_log_no_rewrite on public.audit_log;
create trigger audit_log_no_rewrite
  before update or delete on public.audit_log
  for each row execute function public.audit_log_reject_mutation();

-- TRUNCATE fires no row-level trigger and is not constrained by the absence
-- of DELETE — it needs its own statement-level guard, or the whole table
-- still goes in one statement. This is the same hole 20260823124500 closed
-- for service_role by revoking the privilege; here it is closed for the
-- owner, who cannot be stopped by a revoke.
drop trigger if exists audit_log_no_truncate on public.audit_log;
create trigger audit_log_no_truncate
  before truncate on public.audit_log
  for each statement execute function public.audit_log_reject_mutation();
