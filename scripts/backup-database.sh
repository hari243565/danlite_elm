#!/usr/bin/env bash
#
# Danlite ELM — encrypted logical backup of the production Supabase database.
#
# WHAT THIS DOES
#   1. pg_dump the whole database in custom format (-Fc)
#   2. Verify the dump is a real, parseable archive (not a truncated file)
#   3. Encrypt it to the owner's age PUBLIC key
#   4. Verify the ciphertext is well-formed age
#   5. Hand the encrypted file to the configured destination
#
# WHAT THIS DOES NOT DO
#   - It never decrypts. This script only ever holds the age PUBLIC key.
#     Decryption requires the owner's private key, which is kept offline and
#     is deliberately not available to this pipeline or to CI. If you ever
#     find yourself wanting the private key here, something is wrong.
#   - It never writes to the production database. pg_dump is read-only.
#
# USAGE (manual run, from the repo root)
#   export DB_URL='postgresql://postgres.<ref>:...@aws-0-<region>.pooler.supabase.com:5432/postgres'
#   export AGE_PUBLIC_KEY='age1...'
#   bash scripts/backup-database.sh
#
# WHICH CONNECTION STRING (this matters — see docs/RUNBOOK.md)
#   Supabase offers three, and only one of them works here.
#
#   Session pooler   aws-0-<region>.pooler.supabase.com:5432   <-- USE THIS
#       IPv4, and session mode holds a real backend for the life of the
#       connection, which is what pg_dump needs.
#
#   Direct           db.<ref>.supabase.co:5432                 <-- DOES NOT WORK IN CI
#       Technically ideal, but on the free tier it resolves to IPv6 ONLY
#       (no A record). GitHub-hosted runners are IPv4-only, so this is
#       unreachable from Actions no matter what the credentials are.
#       Verified for this project: AAAA only, no A record.
#
#   Transaction pooler  ...pooler.supabase.com:6543            <-- NEVER
#       Multiplexes statements across backends. pg_dump breaks on it.
#       Rejected outright below.
#
# ENVIRONMENT
#   DB_URL           (required) Postgres URI on port 5432. Session pooler or,
#                               where IPv6 egress exists, the direct connection.
#                               Port 6543 is rejected.
#   AGE_PUBLIC_KEY   (required) recipient public key, "age1..."
#   BACKUP_DEST      (optional) "artifact" (default) or "r2"
#   ARTIFACT_DIR     (optional) where artifact-mode drops the file. Default ./backup-artifact
#   RETENTION_DAYS   (optional) r2-mode prune age in days. Default 30
#   MIN_DUMP_BYTES   (optional) floor for the plausibility check. Default 10240
#
#   r2 mode additionally requires:
#   R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET, R2_ENDPOINT
#
# EXIT CODES
#   0  backup produced and delivered, all checks passed
#   non-zero  anything else. There is deliberately no partial-success path:
#             a backup that half-worked must look like a failure, not a success.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Logging + failure trap
# ---------------------------------------------------------------------------

log()  { printf '[backup] %s\n'        "$*"; }
warn() { printf '[backup] WARNING: %s\n' "$*" >&2; }
die()  { printf '[backup] FATAL: %s\n' "$*" >&2; exit 1; }

on_err() {
  local code=$?
  printf '[backup] FATAL: failed at line %s (exit %s)\n' "${BASH_LINENO[0]}" "$code" >&2
  exit "$code"
}
trap on_err ERR

