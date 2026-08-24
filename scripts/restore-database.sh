#!/usr/bin/env bash
#
# Danlite ELM — restore a backup produced by scripts/backup-database.sh.
#
# ==========================================================================
#  THIS SCRIPT DOES NOT DECRYPT. THAT STEP IS YOURS ALONE.
# ==========================================================================
#
#  Backups are encrypted to your age PUBLIC key. Only your PRIVATE key can
#  open them, and that key is kept offline, off this machine, out of CI, and
#  out of every automated system in this project. That is the entire point:
#  if the pipeline could decrypt its own backups, then anyone who compromised
#  the pipeline could read the whole database.
#
#  So the restore is two commands, and you run the first one yourself:
#
#    STEP 1 — YOU, on a trusted machine, with your private key:
#
#      age --decrypt \
#          --identity /path/to/your-private-key.txt \
#          --output   danlite-backup.dump \
#          danlite-backup-2026-08-24-220000Z.dump.age
#
#    STEP 2 — this script, on the decrypted file:
#
#      bash scripts/restore-database.sh danlite-backup.dump scratch
#
#  If you hand this script a .age file it will stop and print STEP 1 for you
#  rather than pretending it can do something it cannot.
#
# --------------------------------------------------------------------------
# USAGE
#   bash scripts/restore-database.sh <decrypted.dump> [target]
#
#   target:
#     scratch   (default) spin up a throwaway Postgres 17 container, restore
#               into it, run verification queries, and leave it running so you
#               can inspect it. Nothing outside Docker is touched.
#     <URI>     a postgresql:// URI to restore into. Guarded — see below.
#
# SAFETY
#   Restoring into anything hosted on supabase.co is refused unless you set
#     I_UNDERSTAND_THIS_OVERWRITES_PRODUCTION=yes
#   Do not set that variable unless you are knowingly performing a real
#   disaster recovery onto a project you intend to overwrite.

set -Eeuo pipefail

log()  { printf '[restore] %s\n'        "$*"; }
warn() { printf '[restore] WARNING: %s\n' "$*" >&2; }
die()  { printf '[restore] FATAL: %s\n' "$*" >&2; exit 1; }

DUMP="${1:-}"
TARGET="${2:-scratch}"

SCRATCH_CONTAINER="${SCRATCH_CONTAINER:-danlite-restore-scratch}"
SCRATCH_PASSWORD="${SCRATCH_PASSWORD:-scratch_only_not_a_secret}"
SCRATCH_PORT="${SCRATCH_PORT:-55432}"
SCRATCH_DB="${SCRATCH_DB:-danlite_restore_test}"
PG_IMAGE="${PG_IMAGE:-postgres:17-alpine}"

# ---------------------------------------------------------------------------
# Input checks
# ---------------------------------------------------------------------------

if [[ -z "$DUMP" ]]; then
  die "usage: bash scripts/restore-database.sh <decrypted.dump> [scratch|<postgres-uri>]"
fi

# The whole reason this script exists as a separate file: catch the encrypted
# input and hand the owner the exact command only they can run.
if [[ "$DUMP" == *.age ]]; then
  cat >&2 <<EOF

[restore] That file is still encrypted, and this script cannot decrypt it.
[restore] Decryption needs your age PRIVATE key, which is deliberately kept
[restore] offline and is not available to this script, to CI, or to Claude.

[restore] Run this yourself first, on a trusted machine:

    age --decrypt \\
        --identity /path/to/your-private-key.txt \\
        --output   "${DUMP%.age}" \\
        "${DUMP}"

[restore] Then re-run:

    bash scripts/restore-database.sh "${DUMP%.age}" ${TARGET}

EOF
  exit 2
fi

[[ -f "$DUMP" ]] || die "no such file: $DUMP"
[[ -s "$DUMP" ]] || die "$DUMP is empty."

command -v pg_restore >/dev/null 2>&1 || die "pg_restore is not installed or not on PATH."

# If the owner accidentally points this at ciphertext with the wrong extension,
# say so clearly instead of emitting a confusing pg_restore parse error.
# String compare, not a pipe into grep: under `set -o pipefail` an early-exiting
# downstream command sends SIGPIPE upstream and fails the script spuriously.
if [[ "$(head -c 21 "$DUMP")" == "age-encryption.org/v1" ]]; then
  die "$DUMP is age ciphertext, not a dump. Decrypt it first (see the header of this script)."
fi

log "verifying the archive parses before touching any database..."
pg_restore --list "$DUMP" > /tmp/restore-toc.$$ 2>/dev/null \
  || die "$DUMP is not a valid custom-format pg_dump archive."
# grep -a: a TOC can carry stray null bytes from object comments, which makes
# grep switch to binary mode and makes bash warn about nulls in the result.
log "archive is valid: $(grep -acv '^;' /tmp/restore-toc.$$) restorable entries, $(grep -ac 'TABLE DATA' /tmp/restore-toc.$$ || true) with table data"
rm -f /tmp/restore-toc.$$

# ---------------------------------------------------------------------------
# Resolve the target
# ---------------------------------------------------------------------------

