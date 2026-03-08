#!/usr/bin/env bash
# ==============================================================================
# Healthchecks.io Ping Utility
# ==============================================================================
# A tiny helper that pings a healthchecks.io check endpoint.
# Used by cron jobs to report success, failure, or start of a task.
#
# Healthchecks.io expects:
#   - GET <ping_url>         → success (task completed OK)
#   - GET <ping_url>/start   → task is starting (detects "never started" failures)
#   - GET <ping_url>/fail    → task failed
#
# Usage:
#   ./healthcheck-ping.sh <uuid>                # report success
#   ./healthcheck-ping.sh <uuid> start          # report start
#   ./healthcheck-ping.sh <uuid> fail           # report failure
#   ./healthcheck-ping.sh <uuid> fail "msg"     # report failure with message body
#
# Cron example (heartbeat ping every 5 minutes):
#   */5 * * * * /home/deploy/scripts/healthcheck-ping.sh xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# ==============================================================================

set -euo pipefail

# ── Argument Parsing ─────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") <uuid> [start|fail] [message]"
    echo ""
    echo "Arguments:"
    echo "  uuid      The healthchecks.io check UUID"
    echo "  start     Signal that the task is starting"
    echo "  fail      Signal that the task failed"
    echo "  message   Optional message body sent with the ping"
    exit 1
fi

UUID="$1"
ACTION="${2:-}"
MESSAGE="${3:-}"

# ── Build the URL ────────────────────────────────────────────────────────────

BASE_URL="https://hc-ping.com"
PING_URL="${BASE_URL}/${UUID}"

case "$ACTION" in
    start)
        PING_URL="${PING_URL}/start"
        ;;
    fail)
        PING_URL="${PING_URL}/fail"
        ;;
    "")
        # No suffix = success ping
        ;;
    *)
        echo "ERROR: Unknown action '$ACTION'. Use 'start', 'fail', or omit."
        exit 1
        ;;
esac

# ── Send the Ping ────────────────────────────────────────────────────────────
# --max-time 10: Don't hang if healthchecks.io is slow.
# --retry 3:     Retry transient failures (network blips).
# -fsS:          Fail silently on HTTP errors, but show curl errors.

if [[ -n "$MESSAGE" ]]; then
    # Send the message as the request body. Healthchecks.io stores this
    # and displays it in the check's log — useful for error details.
    curl -fsS --max-time 10 --retry 3 --data-raw "$MESSAGE" "$PING_URL" > /dev/null 2>&1
else
    curl -fsS --max-time 10 --retry 3 "$PING_URL" > /dev/null 2>&1
fi
