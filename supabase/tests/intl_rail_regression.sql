/* ════════════════════════════════════════════════════════════════════════
   INTERNATIONAL RAIL — ADVERSARIAL REGRESSION SUITE  (2026-09-22)

   Companion to security_audit_regression.sql, in the same style and with the
   same rules. Each test ATTACKS a specific mechanism introduced by
   20260922120000_intl_order_rate_limit_and_avs.sql and asserts the attack
   fails, by performing it and reading back what actually happened.

   HOW TO RUN

   Both migrations are applied to production as of 2026-09-22, so the suite
   now runs against the real schema and prepends nothing:

     {
       echo "begin;"
       cat supabase/tests/intl_rail_regression.sql
       echo "rollback;"
     } > /tmp/run.sql
     npx supabase db query --linked -f /tmp/run.sql

   BEFORE THEY WERE APPLIED, the two migrations were cat'd in between the
   `begin;` and this file, in timestamp order:

       20260922120000_intl_order_rate_limit_and_avs.sql
       20260922163000_revoke_truncate_intl_ledger.sql

   That form tested the DDL AS WRITTEN — its grants and CHECK constraints,
   not a hand-made approximation — and is how TESTS 1-17 were first run.
   DO NOT use it now: `create table public.intl_order_attempts` fails with
   42P07 once the table exists. Prepend again only against a database where
   these migrations have not landed.

   EITHER WAY NOTHING PERSISTS — see SAFETY below.

   TEST 18 IS THE WORKED EXAMPLE OF WHY THIS SUITE EARNS ITS KEEP. Run
   against production after 20260922120000 and before 20260922163000, it
   reported EXPLOITABLE; after 20260922163000 it reported BLOCKED. A test
   that has never been observed to fail is a test nobody has checked.

   USE `-f`, NOT AN ARGV STRING. Passing this as a quoted argument hits
   Windows' command-line length limit ("The command line is too long") and
   forces a flattening pass that would swallow every `--` comment. The `-f`
   flag takes this file as written.

   The Management API transport discards NOTICE/WARNING output, so every
   verdict is recorded into a scratch table that is SELECTed at the end
   rather than raised as a notice.

   SAFETY. Everything runs inside one transaction ending in ROLLBACK. Nothing
   here commits, so nothing here persists.

   A FAILING TEST CANNOT BE FAKED AS A PASS. Each recorder row is written on
   the path where the attack was BLOCKED. If an attack succeeds the row says
   EXPLOITABLE, and an unexpected error aborts the whole script.
   ════════════════════════════════════════════════════════════════════════ */

create table public._intl_probe (id int primary key, name text, verdict text);
alter table public._intl_probe disable row level security;
/* service_role is in this list because TESTS 3-5 run `set local role
   service_role` and record their verdict from inside it. A fresh table grants
   service_role nothing on this project — the same 42501 that has cost four
   corrective migrations — and the recorder is not exempt from it. */
grant select, insert on public._intl_probe to authenticated, anon, service_role;

do $suite$
declare
  cust uuid := '9b000000-0000-4000-8000-00000000b001';
  atk  uuid := '9b000000-0000-4000-8000-00000000b002';
  inst uuid := '00000000-0000-0000-0000-000000000000';
  n    int;
  bc   text;
  bp   text;
  rs   jsonb;
