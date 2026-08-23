-- ════════════════════════════════════════════════════════════════════════
-- ADMIN PHASE 2 — the first admin actions that CHANGE something.
--
-- Phase 1 was read-only on purpose. This migration is where that stops, so
-- everything here is written around one question: could an action be taken
-- accidentally, or with no accountable record of who did it and why?
--
-- Three things answer that:
--   1. audit_log learns WHO ACTED, separately from who an action is ABOUT.
--   2. An admin-granted licence is labelled as such and can never be mistaken
--      for a real payment.
--   3. A reason is required BY THE DATABASE, not by the browser.
--
-- Nothing here is destructive to existing data: two nullable columns, one
-- widened CHECK, two new functions. No existing row is read or rewritten.
-- ════════════════════════════════════════════════════════════════════════


-- ── 1. WHO ACTED ────────────────────────────────────────────────────────
-- audit_log.user_id already means "the user this entry is ABOUT". Every row
-- written so far is system-generated (a webhook, the entitlement function),
-- so there was never an actor to record and the column did not need to
-- exist. An admin action changes that: "licence revoked" is a fundamentally
-- different fact from "licence revoked BY hs0238766@gmail.com", and only the
-- second one is accountable.
--
-- BOTH columns, not one:
--   • actor_user_id is the foreign key — referential integrity, and the thing
--     to join on if we ever want "everything this admin has ever done".
--   • actor_email is a flat, denormalised copy of the address AT THE TIME OF
--     THE ACTION. It is the load-bearing one. admin_users is an allowlist
--     that people get removed from; if the only record of who acted were a
--     key into that table, then removing someone would quietly turn every
--     action they ever took into "unknown admin". An audit trail that can be
--     degraded by ordinary administration is not an audit trail.
--
-- Both are nullable, because every existing row and every future
-- system-generated row has no human actor. Null actor = the system did it.
alter table public.audit_log
  add column actor_user_id uuid references auth.users(id) on delete set null,
  add column actor_email   text;

-- ON DELETE SET NULL, deliberately, and this is the reason the CHECK below
-- is one-directional. If an admin's auth user is ever deleted, the FK goes
-- null but actor_email survives, and the audit row still says who did it.
-- The alternative (NO ACTION) would make the audit trail block account
-- deletion, and ON DELETE CASCADE would let deleting a user erase the record
-- of what they did — the exact failure this column exists to prevent.
--
-- So: an actor id ALWAYS implies a readable email, but an email may outlive
-- its id. Never the other way round — an anonymous actor is not permitted.
alter table public.audit_log
  add constraint audit_log_actor_email_present
  check (actor_user_id is null or actor_email is not null);

comment on column public.audit_log.actor_user_id is
  'The admin who performed this action. Null = system-generated (webhook, entitlement). FK nulls on user delete; actor_email survives.';
comment on column public.audit_log.actor_email is
  'The acting admin''s email AS IT WAS at the time of the action. Deliberately denormalised so removing someone from admin_users cannot rewrite history.';


-- ── 2. AN ADMIN GRANT IS NOT A PAYMENT ──────────────────────────────────
-- Live constraint before this migration, read from pg_constraint rather than
-- assumed:
--     CHECK (purchase_rail = ANY (ARRAY['razorpay_in'::text,
--                                       'razorpay_intl'::text]))
--
-- Both existing values are preserved exactly; 'admin_grant' is added
-- alongside. purchase_rail stays nullable (an unpurchased licence has no
-- rail), and a CHECK is not violated by NULL, so no existing row is affected.
--
-- WHY THIS MATTERS MORE THAN IT LOOKS: without a distinct value, the only way
-- to grant a licence would be to stamp it 'razorpay_in' — recording, in the
-- system of record, that money arrived through Razorpay when none did. That
-- is fabricated payment provenance. It would corrupt revenue reconciliation,
-- it would survive into any future export or accounting integration, and in a
-- live system it would be the kind of thing that is very hard to explain
-- afterwards. A support gift and a sale are different events and the schema
-- must be able to tell them apart.
alter table public.licences
  drop constraint licences_purchase_rail_check;

