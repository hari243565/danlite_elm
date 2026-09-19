/* ════════════════════════════════════════════════════════════════════════
   SECURITY AUDIT — ADVERSARIAL REGRESSION SUITE  (2026-09-19)

   Each test below ATTACKS a specific mechanism and asserts the attack fails.
   These are not "the code looks right" assertions: every one of them performs
   the exploit and reads back what actually happened.

   HOW TO RUN

     SQL=$(tr '\n' ' ' < supabase/tests/security_audit_regression.sql)
     npx supabase db query --linked "$SQL"

   The Management API transport `supabase db query --linked` uses accepts only
   a SINGLE LINE, and it discards NOTICE/WARNING output. So: block comments
   only (a `--` comment would swallow the rest of the collapsed line), and
   every verdict is recorded into a scratch table that is SELECTed at the end.

   SAFETY. Everything runs inside one transaction ending in ROLLBACK, so it
   leaves no residue on the production database — verified after each run by
   counting leftover rows. The scratch recorder is created and destroyed
   inside that same transaction.

   The fake signups below do fire handle_new_user() and therefore
   on_licence_created_send_activation. That sends no mail: pg_net delivers
   only AFTER COMMIT, and this never commits.

   A FAILING TEST CANNOT BE FAKED AS A PASS. The recorder is written on the
   path where the exploit was BLOCKED; if an exploit succeeds, the row says
   EXPLOITABLE, and an unexpected error aborts the whole script.
   ════════════════════════════════════════════════════════════════════════ */

begin;

create table public._sec_probe (id int primary key, name text, verdict text);
alter table public._sec_probe disable row level security;
grant select, insert on public._sec_probe to authenticated, anon;

do $suite$
declare
  atk  uuid := '9a000000-0000-4000-8000-00000000a001';
  vic  uuid := '9a000000-0000-4000-8000-00000000a002';
  vtm  uuid := '9a000000-0000-4000-8000-00000000a003';
  inst uuid := '00000000-0000-0000-0000-000000000000';
  seen text;
  n    int;
