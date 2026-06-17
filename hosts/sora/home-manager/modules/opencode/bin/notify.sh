#!/usr/bin/env bash
# Ciel's notification cannon.
# Usage: ciel-notify prompt|auto <summary> [body]
# Logs to ~/sync/geral/Ciel/notifications/{prompt,auto}.log
# and pops a desktop notification.

set -euo pipefail

SOURCE="${1:-prompt}"
SUMMARY="${2:-}"
BODY="${3:-}"

case "$SOURCE" in
  prompt|auto) ;;
  *)
    echo "usage: ciel-notify prompt|auto <summary> [body]" >&2
    exit 1
    ;;
esac

LOG_DIR="$HOME/sync/geral/Ciel/notifications"
mkdir -p "$LOG_DIR"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $SUMMARY${BODY:+ | $BODY}" >> "$LOG_DIR/$SOURCE.log"

notify-send \
  --app-name="Ciel" \
  --icon=dialog-information \
  --urgency=normal \
  "ciel — $SUMMARY" \
  "${BODY:-}"