if [[ "$TARGET" == "scratch" ]]; then
  command -v docker >/dev/null 2>&1 || die "target 'scratch' needs Docker, which is not installed or not running."

  log "starting a throwaway Postgres 17 container ('${SCRATCH_CONTAINER}')..."
  docker rm -f "$SCRATCH_CONTAINER" >/dev/null 2>&1 || true
  docker run -d --name "$SCRATCH_CONTAINER" \
    -e POSTGRES_PASSWORD="$SCRATCH_PASSWORD" \
    -e POSTGRES_DB="$SCRATCH_DB" \
    -p "${SCRATCH_PORT}:5432" \
    "$PG_IMAGE" >/dev/null

  log "waiting for it to accept connections..."
  for i in $(seq 1 60); do
    if docker exec "$SCRATCH_CONTAINER" pg_isready -U postgres -q 2>/dev/null; then break; fi
    [[ $i -eq 60 ]] && die "the scratch container never became ready."
    sleep 1
  done

  TARGET_URI="postgresql://postgres:${SCRATCH_PASSWORD}@127.0.0.1:${SCRATCH_PORT}/${SCRATCH_DB}"
  IN_DOCKER=1
  log "scratch database is up on port ${SCRATCH_PORT}."
else
  TARGET_URI="$TARGET"
  IN_DOCKER=0

  case "$TARGET_URI" in
    # One pattern is enough: *supabase.co* already matches supabase.com,
    # and covers db.<ref>.supabase.co and *.pooler.supabase.com alike.
    *supabase.co*)
      if [[ "${I_UNDERSTAND_THIS_OVERWRITES_PRODUCTION:-}" != "yes" ]]; then
        die "refusing to restore into a Supabase-hosted database. If this really is a disaster recovery, re-run with I_UNDERSTAND_THIS_OVERWRITES_PRODUCTION=yes"
      fi
      warn "restoring into a SUPABASE-HOSTED database. This overwrites live data."
      warn "you have 10 seconds to press Ctrl-C."
      sleep 10
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------
#
# --no-owner / --no-role-passwords / --no-privileges: the dump carries Supabase
# role ownership and grants (anon, authenticated, service_role, supabase_admin).
# A plain Postgres has none of those roles, so we drop ownership and ACLs when
# restoring anywhere that is not Supabase. For a real recovery back INTO
# Supabase, remove --no-owner and --no-privileges so grants come back intact.
#
# We deliberately do NOT pass --exit-on-error. Restoring a Supabase dump into
# vanilla Postgres always produces some benign errors (missing extensions,
# missing roles, comments on objects we skipped). Those are counted and
# reported below rather than hidden — the pass/fail decision is made on the
# verification queries, not on pg_restore's exit code.

RESTORE_ARGS=( --dbname="$TARGET_URI" --no-owner --no-privileges --verbose --jobs=2 )

log "restoring... (benign errors are expected and are counted, not hidden)"
set +e
pg_restore "${RESTORE_ARGS[@]}" "$DUMP" 2> /tmp/restore-err.$$
RESTORE_RC=$?
set -e

ERR_COUNT="$(grep -c '^pg_restore: error' /tmp/restore-err.$$ || true)"
log "pg_restore exit code: ${RESTORE_RC}; error lines: ${ERR_COUNT}"

if (( ERR_COUNT > 0 )); then
  log "first 20 errors (review these — they are not automatically fatal):"
  # `sed -n '1,20p'` rather than `| head -20`: sed reads its whole input, so
  # the upstream grep never takes SIGPIPE and trips `set -o pipefail`.
  grep '^pg_restore: error' /tmp/restore-err.$$ | sed -n '1,20p' | sed 's/^/    /'
fi
rm -f /tmp/restore-err.$$

# ---------------------------------------------------------------------------
# Verify — this, not the exit code, is what decides success
# ---------------------------------------------------------------------------

psql_t() {
  if (( IN_DOCKER )); then
    docker exec -e PGPASSWORD="$SCRATCH_PASSWORD" "$SCRATCH_CONTAINER" \
      psql -U postgres -d "$SCRATCH_DB" -tAc "$1"
  else
    psql "$TARGET_URI" -tAc "$1"
  fi
}

log ""
log "=== VERIFICATION ==="

TABLE_COUNT="$(psql_t "select count(*) from information_schema.tables where table_schema in ('public','auth','storage');")"
log "tables restored across public/auth/storage: ${TABLE_COUNT}"

(( TABLE_COUNT > 0 )) || die "no tables were restored. The restore did NOT work."

log ""
log "row counts per table (public schema):"
psql_t "
  select table_name
  from information_schema.tables
  where table_schema='public' and table_type='BASE TABLE'
  order by table_name;
" | while read -r t; do
  [[ -z "$t" ]] && continue
  n="$(psql_t "select count(*) from public.\"$t\";" 2>/dev/null || echo '?')"
  printf '    %-28s %s\n' "$t" "$n"
done

log ""
log "row counts per table (auth schema — the user records):"
psql_t "
  select table_name
  from information_schema.tables
  where table_schema='auth' and table_type='BASE TABLE'
  order by table_name;
" | while read -r t; do
  [[ -z "$t" ]] && continue
  n="$(psql_t "select count(*) from auth.\"$t\";" 2>/dev/null || echo '?')"
  printf '    %-28s %s\n' "$t" "$n"
done

log ""
log "=== COMPARE THESE AGAINST THE LIVE DATABASE ==="
log "Run the same counts against production (read-only) and confirm they match:"
log ""
log "    psql \"\$DB_URL\" -c \"select 'profiles', count(*) from profiles"
log "                          union all select 'licences', count(*) from licences"
log "                          union all select 'payments', count(*) from payments"
log "                          union all select 'orders',   count(*) from orders;\""
log ""

if (( IN_DOCKER )); then
  log "The scratch database is still running so you can inspect it:"
  log "    psql '${TARGET_URI}'"
  log ""
  log "Tear it down when you are done:"
  log "    docker rm -f ${SCRATCH_CONTAINER}"
fi

log ""
log "Restore completed. Judge it on the counts above, not on this message."
