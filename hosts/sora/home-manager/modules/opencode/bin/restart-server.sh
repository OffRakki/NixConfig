#!/usr/bin/env bash
# Restart the opencode server and reconnect to the current session.
# Usage: ciel-restart-server [session-id]
# If no session-id given, continues the last session (-c).
# Reads password from /run/secrets/opencodeServerPass.

set -euo pipefail

PASS=$(</run/secrets/opencodeServerPass)
SESSION_FLAG="-c"
SESSION_ARG=""

if [ $# -ge 1 ]; then
  SESSION_FLAG="-s"
  SESSION_ARG="$1"
fi

sleep 1
systemctl --user restart opencode-server
exec opencode attach http://localhost:4096 -p "$PASS" "$SESSION_FLAG" "$SESSION_ARG"
