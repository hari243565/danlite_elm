-- ════════════════════════════════════════════════════════════════════════
-- PHASE 7 — single active session enforcement.
--
-- CONCURRENCY: claim_session takes a row lock on the licence
-- (SELECT ... FOR UPDATE) before reading or writing active_session_id, so
-- two simultaneous logins are serialized by Postgres itself. The loser does
-- not fail — it simply becomes the new active session, and the earlier one
-- is marked revoked. Last-login-wins is deliberate: it is the behaviour a
-- real user expects when they move to a new phone.
--
-- ── LOCK ORDER, and why it is written this way ──────────────────────────
--
-- Every function below that touches more than one row takes its locks in
-- exactly this order:
--
--        licences  →  devices  →  sessions
--
-- This is not incidental. Two deadlock cycles are possible if it is not
-- held to, and both are silent until they happen in production:
--
--   (a) The device upsert is deliberately INSIDE the licence lock, not
--       before it. If a claim locked `devices` first and then `licences`,
--       while any other statement locked `licences` first and then
--       `devices`, the two would deadlock. Holding the licence lock across
--       the upsert also makes the whole claim one critical section per
--       user, which removes unique-index contention between two logins
--       racing on the SAME fingerprint — they are already serialized.
--
--   (b) sign_out_all_devices locks the licence row FIRST, before it
--       updates `sessions`, even though it has no logical need to read the
--       licence at that point. Without it: a claim holding the licence lock
--       and reaching for a session row, against a sign-out holding that
--       session row and reaching for the licence, is a textbook cycle.
--       Postgres would detect it and abort one caller with 40P01 — a login
--       that fails for no reason the user could ever understand.
-- ════════════════════════════════════════════════════════════════════════

create or replace function public.claim_session(
  p_user_id      uuid,
  p_fingerprint  text,
  p_platform     text default 'android',
  p_model        text default null
)
returns table (
  session_id      uuid,
  device_id       uuid,
  superseded      boolean,
  prior_device_id uuid
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device      uuid;
  v_prior_sess  uuid;
  v_prior_dev   uuid;
  v_new_sess    uuid;
begin
  -- 1. Serialize on the licence row FIRST. Everything below is inside this
  --    lock, so one user's concurrent logins are fully ordered. See the lock
  --    order note at the top of this file.
  select l.active_session_id, l.active_device_id
    into v_prior_sess, v_prior_dev
    from public.licences l
   where l.user_id = p_user_id
   for update;

  if not found then
    raise exception 'no licence row for user %', p_user_id
      using errcode = 'no_data_found';
  end if;

  -- 2. Upsert the device. Re-login on the SAME device must not look like a
  --    supersession — that is the single most common false positive here.
  insert into public.devices (user_id, fingerprint, platform, model)
  values (p_user_id, p_fingerprint, p_platform, p_model)
  on conflict (user_id, fingerprint)
    do update set last_seen_at = now(),
                  model = coalesce(excluded.model, public.devices.model)
  returning id into v_device;

  -- 3. Issue the new session.
  insert into public.sessions (user_id, device_id)
  values (p_user_id, v_device)
  returning id into v_new_sess;

  -- 4. Retire the prior session. The reason string is the only thing that
  --    differs between the two branches; both must clear the old session, or
  --    a stale row would stay unrevoked forever and make "exactly one active
  --    session" untrue in the audit trail.
  if v_prior_sess is not null then
    update public.sessions s
       set revoked_at = now(),
           revoke_reason = case
             when v_prior_dev is distinct from v_device then 'superseded'
             else 'reissued_same_device'
           end
     where s.id = v_prior_sess and s.revoked_at is null;
  end if;

  update public.licences l
     set active_session_id = v_new_sess,
         active_device_id  = v_device
   where l.user_id = p_user_id;

  return query select
    v_new_sess,
    v_device,
    (v_prior_sess is not null and v_prior_dev is distinct from v_device),
    v_prior_dev;
end $$;

revoke all on function public.claim_session(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.claim_session(uuid, text, text, text)
  to service_role;

-- ────────────────────────────────────────────────────────────────────────
-- Sign out every device for a user. The escape hatch for a lost or replaced
-- phone: clears the active session so the next login on any device wins
-- cleanly.
-- ────────────────────────────────────────────────────────────────────────
create or replace function public.sign_out_all_devices(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
begin
  -- Take the licence lock BEFORE touching sessions, to match claim_session's
  -- order. Purely a deadlock-avoidance measure — see the lock order note at
  -- the top of this file.
  perform 1 from public.licences l where l.user_id = p_user_id for update;

  update public.sessions s
     set revoked_at = now(), revoke_reason = 'user_signed_out_all'
   where s.user_id = p_user_id and s.revoked_at is null;
  get diagnostics v_count = row_count;

  update public.licences l
     set active_session_id = null, active_device_id = null
   where l.user_id = p_user_id;

  return v_count;
end $$;

revoke all on function public.sign_out_all_devices(uuid)
  from public, anon, authenticated;
grant execute on function public.sign_out_all_devices(uuid) to service_role;

-- ────────────────────────────────────────────────────────────────────────
-- Heartbeat, called on each entitlement refresh so an idle-vs-active device
-- is distinguishable in support situations. Single-row, single-lock: it can
-- never participate in a deadlock cycle.
-- ────────────────────────────────────────────────────────────────────────
create or replace function public.touch_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.sessions s set last_seen_at = now()
   where s.id = p_session_id and s.revoked_at is null;
end $$;

revoke all on function public.touch_session(uuid) from public, anon, authenticated;
grant execute on function public.touch_session(uuid) to service_role;

-- ────────────────────────────────────────────────────────────────────────
-- GRANTS
--
-- Verified against the live catalog before writing this (Phase 7 Step 1).
-- service_role held only REFERENCES, TRIGGER, TRUNCATE on BOTH devices and
-- sessions — no SELECT, no INSERT, no UPDATE. The same omission class found
-- in Phase 2 (profiles) and Phase 3 (licences).
--
-- SELECT only, deliberately, and worth being precise about why.
--
-- The three functions above are SECURITY DEFINER owned by `postgres`, which
-- holds BYPASSRLS, so their table writes need no service_role grant at all.
-- The portal reads the active device through the USER's own RLS-scoped
-- client (authenticated already holds SELECT plus own-row policies on both
-- tables), so it needs none either. SELECT is granted here as the floor for
-- server-side and support reads, and because a service role that cannot read
-- the tables it administers is a trap for the next phase.
--
-- INSERT/UPDATE are deliberately NOT granted. No caller needs them, and
-- granting them would widen what a leaked service-role key can do while
-- defeating the point of routing every write through a locked, auditable
-- function. Phase 8 must add write grants as its own reviewable decision if
-- it ever genuinely needs them.
-- ────────────────────────────────────────────────────────────────────────
grant select on public.devices  to service_role;
grant select on public.sessions to service_role;
