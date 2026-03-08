#!/usr/bin/env bash
# ==============================================================================
# Restore Test Script
# ==============================================================================
# Verifies that backups are actually restorable by restoring the latest
# snapshot to a temporary directory and checking for key files.
#
# A backup you've never tested restoring is not a backup — it's a hope.
# Run this quarterly via cron to catch problems early.
#
# Prerequisites:
#   - restic installed on the host
#   - .env file configured (same one used by backup.sh)
#
# Usage:
#   ./restore-test.sh                          # uses default env file
#   BACKUP_ENV=/path/to/.env ./restore-test.sh # custom env file
#
# Cron example (quarterly: 1st of Jan, Apr, Jul, Oct at 4 AM):
#   0 4 1 1,4,7,10 * /home/deploy/scripts/restore-test.sh >> /var/log/restore-test.log 2>&1
# ==============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ENV="${BACKUP_ENV:-${SCRIPT_DIR}/../stacks/backups/.env}"

if [[ ! -f "$BACKUP_ENV" ]]; then
    echo "ERROR: Environment file not found: $BACKUP_ENV"
    exit 1
fi

# shellcheck source=/dev/null
source "$BACKUP_ENV"

# Temporary directory for the restore. Created in /tmp so it's on a
# tmpfs or local disk, not on the backup target.
RESTORE_DIR="$(mktemp -d /tmp/restore-test.XXXXXXXXXX)"

# ── Logging ──────────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# ── Healthcheck Pinging ──────────────────────────────────────────────────────

hc_ping() {
    local suffix="${1:-}"
    if [[ -n "${HC_PING_RESTORE_TEST:-}" ]]; then
        curl -fsS --max-time 10 --retry 3 "${HC_PING_RESTORE_TEST}${suffix}" > /dev/null 2>&1 || \
            log "WARNING: Failed to ping healthchecks.io"
    fi
}

# ── Cleanup ──────────────────────────────────────────────────────────────────

cleanup() {
    local exit_code=$?

    log "Cleaning up restore directory: $RESTORE_DIR"
    rm -rf "$RESTORE_DIR"

    if [[ $exit_code -ne 0 ]]; then
        log_error "Restore test FAILED with exit code $exit_code"
        hc_ping "/fail"
    fi

    log "Restore test script finished (exit code: $exit_code)"
}

trap cleanup EXIT

# ── Main ─────────────────────────────────────────────────────────────────────

log "=== Starting restore test ==="
hc_ping "/start"

# Export restic environment variables.
export RESTIC_REPOSITORY
export RESTIC_PASSWORD
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"

# ── Step 1: Find the latest snapshot ─────────────────────────────────────────

log "Finding latest snapshot..."
LATEST_SNAPSHOT=$(restic snapshots --json --latest 1 | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['short_id'] if data else '')")

if [[ -z "$LATEST_SNAPSHOT" ]]; then
    log_error "No snapshots found in repository"
    exit 1
fi

log "Latest snapshot: $LATEST_SNAPSHOT"

# ── Step 2: Restore the snapshot ─────────────────────────────────────────────
# Restore to the temporary directory. This downloads and decrypts the
# backup data, proving the full pipeline works end-to-end.

log "Restoring snapshot $LATEST_SNAPSHOT to $RESTORE_DIR"
restic restore "$LATEST_SNAPSHOT" --target "$RESTORE_DIR" --verbose

# ── Step 3: Verify key files exist ───────────────────────────────────────────
# Check that critical directories and files were restored.
# Customize this list based on what your backup includes.

log "Verifying restored files..."

VERIFICATION_FAILED=0

# List of paths to check (relative to the restore root).
# These should match the paths in your BACKUP_PATHS config.
EXPECTED_PATHS=(
    "var/lib/docker/volumes"
)

for expected in "${EXPECTED_PATHS[@]}"; do
    if [[ -e "${RESTORE_DIR}/${expected}" ]]; then
        log "  FOUND: ${expected}"
    else
        log_error "  MISSING: ${expected}"
        VERIFICATION_FAILED=1
    fi
done

# Check that the restore isn't empty (sanity check).
FILE_COUNT=$(find "$RESTORE_DIR" -type f | wc -l)
log "Total files restored: $FILE_COUNT"

if [[ "$FILE_COUNT" -lt 1 ]]; then
    log_error "Restore appears empty — no files found"
    VERIFICATION_FAILED=1
fi

# Report restored size.
RESTORE_SIZE=$(du -sh "$RESTORE_DIR" | cut -f1)
log "Total restore size: $RESTORE_SIZE"

# ── Step 4: Report results ───────────────────────────────────────────────────

if [[ "$VERIFICATION_FAILED" -ne 0 ]]; then
    log_error "=== Restore test FAILED — some expected files are missing ==="
    exit 1
fi

log "=== Restore test PASSED ==="
log "Snapshot $LATEST_SNAPSHOT restored and verified successfully"
log "  Files: $FILE_COUNT"
log "  Size:  $RESTORE_SIZE"

hc_ping ""
