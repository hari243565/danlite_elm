-- ════════════════════════════════════════════════════════════════════════
-- FIX — create public.profiles automatically when an auth user is created
--
-- BUG: a verified signup produced a row in auth.users but never in
-- public.profiles. Confirmed on the live project: 2 auth users, 0 profiles.
--
-- ROOT CAUSE: profile creation was written client-side (AuthProvider inserted
-- the row on first sign-in), but layer 1 (GRANTS) never granted INSERT on
-- public.profiles to `authenticated`, and no INSERT policy was ever created.
-- Every client insert failed with 42501 before RLS was consulted. The client
-- swallowed the error in a bare catch, so the signup looked successful. This
-- is the same omission as 20260812140944 (missing UPDATE grant), for INSERT.
--
-- WHY A TRIGGER AND NOT AN INSERT POLICY: an INSERT policy's WITH CHECK can
-- only pin `id` to auth.uid(). It cannot stop the client choosing its own
-- country_code on the INSERT, and `profiles_protect_fields` is BEFORE UPDATE
-- so it would not fire. Granting client INSERT would therefore hand a patched
-- APK the pricing rail (Rs109 India vs $1.10 international) — exactly what
-- layer 3 exists to prevent. Creating the row server-side keeps profiles
-- write-closed to clients: `authenticated` still has NO insert grant and NO
-- insert policy after this migration. It also cannot be bypassed, and it runs
-- even if the app is killed between OTP verification and the next frame.
-- ════════════════════════════════════════════════════════════════════════

-- ── The profile factory ────────────────────────────────────────────────
-- SECURITY DEFINER so it runs as the function owner and is unaffected by the
-- (deliberately absent) client grants on public.profiles. search_path is
-- pinned for the same reason as the other definer functions in Phase 1.
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

  return new;
end $$;

-- AFTER INSERT, not BEFORE: profiles.id references auth.users(id), so the auth
-- row has to exist before the profile can point at it.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── Backfill the users stranded by the bug ─────────────────────────────
-- Idempotent: only inserts where no profile exists. country_code takes the
-- table default because no signup to date carried country metadata.
insert into public.profiles (id, email, phone, country_code, signup_platform)
select
  u.id,
  nullif(u.email, ''),
  nullif(u.phone, ''),
  coalesce(
    case when upper(trim(u.raw_user_meta_data->>'country_code')) ~ '^[A-Z]{2}$'
         then upper(trim(u.raw_user_meta_data->>'country_code')) end,
    'IN'),
  'android'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

-- ════════════════════════════════════════════════════════════════════════
-- UNCHANGED, deliberately: no insert/update/delete grant or policy is added
-- for anon or authenticated on public.profiles. The client reads its own row
-- (profiles_select_own) and may update the non-privileged fields
-- (profiles_update_own + profiles_protect_fields). It still cannot create a
-- profile, and still cannot set country_code by any path.
-- ════════════════════════════════════════════════════════════════════════
