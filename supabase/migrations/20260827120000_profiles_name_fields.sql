-- ════════════════════════════════════════════════════════════════════════
-- PROFILES — first_name / last_name, and phone as contact data
--
-- The "Create your account" screen now collects a name (required) and a phone
-- number (optional). Neither is an authentication factor: email OTP remains
-- the only way anybody proves who they are, and nothing in this migration or
-- anywhere downstream sends a code, an SMS or a verification of any kind to
-- profiles.phone.
--
-- ── HOW THESE COLUMNS GET POPULATED ──────────────────────────────────────
-- By the CLIENT, in an authenticated UPDATE immediately after the OTP is
-- verified — NOT by handle_new_user() off the signup metadata.
--
-- handle_new_user() is deliberately left untouched by this migration. The
-- write path this uses already exists in full and was designed for exactly
-- this kind of field:
--
--   • 20260812140944 granted UPDATE on public.profiles to `authenticated`;
--   • `profiles_update_own` (20260812134908) restricts that to auth.uid() = id;
--   • `protect_profile_fields` (same migration) enumerates the columns a
--     client may NOT set — country_code, signup_platform, deleted_at — and
--     reverts them for every non-service_role caller. first_name, last_name
--     and phone are not in that list and are not being added to it: unlike
--     country_code they select no pricing rail, gate no entitlement, and route
--     nothing. They are the user's own contact details, and the user is the
--     correct authority on them.
--
-- The alternative — riding along in signInWithOtp's `data:` payload for the
-- trigger to read, the way country_code does — was rejected for two reasons
-- recorded here so it is not retried:
--
--   1. supabase_service.dart sends that payload on the LOG-IN path too,
--      precisely so sign-up and log-in are byte-identical on the wire and
--      cannot be used to enumerate registered addresses. A name the log-in
--      screen has no field for cannot be added to it, so adding one to the
--      sign-up payload would reintroduce that difference.
--   2. GoTrue copies raw_user_meta_data into the `user_metadata` claim of
--      every access token it issues. Routing a customer's name and phone
--      through it would put both in every JWT the app holds and forwards.
--
-- ── COLUMNS ──────────────────────────────────────────────────────────────
-- Nullable at the database level, deliberately. The screen requires a name;
-- the database must not, because every account created before this feature
-- has none and a NOT NULL would have to invent one for them. Nullable is the
-- honest representation of "we never asked this person".
-- ════════════════════════════════════════════════════════════════════════

alter table public.profiles
  add column if not exists first_name text,
  add column if not exists last_name  text;

-- Length ceilings only. NO character-set constraint, and none is coming: this
-- app sells internationally, and real names carry apostrophes, hyphens,
-- accents and non-Latin scripts. A regex here would reject real customers.
-- The bounds exist so a pasted document cannot become a name.
alter table public.profiles
  add constraint profiles_first_name_len check (char_length(first_name) <= 80),
  add constraint profiles_last_name_len  check (char_length(last_name)  <= 80);

-- ── phone: drop UNIQUE ───────────────────────────────────────────────────
-- profiles.phone was created UNIQUE in 20260812134908, when phone was an
-- IDENTITY channel — the India signup rail was to be SMS OTP, and one number
-- had to mean one account. That rail was removed on 2026-08-25; auth is
-- email-only and permanently so, and the column was kept explicitly for a
-- future use like this one.
--
-- As contact data the constraint is now wrong, and actively harmful: two
-- people who legitimately share a number — a household, a workshop's counter
-- line — would see the second signup's profile write fail with 23505 on a
-- field that decides nothing. Uniqueness was protecting an authentication
-- property that no longer exists.
--
-- Nothing depends on it. No foreign key references profiles.phone, no upsert
-- names it as a conflict target, and no code path looks a user up by it —
-- admin-list-users only ILIKEs it as a search term.
alter table public.profiles drop constraint if exists profiles_phone_key;

alter table public.profiles
  add constraint profiles_phone_len check (char_length(phone) <= 32);

-- ── GRANTS AND POLICIES: UNCHANGED ───────────────────────────────────────
-- No grant, no policy and no trigger is created, altered or dropped here.
-- `authenticated` gains nothing it did not already hold: the UPDATE grant and
-- `profiles_update_own` have both existed since Phase 1, and this migration
-- only adds columns for them to reach. There is still no client INSERT path
-- to profiles, and still no client write path of any kind to licences or
-- payments.
-- ════════════════════════════════════════════════════════════════════════