begin

  insert into auth.users (id, instance_id, aud, role, email) values
    (cust, inst, 'authenticated', 'authenticated', 'intl-cust@test.local'),
    (atk,  inst, 'authenticated', 'authenticated', 'intl-atk@test.local');

  /* The international customer. country_code selects the price, so this is
     the field the whole rail hangs off. Set as the table owner, which is how
     it would be set in reality (signup metadata / admin), never by the
     client. */
  update public.profiles set country_code = 'US' where id = cust;
  update public.profiles set country_code = 'IN' where id = atk;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 1 — the rate-limit ledger must be invisible to customers.

     THE ATTACK: a signed-in customer reads public.intl_order_attempts to
     measure exactly how much budget they have left before the limiter bites,
     then paces a card-testing run to stay just under it. A limiter whose
     counter is readable by the attacker is a limiter with a public dashboard.
     ══════════════════════════════════════════════════════════════════════ */
  perform set_config('request.jwt.claims',
    json_build_object('sub', atk::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  begin
    select count(*) into n from public.intl_order_attempts;
    insert into public._intl_probe values
      (1, 'ledger readable by authenticated', 'EXPLOITABLE');
  exception when insufficient_privilege then
    insert into public._intl_probe values
      (1, 'ledger readable by authenticated', 'BLOCKED');
  end;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 2 — a customer must not be able to pad someone else's ledger.

     THE ATTACK: insert rows against a victim's user_id (or against a shared
     office IP) to exhaust their budget and lock them out of buying. A
     rate limiter that anyone can write to is a denial-of-service primitive.
     ══════════════════════════════════════════════════════════════════════ */
  begin
    insert into public.intl_order_attempts (user_id, ip) values (cust, '8.8.8.8');
    insert into public._intl_probe values
      (2, 'ledger writable by authenticated', 'EXPLOITABLE');
  exception when insufficient_privilege then
    insert into public._intl_probe values
      (2, 'ledger writable by authenticated', 'BLOCKED');
  end;

  set local role postgres;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 3 — the ledger is APPEND-ONLY, even for service_role.

     THE ATTACK: a compromised Edge Function (or a future bug in one) deletes
     its own rate-limit history to escape the window and resume the run. The
     defence is that service_role was granted only SELECT and INSERT, so the
     verbs required to do it were never handed out.
     ══════════════════════════════════════════════════════════════════════ */
  insert into public.intl_order_attempts (user_id, ip, outcome)
    values (cust, '203.0.113.9', 'allowed');

  set local role service_role;

  begin
    delete from public.intl_order_attempts where user_id = cust;
    insert into public._intl_probe values
      (3, 'service_role can DELETE its rate-limit history', 'EXPLOITABLE');
  exception when insufficient_privilege then
    insert into public._intl_probe values
      (3, 'service_role can DELETE its rate-limit history', 'BLOCKED');
  end;

  begin
    update public.intl_order_attempts set created_at = now() - interval '2 hours'
      where user_id = cust;
    insert into public._intl_probe values
      (4, 'service_role can back-date its rate-limit history', 'EXPLOITABLE');
  exception when insufficient_privilege then
    insert into public._intl_probe values
      (4, 'service_role can back-date its rate-limit history', 'BLOCKED');
  end;

  /* service_role DOES need select+insert, or the limiter cannot run at all.
     Asserted positively so an over-zealous future lockdown is caught here
     rather than as a 42501 in production on the first international sale. */
  begin
    select count(*) into n from public.intl_order_attempts;
    insert into public.intl_order_attempts (user_id, ip, outcome)
      values (cust, '203.0.113.9', 'rate_limited');
    insert into public._intl_probe values
      (5, 'service_role retains the select+insert the limiter needs', 'OK');
  exception when insufficient_privilege then
    insert into public._intl_probe values
      (5, 'service_role retains the select+insert the limiter needs', 'BROKEN');
  end;

  set local role postgres;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 6 — a REFUSED attempt still extends the window.

     Not an attack on the schema but on the design. If rejections were not
     logged, every refusal would age out of the window and the limit would be
     unreachable: an attacker could hammer forever. create-order inserts
     unconditionally; this asserts both outcomes are countable.
     ══════════════════════════════════════════════════════════════════════ */
  select count(*) into n from public.intl_order_attempts
    where user_id = cust and created_at >= now() - interval '5 minutes';
  if n = 2 then
    insert into public._intl_probe values
      (6, 'refused attempts are counted in the window', 'OK');
  else
    insert into public._intl_probe values
      (6, 'refused attempts are counted in the window',
       'BROKEN: expected 2 got ' || n);
  end if;

  /* And the window arithmetic itself: a row outside the burst window must
     not be counted by the burst query. */
  insert into public.intl_order_attempts (user_id, ip, created_at)
    values (cust, '203.0.113.9', now() - interval '31 minutes');

  select count(*) into n from public.intl_order_attempts
    where user_id = cust and created_at >= now() - interval '5 minutes';
  if n = 2 then
    insert into public._intl_probe values
      (7, 'an old attempt falls out of the burst window', 'OK');
  else
    insert into public._intl_probe values
      (7, 'an old attempt falls out of the burst window',
       'BROKEN: expected 2 got ' || n);
  end if;

  select count(*) into n from public.intl_order_attempts
    where user_id = cust and created_at >= now() - interval '1 hour';
  if n = 3 then
    insert into public._intl_probe values
      (8, 'the same attempt is still inside the hour window', 'OK');
  else
    insert into public._intl_probe values
      (8, 'the same attempt is still inside the hour window',
       'BROKEN: expected 3 got ' || n);
  end if;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 9 — THE DOMESTIC ORDER ROW IS UNCHANGED.

     The hard constraint on this whole task. create-order's domestic branch
     names exactly five columns, as it always has. This inserts that exact
     row and asserts the three new columns take their table defaults — i.e.
     a domestic order written after this migration is indistinguishable from
     one written before it.
     ══════════════════════════════════════════════════════════════════════ */
  insert into public.orders
    (user_id, gateway_order_id, amount_minor, currency, status)
    values (atk, 'order_DOMESTIC_probe', 12900, 'INR', 'created');

  select billing_country, billing_postal_code, risk_signals
    into bc, bp, rs
    from public.orders where gateway_order_id = 'order_DOMESTIC_probe';

  if bc is null and bp is null and rs = '{}'::jsonb then
    insert into public._intl_probe values
      (9, 'a domestic order row is unchanged by this migration', 'OK');
  else
    insert into public._intl_probe values
      (9, 'a domestic order row is unchanged by this migration',
       'CHANGED: ' || coalesce(bc,'<null>') || '/' ||
       coalesce(bp,'<null>') || '/' || rs::text);
  end if;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 10 — the international order row records what it should.
     ══════════════════════════════════════════════════════════════════════ */
  insert into public.orders
    (user_id, gateway_order_id, amount_minor, currency, status,
     billing_country, billing_postal_code, risk_signals)
    values (cust, 'order_INTL_probe', 129, 'USD', 'created',
            'US', '94107',
            '{"rail":"INTL","tax_code":"zero_rated_export"}'::jsonb);

  select billing_country, risk_signals->>'tax_code'
    into bc, bp
    from public.orders where gateway_order_id = 'order_INTL_probe';

  if bc = 'US' and bp = 'zero_rated_export' then
    insert into public._intl_probe values
      (10, 'an international order records rail, AVS country and tax code', 'OK');
  else
    insert into public._intl_probe values
      (10, 'an international order records rail, AVS country and tax code',
       'BROKEN: ' || coalesce(bc,'<null>') || '/' || coalesce(bp,'<null>'));
  end if;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 11 — billing_country is CHECK-constrained at the database.

     THE ATTACK: stuff the billing-country box with junk, a very long string,
     or an injection attempt, and have it stored and later rendered onto an
     invoice or a dispute pack. The Edge Function already normalises this to
     ISO alpha-2 or NULL; the CHECK is the second line, so a future caller
     that forgets to normalise cannot write rubbish.
     ══════════════════════════════════════════════════════════════════════ */
  begin
    insert into public.orders
      (user_id, gateway_order_id, amount_minor, currency, status, billing_country)
      values (cust, 'order_BADCOUNTRY', 129, 'USD', 'created', 'UNITED STATES');
    insert into public._intl_probe values
      (11, 'billing_country accepts free text', 'EXPLOITABLE');
  exception when check_violation then
    insert into public._intl_probe values
      (11, 'billing_country accepts free text', 'BLOCKED');
  end;

  begin
    insert into public.orders
      (user_id, gateway_order_id, amount_minor, currency, status, billing_postal_code)
      values (cust, 'order_LONGPOSTAL', 129, 'USD', 'created', repeat('9', 64));
    insert into public._intl_probe values
      (12, 'billing_postal_code accepts unbounded text', 'EXPLOITABLE');
  exception when check_violation then
    insert into public._intl_probe values
      (12, 'billing_postal_code accepts unbounded text', 'BLOCKED');
  end;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 13 — the currency column is still a closed set.

     The webhook's currency check is the application-level control. This is
     the database-level one: a third currency cannot be written at all, so a
     bug that tried to open an order in, say, EUR fails loudly at the insert
     rather than quietly creating an order the webhook can never match.
     ══════════════════════════════════════════════════════════════════════ */
  begin
    insert into public.orders
      (user_id, gateway_order_id, amount_minor, currency, status)
      values (cust, 'order_EUR', 129, 'EUR', 'created');
    insert into public._intl_probe values
      (13, 'orders.currency accepts a third currency', 'EXPLOITABLE');
  exception when check_violation then
    insert into public._intl_probe values
      (13, 'orders.currency accepts a third currency', 'BLOCKED');
  end;

  /* And USD genuinely is permitted — the rail is schema-ready. Test 10
     already wrote one, so this is asserted by that row's existence. */
  select count(*) into n from public.orders
    where gateway_order_id = 'order_INTL_probe' and currency = 'USD';
  if n = 1 then
    insert into public._intl_probe values
      (14, 'orders.currency permits USD', 'OK');
  else
    insert into public._intl_probe values
      (14, 'orders.currency permits USD', 'BROKEN');
  end if;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 15 — the five prior security fixes are still in place.

     This task must not have disturbed them. Checked structurally, against
     the live catalog, rather than by reading the migration files.
     ══════════════════════════════════════════════════════════════════════ */
  select count(*) into n from pg_trigger
    where tgname in ('audit_log_no_rewrite', 'audit_log_no_truncate')
      and not tgisinternal;
  if n = 2 then
    insert into public._intl_probe values
      (15, 'audit_log append-only triggers still installed', 'OK');
  else
    insert into public._intl_probe values
      (15, 'audit_log append-only triggers still installed',
       'MISSING: found ' || n || ' of 2');
  end if;

  select count(*) into n from pg_proc
    where proname = 'protect_profile_fields'
      and prosrc like '%new.email%';
  if n = 1 then
    insert into public._intl_probe values
      (16, 'protect_profile_fields still reverts email', 'OK');
  else
    insert into public._intl_probe values
      (16, 'protect_profile_fields still reverts email', 'MISSING');
  end if;

  select count(*) into n from pg_proc
    where proname = 'revoke_licence_from_refund'
      and prosrc ilike '%for update%';
  if n = 1 then
    insert into public._intl_probe values
      (17, 'revoke_licence_from_refund still takes FOR UPDATE', 'OK');
  else
    insert into public._intl_probe values
      (17, 'revoke_licence_from_refund still takes FOR UPDATE', 'MISSING');
  end if;

  /* ══════════════════════════════════════════════════════════════════════
     TEST 18 — service_role must not be able to TRUNCATE the ledger.

     THE ATTACK: the limiter's entire design rests on the ledger being
     append-only, so that a refused attempt stays inside the window and
     cannot be waited out or erased. TESTS 3 and 4 prove DELETE and UPDATE
     are withheld. TRUNCATE is a THIRD, distinct privilege that does more
     than either — it empties the table outright — and withholding the other
     two says nothing about it.

     This is not hypothetical. On 2026-09-22, immediately after
     20260922120000 was applied to production, service_role COULD truncate
     this table: the privilege arrives through the same project-level default
     privileges that hand out TRIGGER and REFERENCES, and `grant select,
     insert` does not displace it. 20260922163000 revokes it. This test is
     what stops it coming back the next time a table is rebuilt or a default
     privilege changes.

     The realistic path is not a stolen key — it is a future cleanup job or
     test helper that truncates this table and silently removes the control.
     ══════════════════════════════════════════════════════════════════════ */
  set local role service_role;
  begin
    truncate public.intl_order_attempts;
    insert into public._intl_probe values
      (18, 'service_role can TRUNCATE the ledger', 'EXPLOITABLE');
  exception when insufficient_privilege then
    insert into public._intl_probe values
      (18, 'service_role can TRUNCATE the ledger', 'BLOCKED');
  end;
  reset role;

end
$suite$;

select id, name, verdict from public._intl_probe order by id;
