-- ════════════════════════════════════════════════════════════════════════
-- SECURITY FIX — profiles.email must not be client-writable.
--
-- ── WHAT WAS WRONG ──────────────────────────────────────────────────────
-- `protect_profile_fields` reverted exactly three columns for non-
-- service_role callers: country_code, signup_platform, deleted_at. Verified
-- live against pg_get_functiondef() before writing this file, not assumed.
--
-- `email` was in neither list — not protected, and not deliberately
-- client-writable the way first_name / last_name / phone are. Combined with
-- the pre-existing `authenticated` UPDATE grant and `profiles_update_own`
-- (both since 20260812134908), any signed-in user could run
--
--     update public.profiles set email = 'someone.else@example.com'
--      where id = auth.uid();
--
-- and it succeeded. Proven live in a rolled-back transaction: the row came
-- back carrying the attacker-chosen address.
--
-- ── WHY THAT IS NOT COSMETIC: THREE REAL CONSEQUENCES ───────────────────
--
-- 1. SIGNUP DENIAL OF SERVICE (the serious one).
--    profiles.email is UNIQUE. handle_new_user() inserts a new signup's
--    address with `on conflict (id) do nothing` — a clause that covers the
--    PRIMARY KEY and does nothing whatsoever for the email unique index. So
--    an attacker who parks a stranger's address on their own profile row
--    makes that address permanently unregisterable: the victim's signup
--    raises 23505 inside an AFTER INSERT trigger on auth.users, which aborts
--    the enclosing transaction and rolls the auth.users row back with it.
--    The victim cannot create an account at all, and the failure names
--    nothing they could act on. Also proven live, same transaction.
--
-- 2. ARBITRARY-RECIPIENT MAIL RELAY.
--    /send-activation looks a customer up by `profiles.email` (Path B) and
--    mails the activation link to whatever that column says. A rewritten
--    column therefore sends real, branded Danlite mail from the verified
--    sending domain to an address the attacker chose — burning Resend quota
--    against a shared customer-activation budget.
--
-- 3. GST INVOICE AND ADMIN-TOOL INTEGRITY.
--    portal/lib/gst.ts billedTo() renders profiles.email onto the invoice,
--    and admin-list-users / admin-user-detail / admin-audit-log all identify
--    a customer by it. A tamperable column means a self-chosen address on a
--    filed tax document, and an admin investigating that account being shown
--    an address the subject picked.
--
-- ── THE FIX ─────────────────────────────────────────────────────────────
-- One line: revert `email` alongside the other three. Identical mechanism,
-- identical service_role exemption, so a future server-side sync from
-- auth.users can still write the column — only the CLIENT loses the ability.
--
-- ── WHAT IS DELIBERATELY NOT CHANGED ────────────────────────────────────
-- first_name, last_name and phone stay client-writable. That was a reasoned
-- decision in 20260827120000 and it is still right: they select no pricing
-- rail, gate no entitlement, route no mail, and carry no unique constraint.
-- The user is the correct authority on their own contact details. This
-- migration adds nothing to that list and removes nothing from it.
--
-- No grant, policy, RLS setting, column or constraint is touched. The
-- function body gains one assignment; its signature, volatility, owner,
-- SECURITY DEFINER flag and pinned search_path are unchanged.
--
-- PRE-EXISTING AND UNCHANGED, stated so it is not mistaken for a regression
-- introduced here: nothing syncs profiles.email from auth.users after
-- signup, so the two can already drift if a user changes their address
-- through Supabase Auth. That gap predates this migration and is unaffected
-- by it — closing the client hole does not create it. It is the column's
-- missing writer, not its missing lock.
-- ════════════════════════════════════════════════════════════════════════

create or replace function public.protect_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Only service_role may change pricing/routing/identity-relevant fields.
  -- NOTE: reads the modern PostgREST GUC `request.jwt.claims` (a JSON blob).
  -- The legacy singular `request.jwt.claim.role` is no longer populated, so
  -- testing it would return NULL for EVERY caller — including service_role —
  -- and would silently discard legitimate Edge Function writes.
  if nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role'
       is distinct from 'service_role' then
    new.country_code    := old.country_code;
    new.signup_platform := old.signup_platform;
    new.deleted_at      := old.deleted_at;
    -- Added by this migration. See the header for the three exploits this
    -- closes. `email` is an identity and mail-routing field carrying a UNIQUE
    -- constraint; it belongs with country_code, not with first_name.
    new.email           := old.email;
  end if;
  return new;
end $$;