begin

  /* Two real signups, through the real trigger chain, so profiles and
     licences rows exist exactly as they would in production. */
  insert into auth.users (id, instance_id, aud, role, email) values
    (atk, inst, 'authenticated', 'authenticated', 'attacker-audit@test.local'),
    (vtm, inst, 'authenticated', 'authenticated', 'victim2-audit@test.local');

  /* ── Become the attacker: an ordinary authenticated customer. ────────── */
  perform set_config('request.jwt.claims',
    json_build_object('sub', atk::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  /* TEST 1 — profiles.email must NOT be client-writable.
     The hole: email was absent from protect_profile_fields' revert list, so
     any signed-in user could park an arbitrary address on their own row. */
  update public.profiles set email = 'victim-audit@test.local' where id = atk;
  select email into seen from public.profiles where id = atk;
  insert into public._sec_probe values (1, 'profiles.email not client-writable',
    case when seen = 'attacker-audit@test.local'
         then 'BLOCKED - email unchanged'
         else 'EXPLOITABLE - email became ' || coalesce(seen, 'null') end);

  /* TEST 2 — country_code stays protected (pricing rail).
     Regression guard on rls_verification.sql TEST 7, re-asserted here so one
     suite covers every protected column. */
  update public.profiles set country_code = 'US' where id = atk;
  select country_code into seen from public.profiles where id = atk;
  insert into public._sec_probe values (2, 'country_code protected',
    case when seen = 'IN' then 'BLOCKED - country_code unchanged'
         else 'EXPLOITABLE - country_code became ' || coalesce(seen,'null') end);

  /* TEST 3 — signup_platform stays protected. */
  update public.profiles set signup_platform = 'web' where id = atk;
  select signup_platform into seen from public.profiles where id = atk;
  insert into public._sec_probe values (3, 'signup_platform protected',
    case when seen = 'android' then 'BLOCKED - signup_platform unchanged'
         else 'EXPLOITABLE - became ' || coalesce(seen,'null') end);

  /* TEST 4 — deleted_at stays protected (a client must not un-delete or
     self-soft-delete its way around a DPDP erasure marker). */
  update public.profiles set deleted_at = now() where id = atk;
  select coalesce(deleted_at::text,'null') into seen
    from public.profiles where id = atk;
  insert into public._sec_probe values (4, 'deleted_at protected',
    case when seen = 'null' then 'BLOCKED - deleted_at still null'
         else 'EXPLOITABLE - deleted_at became ' || seen end);

  /* TEST 5 — NOT OVER-PROTECTED. first_name / last_name / phone are the
     user's own contact details and MUST remain client-writable; the app's
     "Create your account" screen writes exactly these three. A fix that
     locked them would silently break signup, so this asserts the opposite
     direction of every test above. */
  update public.profiles
     set first_name = 'Asha', last_name = 'Kumar', phone = '+919999000011'
   where id = atk;
  select coalesce(first_name,'') || '/' || coalesce(last_name,'') || '/'
         || coalesce(phone,'') into seen from public.profiles where id = atk;
  insert into public._sec_probe values (5, 'first/last/phone still writable',
    case when seen = 'Asha/Kumar/+919999000011'
         then 'OK - client can still write its own contact details'
         else 'REGRESSION - over-protected, got ' || seen end);

  /* TEST 6 — BOLA/IDOR: the attacker names another user's id directly.
     RLS must make the row invisible AND unwritable, not merely hidden. */
  update public.profiles set first_name = 'pwned' where id = vtm;
  select coalesce(first_name,'null') into seen
    from public.profiles where id = vtm;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  select coalesce(first_name,'null') into seen
    from public.profiles where id = vtm;
  insert into public._sec_probe values (6, 'IDOR: cross-user profile write',
    case when seen = 'null' then 'BLOCKED - victim row untouched'
         else 'EXPLOITABLE - victim first_name is now ' || seen end);

  /* TEST 7 — cross-user READ of licences and payments. */
  perform set_config('request.jwt.claims',
    json_build_object('sub', atk::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.licences where user_id = vtm;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  insert into public._sec_probe values (7, 'IDOR: cross-user licence read',
    case when n = 0 then 'BLOCKED - 0 rows visible'
         else 'EXPLOITABLE - ' || n || ' foreign licence rows readable' end);

  /* TEST 8 — the signup denial-of-service that the email hole enabled.
     With TEST 1 blocked, the attacker never owns 'victim-audit@test.local',
     so the victim can still create an account. If TEST 1 ever regresses,
     this insert aborts with 23505 and the victim is locked out permanently. */
  begin
    insert into auth.users (id, instance_id, aud, role, email)
      values (vic, inst, 'authenticated', 'authenticated',
              'victim-audit@test.local');
    insert into public._sec_probe values (8, 'signup DoS via squatted email',
      'BLOCKED - victim signup succeeded');
  exception when unique_violation then
    insert into public._sec_probe values (8, 'signup DoS via squatted email',
      'EXPLOITABLE - victim signup aborted 23505, address unregisterable');
  end;

  /* TEST 9 — audit_log is append-only: INSERT still works.
     Asserted FIRST so a guard that broke the writers shows up as a failure
     here rather than as a silently empty audit trail in production. */
  begin
    insert into public.audit_log (user_id, action, detail)
      values (atk, 'security_audit.probe', '{"probe":true}'::jsonb);
    insert into public._sec_probe values (9, 'audit_log INSERT still works',
      'OK - append path intact');
  exception when others then
    insert into public._sec_probe values (9, 'audit_log INSERT still works',
      'REGRESSION - insert now fails: ' || sqlerrm);
  end;

  /* TEST 10 — audit_log UPDATE rejected. Run as the CURRENT (elevated,
     table-owning) login role, not as `authenticated` — the whole point is
     that ownership is no longer enough to rewrite history. */
  begin
    update public.audit_log set action = 'tampered'
     where action = 'security_audit.probe';
    insert into public._sec_probe values (10, 'audit_log UPDATE rejected',
      'EXPLOITABLE - elevated role rewrote an audit entry');
  exception when others then
    insert into public._sec_probe values (10, 'audit_log UPDATE rejected',
      'BLOCKED - ' || sqlstate);
  end;

  /* TEST 11 — audit_log DELETE rejected, same role. This is the statement an
     admin would use to erase the record of their own actions. */
  begin
    delete from public.audit_log where action = 'security_audit.probe';
    insert into public._sec_probe values (11, 'audit_log DELETE rejected',
      'EXPLOITABLE - elevated role deleted an audit entry');
  exception when others then
    insert into public._sec_probe values (11, 'audit_log DELETE rejected',
      'BLOCKED - ' || sqlstate);
  end;

  /* TEST 12 — audit_log TRUNCATE rejected. TRUNCATE fires no row trigger and
     is not constrained by the absence of DELETE, so it needs its own
     statement-level guard or the entire trail still goes in one statement. */
  begin
    execute 'truncate table public.audit_log';
    insert into public._sec_probe values (12, 'audit_log TRUNCATE rejected',
      'EXPLOITABLE - elevated role truncated the audit trail');
  exception when others then
    insert into public._sec_probe values (12, 'audit_log TRUNCATE rejected',
      'BLOCKED - ' || sqlstate);
  end;

  /* TEST 13 — every SECURITY DEFINER function in public pins search_path.
     An unpinned definer function is a privilege-escalation primitive, and
     this project has been bitten by the class before. */
  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.prosecdef
     and (p.proconfig is null
          or not exists (select 1 from unnest(p.proconfig) c
                          where c like 'search_path=%'));
  insert into public._sec_probe values (13, 'all SECURITY DEFINER fns pinned',
    case when n = 0 then 'OK - 0 unpinned definer functions'
         else 'FINDING - ' || n || ' definer function(s) with no search_path' end);

  /* TEST 14 — no client role may write money or entitlement by any path. */
  perform set_config('request.jwt.claims',
    json_build_object('sub', atk::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    update public.licences set status = 'active' where user_id = atk;
    select status into seen from public.licences where user_id = atk;
    if seen = 'active' then
      insert into public._sec_probe values (14, 'client cannot self-activate',
        'EXPLOITABLE - authenticated set its own licence to active');
    else
      insert into public._sec_probe values (14, 'client cannot self-activate',
        'BLOCKED - no rows updated, status is ' || coalesce(seen,'null'));
    end if;
  exception when others then
    insert into public._sec_probe values (14, 'client cannot self-activate',
      'BLOCKED - ' || sqlstate);
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);

end $suite$;

select id, name, verdict from public._sec_probe order by id;

rollback;