alter table public.licences
  add constraint licences_purchase_rail_check
  check (purchase_rail = any (array['razorpay_in'::text,
                                    'razorpay_intl'::text,
                                    'admin_grant'::text]));


-- ── 3. GRANT ────────────────────────────────────────────────────────────
-- SECURITY DEFINER with search_path pinned, granted to service_role only,
-- called from an Edge Function that has ALREADY independently verified the
-- caller against admin_users. Same shape as activate_licence_from_payment
-- and revoke_licence_from_refund — this function is not a new trust model,
-- it is the existing one with an actor attached.
--
-- The reason check lives HERE, in the database, and not only in the browser.
-- A disabled submit button is a courtesy to a careful person; it is not a
-- control. Anyone holding the service key — a future script, a debugging
-- session, a mistake — reaches this function directly, and at that point the
-- database is the only thing left that can insist on accountability.
create or replace function public.admin_grant_licence(
  p_target_user_id uuid,
  p_actor_user_id  uuid,
  p_actor_email    text,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_reason      text := btrim(coalesce(p_reason, ''));
  v_actor_email text := lower(btrim(coalesce(p_actor_email, '')));
  v_licence_id  uuid;
  v_before      text;
  v_rail_before text;
begin
  -- ── Accountability preconditions. All three are refusals, not defaults.
  -- Note the ordering: identity and intent are checked BEFORE the row is
  -- located, so a malformed call cannot even learn whether a user exists.
  if v_reason = '' then
    raise exception 'admin_grant_licence: a non-empty reason is required'
      using errcode = 'check_violation';
  end if;

  if p_target_user_id is null then
    raise exception 'admin_grant_licence: p_target_user_id is required'
      using errcode = 'check_violation';
  end if;

  -- An action with no identifiable actor is exactly the thing this phase
  -- exists to make impossible, so it is refused rather than logged as null.
  if p_actor_user_id is null or v_actor_email = '' then
    raise exception 'admin_grant_licence: an identified actor (id and email) is required'
      using errcode = 'check_violation';
  end if;

  -- FOR UPDATE, matching the lock discipline in claim_session and
  -- sign_out_all_devices: the licence row is the contended one in this
  -- system and is always taken first.
  select l.id, l.status, l.purchase_rail
    into v_licence_id, v_before, v_rail_before
    from public.licences l
   where l.user_id = p_target_user_id
     for update;

  -- Every user gets a licence row from the signup trigger, so this is always
  -- an UPDATE. Verified live before this migration was written (2 users, 2
  -- licences, 0 users without one). If that invariant ever breaks, this
  -- function REFUSES rather than papering over it with an INSERT: a missing
  -- licence row means the signup trigger has failed, which is a much bigger
  -- problem than one ungranted licence and must not be silently absorbed.
  if v_licence_id is null then
    raise exception 'admin_grant_licence: no licence row for user % — signup trigger may have failed', p_target_user_id
      using errcode = 'no_data_found';
  end if;

  update public.licences
     set status        = 'active',
         purchase_rail = 'admin_grant',
         purchased_at  = now(),
         -- Cleared so the row does not read as simultaneously active and
         -- revoked. The history is not lost — it is in the audit entry below
         -- and in whichever prior entry recorded the revocation.
         revoked_at    = null,
         revoke_reason = null
   where id = v_licence_id;
  -- updated_at is left alone: the licences_updated_at BEFORE UPDATE trigger
  -- owns that column.

  insert into public.audit_log (user_id, action, detail, actor_user_id, actor_email)
  values (
    p_target_user_id,
    'admin.licence_granted',
    jsonb_build_object(
      'reason',              v_reason,
      'licence_id',          v_licence_id,
      'status_before',       v_before,
      'status_after',        'active',
      'purchase_rail_before', v_rail_before,
      'purchase_rail_after', 'admin_grant'
    ),
    p_actor_user_id,
    v_actor_email
  );

  return jsonb_build_object(
    'licence_id',    v_licence_id,
    'status_before', v_before,
    'status_after',  'active'
  );
end
$function$;


-- ── 4. REVOKE ───────────────────────────────────────────────────────────
-- Same shape, same refusals. The one thing worth reading closely is the
-- revoke_reason format.
--
-- revoke_licence_from_refund already writes into this same column, in the
-- format the webhook builds:
--     'refund.created refund_id=rfnd_XXXX amount_minor=10900'
--
-- This function deliberately writes a shape that cannot be confused with it:
--     'admin_revoke: <the admin's typed reason>'
--
-- That prefix is not decoration. revoke_reason is the column a future
-- operator reads during an incident to answer "why did this customer lose
-- access?", and "the gateway refunded them" and "a human took it away" call
-- for completely different responses. If both wrote free text in the same
-- shape, telling them apart would mean guessing.
create or replace function public.admin_revoke_licence(
  p_target_user_id uuid,
  p_actor_user_id  uuid,
  p_actor_email    text,
  p_reason         text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_reason      text := btrim(coalesce(p_reason, ''));
  v_actor_email text := lower(btrim(coalesce(p_actor_email, '')));
  v_licence_id  uuid;
  v_before      text;
  v_stored      text;
begin
  if v_reason = '' then
    raise exception 'admin_revoke_licence: a non-empty reason is required'
      using errcode = 'check_violation';
  end if;

  if p_target_user_id is null then
    raise exception 'admin_revoke_licence: p_target_user_id is required'
      using errcode = 'check_violation';
  end if;

  if p_actor_user_id is null or v_actor_email = '' then
    raise exception 'admin_revoke_licence: an identified actor (id and email) is required'
      using errcode = 'check_violation';
  end if;

  select l.id, l.status
    into v_licence_id, v_before
    from public.licences l
   where l.user_id = p_target_user_id
     for update;

  if v_licence_id is null then
    raise exception 'admin_revoke_licence: no licence row for user % — signup trigger may have failed', p_target_user_id
      using errcode = 'no_data_found';
  end if;

  v_stored := 'admin_revoke: ' || v_reason;

  update public.licences
     set status        = 'revoked',
         revoked_at    = now(),
         revoke_reason = v_stored
   where id = v_licence_id;
  -- purchase_rail is deliberately NOT cleared. How this licence was
  -- originally obtained is a historical fact and stays true after revocation;
  -- a revoked razorpay_in licence and a revoked admin_grant one are different
  -- situations and the row should keep saying which it was.
  --
  -- active_session_id / active_device_id are also NOT cleared here. Revoking
  -- entitlement and terminating sessions are two separate admin actions with
  -- two separate audit entries, and quietly doing the second as a side effect
  -- of the first would mean an action taken with no record of its own. Force
  -- Sign-out exists for that, one button away.

  insert into public.audit_log (user_id, action, detail, actor_user_id, actor_email)
  values (
    p_target_user_id,
    'admin.licence_revoked',
    jsonb_build_object(
      'reason',        v_reason,
      'revoke_reason', v_stored,
      'licence_id',    v_licence_id,
      'status_before', v_before,
      'status_after',  'revoked'
    ),
    p_actor_user_id,
    v_actor_email
  );

  return jsonb_build_object(
    'licence_id',    v_licence_id,
    'status_before', v_before,
    'status_after',  'revoked'
  );
end
$function$;


-- ── 5. WHO MAY CALL THESE ───────────────────────────────────────────────
-- Postgres grants EXECUTE on new functions to PUBLIC by default. For a
-- SECURITY DEFINER function that hands out and takes away paid entitlement,
-- that default is the whole attack. It is revoked explicitly rather than
-- assumed closed, and anon/authenticated are named individually as well:
-- revoking from PUBLIC does not remove a grant held directly by a role, and
-- these two are the roles a browser can actually reach PostgREST as.
revoke all on function public.admin_grant_licence(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.admin_revoke_licence(uuid, uuid, text, text) from public, anon, authenticated;

grant execute on function public.admin_grant_licence(uuid, uuid, text, text) to service_role;
grant execute on function public.admin_revoke_licence(uuid, uuid, text, text) to service_role;
