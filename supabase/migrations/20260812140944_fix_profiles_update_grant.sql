-- ════════════════════════════════════════════════════════════════════════
-- FIX — grant UPDATE on public.profiles to authenticated
--
-- The initial migration created the `profiles_update_own` RLS policy and the
-- `profiles_protect_fields` trigger, both of which exist solely to police
-- client-side updates to a user's own profile row. But layer 1 (GRANTS) only
-- granted SELECT, so the update path was dead: every client UPDATE failed with
-- 42501 before RLS was ever consulted. RLS verification TEST 7 caught this.
--
-- This is strictly the missing half of the intended design, not a loosening:
--   • the policy still restricts the user to their OWN row (auth.uid() = id),
--   • the trigger still reverts country_code / signup_platform / deleted_at
--     for every non-service_role caller, so the pricing rail remains
--     unreachable from the client.
-- Layers 2 and 3 are unchanged. No new write path to licences or payments.
-- ════════════════════════════════════════════════════════════════════════

grant update on public.profiles to authenticated;
