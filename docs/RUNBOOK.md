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
