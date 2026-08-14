-- ════════════════════════════════════════════════════════════════════════
-- PHASE 3 — licence row autocreation + entitlement read path
--
-- Two things happen here, both prerequisites for the /entitlement Edge
-- Function:
--
--   1. Every new auth user gets a `licences` row (status='inactive') in the
--      SAME transaction that creates their `profiles` row, plus a backfill for
--      the users who already exist.
--   2. service_role is granted SELECT on public.licences so the Edge Function
--      can actually read it. See the grant section for why this was missing.
--
-- NOTHING here gates any feature. Phase 8 owns the paywall. A row with
-- status='inactive' is simply the truthful statement "this user has not paid
-- yet", which is what /entitlement must be able to report.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1. Extend the signup factory to also mint the licence row ──────────
--
-- This is a CREATE OR REPLACE of the function introduced in
-- 20260813130250_profile_autocreate_on_signup.sql. The profiles half below is
-- reproduced VERBATIM from the live definition (read back with
-- pg_get_functiondef before writing this migration, not guessed) — only the
-- licences insert is new. If the profiles half is ever edited, edit it here,
-- because this file is now the authoritative definition.
--
-- WHY IN THE TRIGGER AND NOT CLIENT-SIDE: identical reasoning to the profiles
-- row. `authenticated` has SELECT and nothing else on public.licences — no
-- insert grant, no insert policy. A patched APK therefore cannot mint itself a
-- licence row, let alone one with status='active'. Creating it server-side in
-- the same transaction as the auth user means the row cannot be missing, and
-- cannot be attacker-controlled.
--
-- WHY status='inactive' EXPLICITLY: it is also the column default, but stating
-- it makes the security property legible at the call site — signup never
-- produces an entitled user. Payment (Phase 5/6) is the only thing that may
-- ever move a row to 'active'.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  meta_country  text;
  meta_platform text;
begin
  -- Read the signup metadata if the client sent any, but never trust its
  -- shape: an unrecognised value falls back to the column default rather than
  -- tripping the table's CHECK constraint and aborting the signup.
  meta_country := upper(nullif(trim(new.raw_user_meta_data->>'country_code'), ''));
  if meta_country !~ '^[A-Z]{2}$' then
    meta_country := null;
  end if;

  meta_platform := lower(nullif(trim(new.raw_user_meta_data->>'signup_platform'), ''));
  if meta_platform is distinct from 'android'
     and meta_platform is distinct from 'web' then
    meta_platform := null;
  end if;

  -- nullif on email/phone is load-bearing: GoTrue stores the unused channel as
  -- '' rather than NULL, and profiles.email / profiles.phone are UNIQUE. Two
  -- email signups would both insert phone = '' and the second would fail.
  insert into public.profiles (id, email, phone, country_code, signup_platform)
  values (
    new.id,
    nullif(new.email, ''),
    nullif(new.phone, ''),
    coalesce(meta_country, 'IN'),
    coalesce(meta_platform, 'android')
  )
  on conflict (id) do nothing;

  -- ── NEW IN PHASE 3 ──────────────────────────────────────────────────
  -- Same transaction as the profile above: either the user gets both rows or
  -- the signup fails outright. There is no window in which a user exists with
  -- a profile but no licence.
  --
  -- on conflict (user_id) targets the licences_user_id_key UNIQUE constraint.
  -- It makes a re-fired trigger or a re-run backfill harmless, and — more to
  -- the point — guarantees this can never clobber an ALREADY PAID licence back
  -- to 'inactive'.
  --
  -- active_session_id / active_device_id are deliberately left NULL: those
  -- columns are Phase 7 (single active session) and nothing assigns them yet.
  insert into public.licences (user_id, status)
  values (new.id, 'inactive')
  on conflict (user_id) do nothing;

  return new;
end $$;

-- The trigger itself is unchanged (still AFTER INSERT on auth.users) and is
-- recreated only so this migration is self-contained and idempotent.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ── 2. Backfill users who predate this migration ───────────────────────
-- Every auth user without a licence row gets one now. Idempotent, and the
-- `not exists` guard plus on conflict means an existing paid licence is never
-- touched. Driven off auth.users (not profiles) so a user somehow lacking a
-- profile still gets a licence rather than being silently skipped.
insert into public.licences (user_id, status)
select u.id, 'inactive'
from auth.users u
where not exists (select 1 from public.licences l where l.user_id = u.id)
on conflict (user_id) do nothing;


-- ── 3. Let service_role read licences ──────────────────────────────────
--
-- WHY THIS WAS MISSING: 20260812134908 ran
--   revoke all on all tables in schema public from anon, authenticated;
-- and granted back per role, but service_role was never granted DML on
-- public.licences — it holds only REFERENCES / TRIGGER / TRUNCATE. This is the
-- exact same class of omission as 20260812140944 (missing UPDATE for
-- authenticated) and 20260813185001 (missing DML for service_role on
-- profiles), now for service_role on licences.
--
-- WITHOUT THIS the /entitlement Edge Function fails with 42501 on its very
-- first query. service_role already has BYPASSRLS, so the RLS policies were
-- never the obstacle — the missing table-level grant was.
--
-- SELECT ONLY, DELIBERATELY: /entitlement only reads. It has no reason to
-- write, and a read-only grant means a bug or an injection in that function
-- cannot activate, revoke, or delete anybody's licence. Phase 5/6 (Razorpay
-- webhooks) will need INSERT/UPDATE and must add them in their own migration,
-- as an explicit and reviewable decision rather than a privilege inherited
-- from here.
--
-- NOT A LOOSENING OF THE CLIENT SURFACE: service_role is the Edge Function
-- key. It never ships in the APK and never reaches a browser. anon and
-- authenticated are untouched — `authenticated` still holds only SELECT on
-- licences, constrained by licences_select_own to its own row, and still has
-- no way to create or modify a licence by any path.
grant select on public.licences to service_role;
