#!/usr/bin/env bash
# ==============================================================================
# Homelab Backup Script
# ==============================================================================
# Backs up Docker volumes and config directories to a restic repository.
# Designed to be run via cron on the host machine.
#
# Features:
#   - Stops database containers before backup for consistency
#   - Tags snapshots with hostname and date for easy identification
#   - Applies retention policy to prune old snapshots
#   - Runs integrity checks after backup
#   - Pings healthchecks.io on success or failure
#
# Prerequisites:
#   - restic installed on the host: https://restic.readthedocs.io/
#   - .env file configured (copy from stacks/backups/.env.example)
#
# Usage:
#   ./backup.sh                          # uses default env file location
#   BACKUP_ENV=/path/to/.env ./backup.sh # custom env file location
#
# Cron example (daily at 3 AM):
#   0 3 * * * /home/deploy/scripts/backup.sh >> /var/log/backup.log 2>&1
# ==============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

# Source environment variables from the backup .env file.
# Default location is alongside the backup stack's docker-compose.yml.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ENV="${BACKUP_ENV:-${SCRIPT_DIR}/../stacks/backups/.env}"

if [[ ! -f "$BACKUP_ENV" ]]; then
    echo "ERROR: Environment file not found: $BACKUP_ENV"
    echo "Copy stacks/backups/.env.example to stacks/backups/.env and configure it."
    exit 1
fi

# shellcheck source=/dev/null
source "$BACKUP_ENV"

# ── Logging ──────────────────────────────────────────────────────────────────

# Prefix every log line with a timestamp for easier debugging in log files.
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# ── Healthcheck Pinging ──────────────────────────────────────────────────────

# Ping healthchecks.io to report status. Failures to ping are logged but
# don't abort the backup — the backup itself is more important.
hc_ping() {
    local suffix="${1:-}"
    if [[ -n "${HC_PING_BACKUP:-}" ]]; then
        curl -fsS --max-time 10 --retry 3 "${HC_PING_BACKUP}${suffix}" > /dev/null 2>&1 || \
            log "WARNING: Failed to ping healthchecks.io (${suffix:-success})"
    fi
}

# ── Error Handling ───────────────────────────────────────────────────────────

# Track containers we stopped so we can restart them even if the backup fails.
STOPPED_CONTAINERS=()

cleanup() {
    local exit_code=$?

    # Always restart containers that were stopped, regardless of backup outcome.
    if [[ ${#STOPPED_CONTAINERS[@]} -gt 0 ]]; then
        log "Restarting stopped containers: ${STOPPED_CONTAINERS[*]}"
        for container in "${STOPPED_CONTAINERS[@]}"; do
            docker start "$container" 2>/dev/null || \
                log_error "Failed to restart container: $container"
        done
    fi

    if [[ $exit_code -ne 0 ]]; then
        log_error "Backup failed with exit code $exit_code"
        hc_ping "/fail"
    fi

    log "Backup script finished (exit code: $exit_code)"
}

# The trap ensures cleanup runs even if the script crashes.
trap cleanup EXIT

# ── Main Backup Flow ─────────────────────────────────────────────────────────

log "=== Starting backup ==="

# Signal healthchecks.io that the backup is starting.
# This lets you detect "backup never started" failures (e.g., cron misconfigured).
hc_ping "/start"

# Export restic environment variables so the restic CLI can find them.
export RESTIC_REPOSITORY
export RESTIC_PASSWORD
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"

# ── Step 1: Stop containers for consistent backups ───────────────────────────
# Databases should be stopped (or have their data dumped) before backing up
# their volume. Otherwise, the backup might capture a partially-written
# data file, leading to corruption on restore.
#
# Alternative: Use pg_dump / redis-cli BGSAVE before backup instead of stopping.
# That's less disruptive but requires more complex scripting.

if [[ -n "${BACKUP_STOP_CONTAINERS:-}" ]]; then
    IFS=',' read -ra containers_to_stop <<< "$BACKUP_STOP_CONTAINERS"
    for container in "${containers_to_stop[@]}"; do
        container="$(echo "$container" | xargs)"  # trim whitespace
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            log "Stopping container: $container"
            docker stop "$container"
            STOPPED_CONTAINERS+=("$container")
        else
            log "Container not running (skipping): $container"
        fi
    done
    # Brief pause to ensure filesystem buffers are flushed.
    sleep 2
fi

# ── Step 2: Run restic backup ────────────────────────────────────────────────
# Parse the comma-separated BACKUP_PATHS into an array.
IFS=',' read -ra backup_paths <<< "$BACKUP_PATHS"

log "Backing up: ${backup_paths[*]}"

# Tags make it easy to find snapshots later:
#   restic snapshots --tag hostname:myserver
restic backup \
    --tag "hostname:$(hostname)" \
    --tag "date:$(date +%Y-%m-%d)" \
    --tag "automated" \
    --verbose \
    "${backup_paths[@]}"

log "Backup completed successfully"

# ── Step 3: Apply retention policy ───────────────────────────────────────────
# "restic forget" marks old snapshots for deletion based on the retention
# policy. --prune actually removes the data. Without --prune, the snapshots
# are forgotten but the data remains (useful for testing retention rules).

log "Applying retention policy"
restic forget \
    --keep-hourly "${RETENTION_HOURLY:-0}" \
    --keep-daily "${RETENTION_DAILY:-7}" \
    --keep-weekly "${RETENTION_WEEKLY:-4}" \
    --keep-monthly "${RETENTION_MONTHLY:-6}" \
    --keep-yearly "${RETENTION_YEARLY:-2}" \
    --prune \
    --verbose

log "Retention policy applied"

# ── Step 4: Verify repository integrity ──────────────────────────────────────
# "restic check" verifies that the repository structure is consistent.
# This catches corruption early, before you need to restore.
# Use --read-data for a full verification (slower, reads all data packs).
# We use the default (metadata-only) check for daily runs.

log "Running repository integrity check"
restic check

log "Integrity check passed"

# ── Step 5: Report success ───────────────────────────────────────────────────

log "=== Backup completed successfully ==="
hc_ping ""