# Scratch dir holds the PLAINTEXT dump. Always destroyed, on every exit path.
WORKDIR="$(mktemp -d)"
cleanup() {
  if [[ -n "${WORKDIR:-}" && -d "$WORKDIR" ]]; then
    find "$WORKDIR" -type f -exec shred -u {} \; 2>/dev/null || true
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

BACKUP_DEST="${BACKUP_DEST:-artifact}"
ARTIFACT_DIR="${ARTIFACT_DIR:-./backup-artifact}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
MIN_DUMP_BYTES="${MIN_DUMP_BYTES:-10240}"

# Timestamp is UTC and sortable. Date only would collide if a manual run and
# the nightly run land on the same day, so include the time.
STAMP="$(date -u +%Y-%m-%d-%H%M%SZ)"
BASENAME="danlite-backup-${STAMP}.dump"
DUMP_PATH="${WORKDIR}/${BASENAME}"
ENC_PATH="${WORKDIR}/${BASENAME}.age"

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------

[[ -n "${DB_URL:-}" ]]         || die "DB_URL is not set."
[[ -n "${AGE_PUBLIC_KEY:-}" ]] || die "AGE_PUBLIC_KEY is not set."

# Guard against the single most likely misconfiguration: the TRANSACTION
# pooler on 6543. It multiplexes statements across backends, so pg_dump either
# errors out or returns a subtly inconsistent dump — the worst possible
# outcome for a backup. The SESSION pooler on 5432 is fine and is what CI uses.
case "$DB_URL" in
  *:6543/*) die "DB_URL points at port 6543 (the TRANSACTION pooler). pg_dump cannot use it. Use the session pooler on port 5432." ;;
esac

case "$DB_URL" in
  postgresql://*|postgres://*) : ;;
  *) die "DB_URL does not look like a Postgres URI (expected it to start with 'postgresql://')." ;;
esac

# Warn — do not fail — on the direct connection. It works from an IPv6-capable
# host, but on Supabase's free tier db.<ref>.supabase.co has no A record, and
# GitHub-hosted runners are IPv4-only. Failing here would break legitimate
# local use; staying silent would let CI break mysteriously.
case "$DB_URL" in
  *db.*.supabase.co:5432*)
    warn "DB_URL is the DIRECT connection (db.*.supabase.co). On the free tier this is IPv6-only."
    warn "It works locally if you have IPv6 egress, but GitHub-hosted runners are IPv4-only and cannot reach it."
    warn "For CI, use the session pooler: aws-0-<region>.pooler.supabase.com:5432"
    ;;
esac

# The age public key must actually be a public key. If someone ever pastes a
# private key in here by mistake, fail loudly rather than silently accepting it
# and writing the secret into CI logs or process listings.
case "$AGE_PUBLIC_KEY" in
  AGE-SECRET-KEY-*) die "AGE_PUBLIC_KEY contains an age PRIVATE key. This pipeline must only ever hold the public key. Rotate that key immediately." ;;
  age1*)  : ;;
  *)      die "AGE_PUBLIC_KEY does not look like an age public key (expected it to start with 'age1')." ;;
esac

for tool in pg_dump pg_restore age; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' is not installed or not on PATH."
done

if [[ "$BACKUP_DEST" == "r2" ]]; then
  command -v aws >/dev/null 2>&1 || die "BACKUP_DEST=r2 requires the AWS CLI, which is not installed."
  for v in R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_ENDPOINT; do
    [[ -n "${!v:-}" ]] || die "BACKUP_DEST=r2 but $v is not set."
  done
fi

# ---------------------------------------------------------------------------
# 1. Version check
# ---------------------------------------------------------------------------
#
# pg_dump REFUSES to dump from a server newer than itself. Supabase runs
# Postgres 17. GitHub's ubuntu runners have historically shipped an older
# client, so the workflow installs the PGDG 17 client explicitly. This check
# makes that requirement enforced rather than assumed — if the runner image
# ever changes, this fails loudly on day one instead of producing nothing.

# Parsed without a `| head`: under `set -o pipefail`, head exiting early sends
# SIGPIPE to the upstream command and the whole pipeline returns 141.
# awk consumes all of its input, so there is no early close here.
# Handles both "pg_dump (PostgreSQL) 17.11" and the PGDG form
# "pg_dump (PostgreSQL) 17.11 (Ubuntu 17.11-1.pgdg24.04+1)".
CLIENT_VERSION_RAW="$(pg_dump --version)"
CLIENT_VERSION_NUM="$(awk '{print $3}' <<<"$CLIENT_VERSION_RAW")"
CLIENT_MAJOR="${CLIENT_VERSION_NUM%%.*}"
SERVER_VERSION="$(psql "$DB_URL" -tAc 'SHOW server_version;' 2>/dev/null || echo '')"

if [[ -z "$SERVER_VERSION" ]]; then
  die "could not connect to the database to read its version. Check DB_URL and network egress."
fi

SERVER_MAJOR="$(printf '%s' "$SERVER_VERSION" | grep -oE '^[0-9]+')"
log "pg_dump client major: ${CLIENT_MAJOR}; server version: ${SERVER_VERSION} (major ${SERVER_MAJOR})"

if (( CLIENT_MAJOR < SERVER_MAJOR )); then
  die "pg_dump ${CLIENT_MAJOR} cannot dump a Postgres ${SERVER_MAJOR} server. Install the matching client."
fi

# ---------------------------------------------------------------------------
# 2. Dump
# ---------------------------------------------------------------------------
#
# -Fc  custom format: compressed, and restorable selectively with pg_restore.
# --no-acl / --no-owner are deliberately NOT set here. We capture ownership and
# grants in the archive so a real disaster-recovery restore back into Supabase
# can reproduce them. The restore script drops them with pg_restore flags when
# restoring into a plain Postgres that has no Supabase roles. Keeping the dump
# maximal and filtering at restore time is the reversible choice.
#
# Supabase-managed internals are excluded: they are recreated by the platform
# when a project is provisioned, are not owned by us, and attempting to dump or
# restore them produces permission errors and unrestorable noise. Everything
# that is actually *our* data — public, auth, storage — is captured in full.

EXCLUDED_SCHEMAS=(
  extensions
  graphql
  graphql_public
  pgbouncer
  realtime
  supabase_functions
  supabase_migrations
  vault
  _analytics
  _realtime
  _supavisor
  cron
  net
  pgsodium
  pgsodium_masks
)

PGDUMP_ARGS=(
  --format=custom
  --compress=9
  --verbose
  --no-password
)
for s in "${EXCLUDED_SCHEMAS[@]}"; do
  PGDUMP_ARGS+=( --exclude-schema="$s" )
done

log "dumping to a temporary file (plaintext, destroyed on exit)..."
# stderr from --verbose is noisy but valuable; keep it in the CI log. It cannot
# leak the password: the URI is passed as one argv element and never echoed.
if ! pg_dump "${PGDUMP_ARGS[@]}" --file="$DUMP_PATH" "$DB_URL"; then
  die "pg_dump failed."
fi

[[ -s "$DUMP_PATH" ]] || die "pg_dump produced an empty file."

DUMP_BYTES="$(wc -c < "$DUMP_PATH" | tr -d '[:space:]')"
log "dump size: ${DUMP_BYTES} bytes"

if (( DUMP_BYTES < MIN_DUMP_BYTES )); then
  die "dump is only ${DUMP_BYTES} bytes, below the ${MIN_DUMP_BYTES}-byte floor. Treating as a failed dump."
fi

# ---------------------------------------------------------------------------
# 3. Verify the dump is a real archive
# ---------------------------------------------------------------------------
#
# This is the check that separates "the command exited 0" from "we actually
# have something restorable". pg_restore --list parses the archive's table of
# contents; a truncated or corrupt file fails here.

log "verifying the archive parses..."
TOC="${WORKDIR}/toc.txt"
if ! pg_restore --list "$DUMP_PATH" > "$TOC" 2>"${WORKDIR}/toc.err"; then
  warn "pg_restore --list stderr:"; cat "${WORKDIR}/toc.err" >&2 || true
  die "the dump is not a valid custom-format archive."
fi

# grep -a: a TOC can carry stray null bytes from object comments, which makes
# grep switch to binary mode and makes bash warn about nulls in the result.
TOC_ENTRIES="$(grep -acv '^;' "$TOC" || true)"
log "archive table of contents: ${TOC_ENTRIES} restorable entries"
(( TOC_ENTRIES > 0 )) || die "the archive parsed but contains zero restorable entries."

# A schema-only or table-less dump would still parse. Require that the archive
# actually carries table data, which is the whole point of the backup.
TABLE_DATA="$(grep -ac 'TABLE DATA' "$TOC" || true)"
log "archive contains ${TABLE_DATA} TABLE DATA entries"
(( TABLE_DATA > 0 )) || die "the archive contains no TABLE DATA entries — this is not a usable backup."

# ---------------------------------------------------------------------------
# 4. Encrypt (public key only)
# ---------------------------------------------------------------------------

log "encrypting to recipient ${AGE_PUBLIC_KEY}"
age --encrypt --recipient "$AGE_PUBLIC_KEY" --output "$ENC_PATH" "$DUMP_PATH" \
  || die "age encryption failed."

[[ -s "$ENC_PATH" ]] || die "age produced an empty file."

ENC_BYTES="$(wc -c < "$ENC_PATH" | tr -d '[:space:]')"
log "encrypted size: ${ENC_BYTES} bytes"

# age's header is plaintext and identifies the format. If this is missing, the
# file is not age ciphertext and the owner will not be able to decrypt it.
# Compared as a string rather than piped into grep, to avoid the same SIGPIPE
# trap that `set -o pipefail` turns into a spurious failure.
AGE_HEADER="$(head -c 21 "$ENC_PATH")"
[[ "$AGE_HEADER" == "age-encryption.org/v1" ]] \
  || die "the output does not carry an age v1 header — refusing to publish it as a backup."

# The payload is already compressed by pg_dump, so age is near-1:1. A ciphertext
# dramatically smaller than the plaintext means truncation.
if (( ENC_BYTES * 2 < DUMP_BYTES )); then
  die "encrypted file (${ENC_BYTES} B) is implausibly small next to the dump (${DUMP_BYTES} B) — suspected truncation."
fi

SHA256="$(sha256sum "$ENC_PATH" | awk '{print $1}')"
log "sha256(ciphertext): ${SHA256}"

# ---------------------------------------------------------------------------
# 5. Deliver
# ---------------------------------------------------------------------------

case "$BACKUP_DEST" in

  artifact)
    # ---- TEMPORARY — swap to Cloudflare R2 once the client's account is ready.
    # The bucket does not exist yet (card + domain arriving). Until then the
    # encrypted file is handed to the caller, and the GitHub Actions workflow
    # uploads it as a build artifact with 90-day retention.
    #
    # Retention in this mode is GitHub's, not ours: the prune step below is
    # skipped entirely because Actions expires artifacts on its own schedule.
    #
    # WHAT CHANGES WHEN R2 ARRIVES: only BACKUP_DEST=r2 and the four R2_*
    # secrets. The dump, the verification, the encryption and the restore
    # procedure are all unchanged.
    mkdir -p "$ARTIFACT_DIR"
    cp "$ENC_PATH" "${ARTIFACT_DIR}/"
    cp "$TOC"      "${ARTIFACT_DIR}/${BASENAME}.toc.txt"
    printf '%s  %s\n' "$SHA256" "${BASENAME}.age" > "${ARTIFACT_DIR}/${BASENAME}.age.sha256"
    log "TEMPORARY artifact mode: wrote ${ARTIFACT_DIR}/${BASENAME}.age"
    log "TEMPORARY artifact mode: retention is GitHub's 90-day artifact expiry, not the ${RETENTION_DAYS}-day R2 prune."
    ;;

  r2)
    # R2 speaks the S3 API at https://<ACCOUNT_ID>.r2.cloudflarestorage.com.
    # ListObjectsV2, DeleteObject and DeleteObjects are supported; bucket-level
    # lifecycle configuration over the S3 API is not, which is why retention
    # below is an explicit list-then-delete rather than a lifecycle rule. That
    # is also the better choice for a backup pruner: it logs what it removed.
    export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION=auto

    # AWS CLI v2.23+ sends CRC32/CRC64 integrity headers by default, which R2
    # rejected with "Header 'x-amz-checksum-algorithm' ... not implemented".
    # Cloudflare has since fixed this, but pinning the old behaviour costs
    # nothing and protects against a regression silently breaking every upload.
    export AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED
    export AWS_RESPONSE_CHECKSUM_VALIDATION=WHEN_REQUIRED

    log "uploading to r2://${R2_BUCKET}/${BASENAME}.age"
    aws s3 cp "$ENC_PATH" "s3://${R2_BUCKET}/${BASENAME}.age" \
      --endpoint-url "$R2_ENDPOINT" \
      --checksum-algorithm CRC32 \
      || die "upload to R2 failed."

    # Read it back. An upload that reports success but stored nothing is
    # exactly the false confidence this pipeline exists to prevent.
    REMOTE_BYTES="$(aws s3api head-object \
      --bucket "$R2_BUCKET" --key "${BASENAME}.age" \
      --endpoint-url "$R2_ENDPOINT" \
      --query 'ContentLength' --output text)" || die "could not HEAD the object we just uploaded."

    log "verified in bucket: ${REMOTE_BYTES} bytes"
    [[ "$REMOTE_BYTES" == "$ENC_BYTES" ]] \
      || die "size mismatch: local ${ENC_BYTES} B vs remote ${REMOTE_BYTES} B."

    # ---- Retention: delete anything older than RETENTION_DAYS.
    CUTOFF="$(date -u -d "${RETENTION_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)"
    log "pruning backups last modified before ${CUTOFF}"

    OLD_KEYS="$(aws s3api list-objects-v2 \
      --bucket "$R2_BUCKET" \
      --prefix 'danlite-backup-' \
      --endpoint-url "$R2_ENDPOINT" \
      --query "Contents[?LastModified<\`${CUTOFF}\`].Key" \
      --output text 2>/dev/null || true)"

    if [[ -z "$OLD_KEYS" || "$OLD_KEYS" == "None" ]]; then
      log "nothing to prune."
    else
      # Never prune the object we just wrote, whatever the clocks say.
      for key in $OLD_KEYS; do
        if [[ "$key" == "${BASENAME}.age" ]]; then
          warn "refusing to prune the backup written by this run: $key"
          continue
        fi
        log "pruning $key"
        aws s3api delete-object \
          --bucket "$R2_BUCKET" --key "$key" \
          --endpoint-url "$R2_ENDPOINT" >/dev/null \
          || die "failed to delete $key — retention is not being enforced."
      done
    fi
    ;;

  *)
    die "unknown BACKUP_DEST '${BACKUP_DEST}' (expected 'artifact' or 'r2')."
    ;;
esac

log "OK — ${BASENAME}.age (${ENC_BYTES} bytes, sha256 ${SHA256})"
log "Reminder: this pipeline cannot verify the file decrypts. Only the owner,"
log "with the offline private key, can confirm that. See docs/RUNBOOK.md."
