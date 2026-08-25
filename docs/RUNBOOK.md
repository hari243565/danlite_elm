# Danlite ELM — Operations Runbook

Operational procedures for the live system. Each section is self-contained.

---

## Database Backups

**Status:** pipeline built and exercised end-to-end except the final decrypt,
which only the owner can perform. See *What has and has not been proven* below
before you rely on this.

### Why this exists

Supabase's free tier does **not** include point-in-time recovery, and its
automatic daily backups are not retained or restorable the way a paid plan's
are. If the project were deleted, corrupted, or lost, there would be nothing to
restore from. This pipeline closes that gap at zero recurring cost, using
GitHub Actions (free) for compute.

### How it works

Every night the workflow:

1. Installs a PostgreSQL **17** client (matching Supabase's server version).
2. Runs `pg_dump` in custom format against the **session pooler** on port 5432
   (see *Which connection string to use* below — this is not the obvious
   choice). This is **read-only** — it never writes to production.
3. Verifies the dump is a genuinely parseable archive containing real table
   data, not just a file that happens to exist.
4. Encrypts it to the owner's **age public key**.
5. Verifies the ciphertext carries a valid age header and is a plausible size.
6. Stores the encrypted file.

**The pipeline cannot decrypt its own backups.** It only ever holds the public
key. The private key lives offline, on the owner's machine, and is not present
in GitHub secrets, in CI, on any developer machine, or anywhere Claude can
reach it. This is deliberate: if the automation could read the backups, then
anyone who compromised the automation could read the entire customer database.

### Where backups live

> ⚠️ **TEMPORARY — swap to Cloudflare R2 once the client's account is ready.**
>
> The R2 bucket does not exist yet (card and domain arriving). Until then,
> backups are stored as **GitHub Actions artifacts with 90-day retention**.
>
> **What changes when R2 arrives: only the upload destination.** The dump, the
> verification, the encryption, the restore procedure, and the private key all
> stay exactly as they are. Concretely, in
> `.github/workflows/backup-database.yml`:
>
> 1. Set `BACKUP_DEST: r2`
> 2. Uncomment the four `R2_*` env lines and `RETENTION_DAYS`
> 3. Add the four `R2_*` repository secrets
> 4. Delete the `Upload the encrypted backup` step
>
> Retention then becomes the script's own 30-day prune instead of GitHub's
> 90-day artifact expiry.

**Today:** GitHub → **Actions** → **Database Backup** → pick a run → the
**Artifacts** section at the bottom. Each artifact contains:

| File | What it is |
|---|---|
| `danlite-backup-<timestamp>.dump.age` | the encrypted backup |
| `danlite-backup-<timestamp>.dump.toc.txt` | the archive's table of contents, readable without decrypting |
| `danlite-backup-<timestamp>.dump.age.sha256` | checksum, to confirm the download is intact |

The `.toc.txt` is genuinely useful: it lets you confirm a backup contains the
tables you expect **without** needing the private key.

### Schedule

Daily at **22:00 UTC = 03:30 IST**, chosen as deep off-peak for an India-facing
app. GitHub cron is always UTC and has no timezone setting.

Scheduled runs on free plans are **queued, not punctual** — they can be delayed
by minutes to hours under GitHub load. That is acceptable for a daily backup.
Do not treat the start time as exact.

> **Committing the workflow file is what activates the schedule.** Until
> `.github/workflows/backup-database.yml` is pushed to the default branch on
> GitHub, nothing runs, ever.

### Running a backup on demand

GitHub → **Actions** → **Database Backup** → **Run workflow** → optionally type
a reason → **Run workflow**. Takes a couple of minutes.

To run it from your own machine instead:

```bash
export DB_URL='postgresql://postgres.uomelinvbqabczhrzhnb:YOUR_DB_PASSWORD@aws-0-ap-south-1.pooler.supabase.com:5432/postgres'
export AGE_PUBLIC_KEY='age1u6lvuptcszy3asf7zk7agyf0jp0aavnsk6knuc23sjts3rtcwsjs28ev5j'
bash scripts/backup-database.sh
```

Requires `pg_dump`/`pg_restore` v17 and `age` locally. The encrypted file lands
in `./backup-artifact/`.

> **One-line follow-up worth doing:** add `backup-artifact/` to `.gitignore`.
> A local run drops an encrypted production backup inside the repo working
> tree. It is encrypted, so this is not a leak — but a database backup has no
> business being committable, and right now nothing stops it. The build session
> left `.gitignore` untouched because it was outside the agreed file scope.

### Which connection string to use — this bit is not obvious

Supabase offers three connection strings and **only one of them works here.**

| String | Host | Works? |
|---|---|---|
| **Session pooler** | `aws-0-ap-south-1.pooler.supabase.com:5432` | ✅ **use this** |
| Direct | `db.uomelinvbqabczhrzhnb.supabase.co:5432` | ❌ not from CI |
| Transaction pooler | `...pooler.supabase.com:6543` | ❌ never |

The **direct** connection is IPv6-only on the free tier — verified for this
project: `db.uomelinvbqabczhrzhnb.supabase.co` publishes an AAAA record and
**no A record**. GitHub-hosted runners are IPv4-only, so the direct connection
is unreachable from Actions no matter how correct the password is. Supabase
sells an IPv4 add-on that would fix this; the session pooler is free and does
the same job here.

The **transaction pooler** (6543) multiplexes statements across backends, which
breaks `pg_dump`. `backup-database.sh` rejects port 6543 outright and warns if
you hand it the direct host.

Note the session pooler also changes the **username**: it is
`postgres.uomelinvbqabczhrzhnb`, not plain `postgres`.

### If a backup fails

A failed run means **no backup was produced that night** — the script has no
partial-success path by design. Open the run, read the failing step, fix it,
then trigger a manual run rather than waiting for the next night.

GitHub emails the repository owner on workflow failure. Verified for this repo
as of 2026-08-24:

| Check | State | How verified |
|---|---|---|
| Repo owner is `hari243565`, admin | ✅ | GitHub REST API |
| Actions enabled on the repo | ✅ | `/actions/permissions` → `enabled: true` |
| No repo-level notification override | ✅ | no explicit subscription record; owners are auto-subscribed |
| Account-level "failed workflows" email | ⚠️ **not verifiable via API** | see below |

> ⚠️ **One thing you must confirm by hand — it is not readable through any API.**
>
> Go to **https://github.com/settings/notifications** → the **Actions** section
> → confirm **"Send notifications for failed workflows only"** is ticked, and
> that email delivery is enabled.
>
> This is the *only* failure alerting this pipeline has. If it is off, backups
> could silently stop for weeks and nothing would tell you. It is on by default,
> but "on by default" is not the same as "verified on", and this session could
> not verify it.
>
> Also confirm your GitHub notification email address is verified — an
> unverified address silently receives nothing.

### Free-tier quota headroom

This repo is **private**, so Actions minutes and artifact storage are metered
against the free allowance (2,000 minutes and 500 MB per month).

A backup run takes roughly 2–3 minutes, so the nightly schedule uses about
**90 minutes/month** — well inside the allowance. The encrypted dump is
currently ~280 KB; at 90-day retention that is roughly **25 MB** of artifact
storage. Both have ample headroom, but the storage figure grows with the
database, and it disappears entirely once backups move to R2.

### Free-tier project pausing — and why there is no keep-alive job

Supabase pauses Free Plan projects that show **low activity over a 7-day
period**. The docs are explicit that *database queries* are what counts:
"typically a few user requests to the database each day over the previous week
is enough to keep the project from being paused." Visiting the dashboard also
generates activity, but that depends on a human remembering to do it.

**The nightly backup already satisfies this.** Every run opens a session-pooler
connection and reads the entire database with `pg_dump` — real database
activity, every single day, with no extra moving parts. A separate keep-alive
workflow or `SELECT 1` ping is **not needed** and is not configured; it would be
one more thing to maintain that does nothing the backup is not already doing.

The catch is worth understanding rather than discovering later:

> Pause-protection is now a **side effect of the backup**, so the two fail
> together. If backups break — rotated database password, a bad secret, an
> Actions outage — you lose the backups *and* your only source of daily database
> activity at the same moment. The 7-day pause window is short enough that this
> can land before anyone notices.
>
> **This is why consecutive backup failures are urgent, not routine.** One
> failed night is noise; two in a row is a signal. See *If a backup fails*.

A related worry that does **not** apply here: GitHub auto-disables scheduled
workflows after 60 days of inactivity **in public repositories only**. This repo
is private, so the nightly schedule will not be switched off underneath you.

If the project is ever paused anyway:

- **Data is not deleted.** A paused project can be restored from the Supabase
  dashboard, and there is a **1-year window** to do so from Studio.
- **Backups fail while paused** — the dump cannot connect to a paused database.
  Restore the project first, then run a manual backup before trusting the
  schedule again.
- Pausing is discretionary ("we *may* pause"), so do not treat daily activity as
  a contractual guarantee. Projects on the Pro plan are never paused for
  inactivity; that is the only real removal of this risk.

Sources: [Project Pausing](https://supabase.com/docs/guides/platform/free-project-pausing),
[Production Checklist](https://supabase.com/docs/guides/deployment/going-into-prod).

---

### Restoring a backup

There are two steps. **You must perform the first one yourself** — no script,
no automation, and no AI assistant can do it, because it requires your offline
private key.

#### Step 1 — Decrypt (owner only)

Download the `.dump.age` artifact and unzip it. Optionally confirm it arrived
intact:

```bash
sha256sum -c danlite-backup-<timestamp>.dump.age.sha256
```

Then, on a trusted machine, with your private key:

```bash
age --decrypt \
    --identity /path/to/your-private-key.txt \
    --output   danlite-backup.dump \
    danlite-backup-<timestamp>.dump.age
```

Notes:

- Your private key file is the one starting `AGE-SECRET-KEY-1...`. Keep it
  offline. Do not paste it into a terminal that logs, into CI, into this repo,
  or into a chat with an AI assistant.
- **If you lose the private key, every backup becomes permanently unreadable.**
  There is no recovery path and no one — not Cloudflare, not GitHub, not
  Anthropic — can help. Store a copy somewhere physically separate from your
  main machine.
- Delete the decrypted `danlite-backup.dump` when you are finished with it. It
  is the entire customer database in the clear.

#### Step 2 — Restore and verify

```bash
bash scripts/restore-database.sh danlite-backup.dump scratch
```

This spins up a throwaway Postgres 17 Docker container, restores into it, and
prints row counts per table. Nothing outside Docker is touched. If you hand the
script the still-encrypted `.age` file, it stops and prints the Step 1 command
rather than pretending it can decrypt.

Then compare the restored counts against production (read-only):

```bash
psql "$DB_URL" -c "select 'profiles', count(*) from profiles
                   union all select 'licences', count(*) from licences
                   union all select 'payments', count(*) from payments
                   union all select 'orders',   count(*) from orders;"
```

They should match, allowing for rows written between the dump and the check.

Tear the scratch database down when done:

```bash
docker rm -f danlite-restore-scratch
```

**Expect some `pg_restore: error` lines.** A Supabase dump restored into plain
Postgres always produces benign errors — missing Supabase-specific roles
(`anon`, `authenticated`, `service_role`), missing extensions, comments on
skipped objects. The script counts and prints these rather than hiding them.
**Judge the restore on the row counts, not on the error count.**

#### Real disaster recovery, back into Supabase

Restoring into a live Supabase project is different and riskier:

- Drop `--no-owner --no-privileges` from `pg_restore` so Supabase role grants
  and RLS ownership come back intact. Restoring without them into a real
  project leaves RLS policies attached to the wrong owner and can silently
  expose or lock out data.
- Restore into a **fresh** Supabase project first and repoint the app, rather
  than restoring over a damaged one. It is far easier to abandon a bad restore
  than to undo one.
- `restore-database.sh` refuses a `supabase.co` target unless you set
  `I_UNDERSTAND_THIS_OVERWRITES_PRODUCTION=yes`. That guard is there on purpose.

---

### What the backup does and does not contain

**Contained:** the `public` schema (profiles, licences, payments, orders,
devices, sessions, webhook_events, audit_log, admin_users and the rest), the
`auth` schema (user accounts and identities), and the `storage` schema.

**Excluded**, because Supabase recreates them when a project is provisioned and
they are not ours to restore: `extensions`, `graphql`, `graphql_public`,
`pgbouncer`, `realtime`, `supabase_functions`, `supabase_migrations`, `vault`,
`cron`, `net`, `pgsodium`, and the `_analytics` / `_realtime` / `_supavisor`
internals.

**Also not covered by this pipeline:**

- **Edge Function source** — lives in `supabase/functions/` in git. Git is its backup.
- **Edge Function secrets / environment variables** — not in git and not in this
  backup. Record them separately; they would have to be re-entered by hand.
- **Storage bucket file contents** — the `storage` schema records file *metadata*;
  the actual objects are not dumped by `pg_dump`.
- **`vault` secrets** — excluded above. If anything depends on Vault, it must be
  re-provisioned manually after a restore.

---

### What has and has not been proven

#### Proven on 2026-08-24, with real output

The mechanism was proven end-to-end using a **throwaway age keypair generated
for the test** — never the owner's key. The full chain
*dump → encrypt → decrypt → restore → compare* was executed:

- `pg_dump` 17.11 against the live server (17.6), read-only, via the session
  pooler. Produced a 286,535-byte custom-format archive: 558 restorable TOC
  entries, 44 of them `TABLE DATA`.
- Encrypted to the test key, then **decrypted with the matching test private
  key** and restored into a throwaway Postgres 17.11 Docker container on an
  isolated network — not Supabase, not a branch.
- **All ten row counts matched live production exactly:**

  | Table | Live | Restored |
  |---|---|---|
  | `profiles` | 2 | 2 ✅ |
  | `licences` | 2 | 2 ✅ |
  | `payments` | 1 | 1 ✅ |
  | `orders` | 1 | 1 ✅ |
  | `devices` | 3 | 3 ✅ |
  | `sessions` | 11 | 11 ✅ |
  | `webhook_events` | 8 | 8 ✅ |
  | `audit_log` | 13 | 13 ✅ |
  | `admin_users` | 1 | 1 ✅ |
  | `auth.users` | 2 | 2 ✅ |

- `restore-database.sh` correctly refuses encrypted input (exit 2) and prints
  the decrypt command instead.

A second run then produced the **real** artifact encrypted to the owner's
actual public key (`age1u6lvup…s28ev5j`), and it passed every check that is
possible without the private key:

- valid `age-encryption.org/v1` header with an `X25519` recipient stanza
- 286,799 bytes — 264 bytes of age framing over the known dump size
- SHA-256 matches its recorded sidecar
- the **throwaway key is correctly rejected** with
  `no identity matched any of the recipients`, which proves the file is genuine
  age ciphertext addressed to a different recipient rather than random bytes
- the `.toc.txt` sidecar confirms `profiles`, `licences`, `payments`, `orders`
  and `admin_users` are present — auditable **without** decrypting

#### Proven on GitHub Actions — 2026-08-24

The workflow is committed and **has now run for real on GitHub Actions**, which
was the last outstanding gap. Two earlier attempts failed first, and both are
recorded here because they are environment faults that will recur on any fresh
runner image:

| Run | Result | Cause | Fix |
|---|---|---|---|
| `32691927541` | failed, 12s | `gpg --dearmor` invoked under `sudo` reached for `/dev/tty`, which does not exist on a runner; it died, and `curl` then failed writing into the dead pipe (exit 23) | dearmor as the normal user, then `sudo install` the result — `b671827` |
| `32691986679` | failed, 40s | the runner image's own PG16 client in `/usr/bin` shadowed the PGDG 17 binaries — `psql` resolved to 17.11 but `pg_dump` to 16.15 | put `/usr/lib/postgresql/17/bin` ahead of `/usr/bin` via `$GITHUB_PATH` and assert `pg_dump` is v17 — `16c48e5` |
| `32692117213` | **success, 1m28s** | — | published `danlite-encrypted-backup-32692117213` |

The second failure is the safety check working exactly as designed: the script
refused to dump a 17 server with a 16 client, producing **no backup rather than
a subtly bad one**. That is the behaviour you want from this pipeline.

The published artifact was then **downloaded and inspected**, not merely observed
to be green:

- three files, 322 KB total — `.dump.age`, its `.sha256` sidecar, and a
  plaintext `.toc.txt`
- SHA-256 recomputed after download **matches the recorded sidecar**
  (`486a631a…35c7ffc`), so the file survived upload and download intact
- valid `age-encryption.org/v1` header with an `X25519` recipient stanza
- **no plaintext `PGDMP`, `CREATE TABLE` or `COPY public` markers anywhere in the
  payload** — the body is real ciphertext, not an unencrypted dump wearing an
  `.age` extension
- the TOC describes a real archive: `pg_dump` 17.11 against server 17.6, 558
  entries, 44 of them `TABLE DATA`, plus 37 `ROW SECURITY`, 9 `POLICY`, 33
  `FUNCTION`, 33 `FK CONSTRAINT`, 81 `INDEX` and 9 `TRIGGER` — a restore rebuilds
  RLS and constraints, not merely rows
- **all 13 tables** declared in `supabase/migrations/` are present, diffed
  name-by-name against the migration files so nothing was silently missed —
  alongside `auth.users` and the `invoice_seq` and `audit_log_id_seq` values

None of this changes the one gap that remains: only the owner's private key can
prove these artifacts actually decrypt — which is the subject of the next section.

#### Not proven — and only the owner can prove it

Be precise about what the tests above did and did not establish. They proved the
**mechanism** works, using a key the build session controlled. They did **not**
prove that *your* key opens *your* backups.

> **What remains unverified: that the private key you hold actually decrypts
> artifacts encrypted to `age1u6lvup…s28ev5j`.**
>
> The build session never had your private key — by design, and correctly so.
> That means nobody has yet confirmed the two halves of your keypair match, or
> that the private key file you have saved is intact and is the right one.
>
> If that key is wrong, lost, or corrupt, **every backup this pipeline has ever
> produced is unreadable**, and nothing in the automated checks would reveal it.
> That specific failure is the one this session structurally could not rule out.
>
> **Do this once, by hand, before treating this pipeline as real protection.**
> Download the latest artifact, run Step 1 and Step 2 above, and confirm the row
> counts match production. Until you have personally done that, this is an
> untested backup, and an untested backup is a guess.
>
> Repeat the rehearsal roughly every quarter, and after any change to the
> schema, the key, or the storage destination.


### Verification log

Record each owner-performed rehearsal here.

| Date | Backup restored | Result | By |
|---|---|---|---|
| _(pending — first rehearsal not yet performed)_ | | | |

---

## Emergency paywall bypass

**What it is:** a single switch that makes the licence check say "yes" to
everybody. It exists for one situation only — a bug on our side is locking
**paying customers** out of the app, and the real fix is not deployed yet. It
stops the bleeding while you find the actual problem.

It is **not** a discount, **not** a free trial, and **not** a way to give one
person a licence. To help one customer, use *Licence correction* below instead.

### Read this before you arm it

While the switch is on, **everyone** who opens the app gets a working licence —
including people who have never paid a rupee.

The part that catches people out: each person who opens the app while it is on
walks away with a pass that **keeps working offline for 14 days**, and

> **turning the switch off does not take those passes back.**

There is no way to un-issue them. So the cost of leaving it on for an extra day
is not one extra day of free access — it is another day's worth of people who
each get another 14 days. Arm it late, disarm it early.

### How to arm it

Two things must both be true, which is deliberate — this switch must be
impossible to flip by accident.

1. The secret must be named exactly `PAYWALL_EMERGENCY_BYPASS`.
2. Its value must be exactly this text, with nothing else in it:

   ```
   EMERGENCY-PAYWALL-BYPASS-ON
   ```

Set it from your machine, in the project folder:

```bash
npx supabase secrets set PAYWALL_EMERGENCY_BYPASS=EMERGENCY-PAYWALL-BYPASS-ON
npx supabase functions deploy entitlement
```

Any other value — `1`, `true`, `yes`, `on`, or the right text with a stray
space — leaves the paywall fully in place. That is on purpose. The failure this
design refuses to allow is "the paywall quietly stopped existing and nobody
noticed", so nothing except that one exact string opens it.

### How to disarm it

```bash
npx supabase secrets unset PAYWALL_EMERGENCY_BYPASS
npx supabase functions deploy entitlement
```

Setting it to any other value also disarms it, but removing it entirely is
cleaner — there is then nothing to mistake for "off" later.

**Confirm it is really off.** Check the list of secrets and satisfy yourself the
name is gone:

```bash
npx supabase secrets list
```

Then remember the 14-day tail: for the next two weeks, some people will still
have working passes issued while it was on. That is expected and cannot be
reversed. It is not evidence the switch is still armed.

### Where its use is recorded

Every single request handled while the switch is on writes one row to
`audit_log`:

| Column | Value |
|---|---|
| `action` | `paywall_emergency_bypass_used` |
| `user_id` | the person who was let through |
| `detail.real_licence_status` | what their licence **actually** said |
| `detail.issued_licence_status` | always `active` |
| `detail.function` | `entitlement` |

You can read these in the admin portal under **Audit log**.

This is loud on purpose. A global bypass that left no trace would be
indefensible; one that records every use is an operational tool. Note the audit
write is best-effort — if writing the row fails, the customer is still let
through, because the switch is only ever on when customers are already locked
out. A failed write is shouted into the function log instead, so a broken trail
is still visible.

**One honest caveat:** the switch is read when the function starts, so a deploy
(or restart) is what actually applies a change. Do not assume setting the secret
alone has armed or disarmed anything — run the deploy command, then re-check.

---

## Licence correction and forced sign-out

**Use the admin portal for this. Not raw SQL.** The portal records who did what
and why; a hand-written database statement records nothing, and a mistyped one
cannot be undone.

### Getting in

1. Start the portal on your machine, from the project folder:

   ```bash
   cd admin
   npm run dev
   ```

2. Open **http://localhost:3001** in a browser.
3. Enter your email address. It must already be on the `admin_users` allowlist —
   if it is not, the portal tells you so plainly and sends nothing.
4. A **6-digit code** arrives by email. Enter it. You are in.

If the code never arrives, read *Sentry* below — the most likely cause is the
activation email transport, not the portal.

### Finding the person

**Users** in the top navigation, then search. Click through to their detail page.
You will see their licence status, their payments, and their devices.

### The three actions

Each one is on the user's detail page. All three ask you to confirm, and **all
three require you to type a reason** — the database itself rejects an empty one,
so this is not a formality you can click past.

| Action | Use it when | What the customer sees |
|---|---|---|
| **Grant** | They paid but the licence did not activate | The app starts working, within about a minute |
| **Revoke** | A refund, a chargeback, or a wrong grant | The app stops working when its current pass expires |
| **Force sign-out** | Their account is stuck on a device they no longer have, or they report someone else using it | They are signed out everywhere and must log in again |

**Write the reason for a stranger.** In six months, "fixed" tells nobody
anything. "Paid Rs 499 via Razorpay pay_XXXX on 24 Aug, webhook never arrived"
tells the next person exactly what happened.

### Two things worth knowing

- **Grant is not instant on the phone.** The app holds its existing pass until
  it expires. If the customer is watching, ask them to close and reopen the app.
- **Revoke has the same 14-day tail as the emergency bypass.** It stops the
  *next* pass being issued; it cannot reach into a phone and delete the pass
  already there. For a refund, this is normally fine. If it is not, use **Force
  sign-out** as well — that ends the session immediately.

Everything you do here lands in **Audit log**, with your name, the reason you
typed, and the time.

---

## Webhook failure diagnosis

A webhook is Razorpay telling us "this payment happened". If that message never
lands, or lands and fails, the customer has paid and has nothing to show for it.
This is the single most common cause of an angry message.

### Did we receive it at all?

Every webhook we accept writes one row to `webhook_events`. Check the recent
ones:

```bash
npx supabase db query --linked "select event_id, event_type, processed_at from webhook_events order by processed_at desc limit 20;"
```

Keep the SQL on **one line** — this command does not accept a query split across
several lines.

- **A row is there** → we received it and recorded it. If the customer still has
  no licence, the problem is after this point: look at `payments` and `licences`
  for that person, then use **Grant** from the admin portal to unblock them
  while you investigate.
- **No row at all** → the message never reached us, or we rejected it before
  trusting it. Open the Razorpay Dashboard → **Settings → Webhooks** and read the
  delivery attempts. Razorpay shows you the status code we returned.

### What the status code means

This distinction is the whole diagnosis, so it is worth being precise:

| What Razorpay saw | What it means | Where the fault is |
|---|---|---|
| **400** | We refused the message **before trusting it** — the signature was missing, the signature did not match, or the body was not readable | Almost always **the shared secret does not match**. Nothing was written. Nothing was half-done. |
| **500** | We **believed** the message and then something on our side failed — the database, the licence activation, the order lookup | **Our bug.** The payment is real. The customer needs a manual Grant now, and the underlying error needs fixing. |
| **200** | Accepted | Includes deliberate "ignored" outcomes — an event type we do not act on, an unknown order, an amount mismatch. A 200 does **not** by itself mean a licence was granted. |

> **The one-line version:** a **400** means we do not trust Razorpay's message
> and you should suspect the secret. A **500** means we trusted it and broke.
> A 400 storm is a configuration problem; a 500 storm is an outage.

There is one special 500 worth recognising: **"webhook not configured"**. That
means `RAZORPAY_WEBHOOK_SECRET` is missing entirely. Every webhook will fail
until it is set.

### Rotating the webhook secret

Both sides hold the same secret, and **they are only in step once you have
finished all four steps.** Between step 2 and step 3, live webhooks fail with a
400. Do this at a quiet hour, not during a sale.

1. **Generate a new secret** — long and random. Keep it somewhere you can paste
   from twice.

2. **Set it on our side:**

   ```bash
   npx supabase secrets set RAZORPAY_WEBHOOK_SECRET=<the new secret>
   npx supabase functions deploy razorpay-webhook
   ```

3. **Set the identical value in Razorpay** — Dashboard → Settings → Webhooks →
   edit the endpoint → replace the secret → save.

4. **Prove it works before you walk away.** Use Razorpay's own "send test
   webhook" button, then confirm a fresh row appeared:

   ```bash
   npx supabase db query --linked "select event_id, event_type, processed_at from webhook_events order by processed_at desc limit 5;"
   ```

   A new row means the two sides agree. A 400 in Razorpay's delivery log means
   they do not — re-check for a copied trailing space, which is the usual
   culprit.

This is the same shape as the database-password and backup-secret handling
described under *Database Backups*: change it in one place, deploy, then prove
it with a real run rather than assuming.

**Any payment that came in during the gap is not lost.** Razorpay retries failed
deliveries, and once the secret matches, the retry succeeds normally. If a
customer is waiting, Grant them a licence from the admin portal rather than
making them wait for a retry.

---

## Sentry — where errors show up

Two separate Sentry projects, because the two halves fail for different reasons
and you almost always want to look at only one of them:

| Project | Covers | Look here when |
|---|---|---|
| **Danlite ELM — App** | The Android app | A customer says the app crashed, froze, or would not sign in |
| **Danlite ELM — Edge Functions** | The seven backend functions | Payments, licences, activation emails, webhooks |

Both are reachable from **https://sentry.io** with the project's own login.

### How to read it

Sort by **Events** (how often) rather than by newest. One error hitting two
hundred people matters more than a fresh one that hit a single person once.

Two numbers appear on every issue: **events** (how many times it happened) and
**users** (how many different people saw it). The gap between them is the
diagnosis:

- **Many events, one user** → one person in a retry loop. Annoying for them,
  not an outage.
- **Many events, many users** → an outage. Treat it as one.

### What you will not find in Sentry

**No email addresses, no phone numbers, no request bodies.** Errors carry the
function name, a status code, an error type, and ids such as an order or payment
id — enough to find the record yourself in the database, and nothing that would
turn Sentry into a second copy of the customer list.

This was checked against a real event, not just configured: a login was
deliberately failed on a real device with the address `hs02…@gmail.com` typed
into the form, and the resulting Sentry event contained the file, the line, the
sign-in channel and the failure category — and **no trace of the address
anywhere**, including in the debug breadcrumbs, which Sentry itself shows as
`[Filtered]`.

So the workflow is: Sentry tells you **what** broke and **how widely**; the
admin portal and the database tell you **who** it happened to.

> ### ⚠ One thing that is NOT yet private: IP addresses
>
> Events currently arrive carrying the caller's **IP address** and a city-level
> **location** ("Mumbai, India"). This is not something the app chooses to send —
> Sentry fills it in at its end — and it happens even though the code asks for
> no personal data, and even after the code was changed to explicitly blank the
> field. That was tested twice and the address still arrived.
>
> **There is a switch that fixes it, and it has to be flipped by hand — once per
> project:**
>
> **Sentry → Settings → Security & Privacy → "Prevent Storing of IP Addresses"**
>
> Do this on **both** projects (App and Edge Functions). Until it is on, assume
> Sentry holds a rough location for anyone who hits an error. Under the DPDP Act
> that is personal data, so this is worth doing before real customers are on the
> system rather than after.

### What to expect, and what it would mean

> **Mostly expectations, not yet observations.** Error reporting was switched on
> in Phase 9, so the only events recorded so far are the deliberate test ones
> below. Everything after those is drawn from faults this project has genuinely
> had, and describes what each would look like now that it is being reported.
> Replace them with real incidents as they happen.

**Already seen — the Phase 9 verification events (safe to resolve).** Three
events were created on purpose while wiring this up, and you will see them as
the oldest entries:

| Project | Issue | What it was |
|---|---|---|
| Edge Functions | `Phase 9 verification — deliberate test error…` | a throwaway function, deployed to prove reporting worked and then deleted |
| App | `auth dispatch failed` (`auth_provider.dart`) | a login attempted with the phone offline |
| App | `FunctionsFetchException` (`entitlement_service.dart`) | the licence check running with the phone offline |

The two app ones are worth understanding, because **they are what a genuinely
offline customer produces** — they are not defects. `FunctionsFetchException`
with `Failed host lookup` means the phone had no network. If you see a handful
of these, that is normal life in a car park or a basement workshop. See *Fetch
failures* below for how to separate them from real bugs.

**A cluster of activation-email failures from `send-activation`.** This project
still sends activation email from Resend's **shared** sending domain
(`onboarding@resend.dev`), because `ACTIVATION_FROM_EMAIL` has never been set and
no domain of our own has been verified. **That gap is open today — it is not a
past problem.** While it stands, delivery depends on a domain we do not control:
codes land in spam, or are rejected outright by stricter mail providers. A
cluster of failures here — especially all to the same mail provider — points at
the sending domain, not at our code. Its signature is customers saying "the code
never arrived" while the function log shows the send being made. **The fix is to
verify a real domain in Resend and set `ACTIVATION_FROM_EMAIL`, not to retry the
sends.**

**A burst of `42501 permission denied` from any function.** This project has hit
this before. It means a table or sequence is missing a grant for `service_role` —
a newly created table gives it no data permissions at all, and a `bigserial` id
column needs its sequence granted separately. It appears immediately after a
migration and affects **every** user, not some. That is a deployment fault, not
a customer fault.

**`entitlement signature verification failed` from the app.** Either the signing
key changed on the backend and real customers are now stranded, or somebody is
editing a stored pass on their own device. Tell the two apart by the user count:
one user is tampering, many users is an outage you caused.

**Fetch failures from the app's entitlement check.** Most of these are simply
phones with no signal, which is why the error type is attached to every one.
Filter out `SocketException`, `TimeoutException` and `ClientException`, and
whatever remains is a genuine defect — that same catch also swallows
response-parsing bugs, which would otherwise never be seen.

**A `500` storm from `razorpay-webhook`.** Cross-reference *Webhook failure
diagnosis* above. Customers have paid and have no licence. Grant them from the
admin portal first, diagnose second.

### If Sentry itself goes quiet

An empty dashboard is ambiguous: it means either nothing is failing or nothing
is reporting. Reporting is deliberately built to fail silently rather than take
the app down with it, which is the right trade — but it does mean silence proves
nothing on its own.

Both halves switch off completely when their DSN is absent:

- **App:** `SENTRY_DSN` in the gitignored `.env` file. If it is missing, the app
  runs perfectly and reports nothing at all.
- **Edge Functions:** the `SENTRY_DSN` secret. Check it is present with
  `npx supabase secrets list`.

If you have seen no events at all for a week, confirm the DSN is still in place
before concluding that things are healthy.
