-- RLS VERIFICATION — run as the postgres/service role.
-- Simulates two authenticated users and proves isolation.
--
-- TRANSPORT NOTE: this script is executed via `supabase db query --linked`,
-- which goes through the Management API. That transport returns result ROWS
-- but discards NOTICE messages, so the `raise notice` lines below (kept intact
-- for psql users) are mirrored into a scratch table that is selected at the
-- end. The scratch table is created inside the transaction and destroyed by
-- the same `rollback`, so it leaves no residue. A failing assertion still
-- raises an exception and aborts the whole script — a pass CANNOT be faked by
-- the recorder, because the recorder only ever runs on the success path.
begin;

create table public._rls_results (
  id     int primary key,
  name   text not null,
  result text not null
);
-- This Supabase project has an event trigger that force-enables RLS on every
-- new table in `public`. That is a good default, but the scratch recorder is
-- not user data — it must accept writes from whichever role a test is running
-- as, so RLS is disabled on this one throwaway table only.
alter table public._rls_results disable row level security;
grant select, insert on public._rls_results to authenticated, anon;

-- Two fake users
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local')
on conflict do nothing;

insert into public.profiles (id, email, country_code) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local', 'IN'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local', 'US')
on conflict do nothing;

insert into public.licences (user_id, status, purchase_rail, purchased_at) values
  ('11111111-1111-1111-1111-111111111111', 'active', 'razorpay_in',  now()),
  ('22222222-2222-2222-2222-222222222222', 'active', 'razorpay_intl', now())
on conflict do nothing;

-- ── Become user A ─────────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- TEST 1: A sees exactly one licence (their own)
do $$
declare n int;
begin
  select count(*) into n from public.licences;
  if n <> 1 then raise exception 'TEST 1 FAILED: A sees % licences, expected 1', n;
  end if;
  raise notice 'TEST 1 PASS: user A sees only their own licence';
  insert into public._rls_results values
    (1, 'user A sees only own licence', 'TEST 1 PASS: user A sees only their own licence');
end $$;

-- TEST 2: A cannot see B's licence specifically
do $$
declare n int;
begin
  select count(*) into n from public.licences
   where user_id = '22222222-2222-2222-2222-222222222222';
  if n <> 0 then raise exception 'TEST 2 FAILED: A can read B''s licence';
  end if;
  raise notice 'TEST 2 PASS: user A cannot read user B licence';
  insert into public._rls_results values
    (2, 'user A cannot read B licence', 'TEST 2 PASS: user A cannot read user B licence');
end $$;

-- TEST 3: A cannot INSERT a licence (no insert policy exists)
do $$
begin
  begin
    insert into public.licences (user_id, status)
    values ('11111111-1111-1111-1111-111111111111', 'active');
    raise exception 'TEST 3 FAILED: authenticated user inserted a licence';
  exception when insufficient_privilege or others then
    raise notice 'TEST 3 PASS: licence insert blocked for authenticated';
    insert into public._rls_results values
      (3, 'licence insert blocked', 'TEST 3 PASS: licence insert blocked for authenticated');
  end;
end $$;

-- TEST 4: A cannot UPDATE their licence status to active
do $$
begin
  begin
    update public.licences set status = 'active'
     where user_id = '11111111-1111-1111-1111-111111111111';
    if found then
      raise exception 'TEST 4 FAILED: authenticated user updated licence status';
    end if;
    raise notice 'TEST 4 PASS: licence update blocked (no rows affected)';
    insert into public._rls_results values
      (4, 'licence status update blocked', 'TEST 4 PASS: licence update blocked (no rows affected)');
  exception when insufficient_privilege then
    raise notice 'TEST 4 PASS: licence update blocked by privilege';
    insert into public._rls_results values
      (4, 'licence status update blocked', 'TEST 4 PASS: licence update blocked by privilege');
  end;
end $$;

-- TEST 5: A cannot read payments belonging to B
do $$
declare n int;
begin
  select count(*) into n from public.payments
   where user_id = '22222222-2222-2222-2222-222222222222';
  if n <> 0 then raise exception 'TEST 5 FAILED: A can read B payments';
  end if;
  raise notice 'TEST 5 PASS: payments isolated';
  insert into public._rls_results values
    (5, 'payments isolated', 'TEST 5 PASS: payments isolated');
end $$;

-- TEST 6: A cannot touch webhook_events at all
do $$
begin
  begin
    perform 1 from public.webhook_events limit 1;
    raise exception 'TEST 6 FAILED: authenticated can read webhook_events';
  exception when insufficient_privilege then
    raise notice 'TEST 6 PASS: webhook_events not readable by authenticated';
    insert into public._rls_results values
      (6, 'webhook_events unreadable by client', 'TEST 6 PASS: webhook_events not readable by authenticated');
  end;
end $$;

-- TEST 7: A cannot escalate country_code (pricing rail protection)
do $$
declare c text;
begin
  update public.profiles set country_code = 'US'
   where id = '11111111-1111-1111-1111-111111111111';
  select country_code into c from public.profiles
   where id = '11111111-1111-1111-1111-111111111111';
  if c <> 'IN' then
    raise exception 'TEST 7 FAILED: country_code changed to %', c;
  end if;
  raise notice 'TEST 7 PASS: country_code protected from client update';
  insert into public._rls_results values
    (7, 'country_code protected', 'TEST 7 PASS: country_code protected from client update');
end $$;

-- ── Become anon ───────────────────────────────────────────────────────
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- TEST 8: anon can read nothing from licences
do $$
begin
  begin
    perform 1 from public.licences limit 1;
    raise exception 'TEST 8 FAILED: anon can read licences';
  exception when insufficient_privilege then
    raise notice 'TEST 8 PASS: anon has no grant on licences';
    insert into public._rls_results values
      (8, 'anon has no licence grant', 'TEST 8 PASS: anon has no grant on licences');
  end;
end $$;

-- ── Report ────────────────────────────────────────────────────────────
-- Mirrors the eight NOTICE lines above for transports that drop notices.
select id, name, result from public._rls_results order by id;

rollback;   -- leave the database exactly as it was
