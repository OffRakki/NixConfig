#!/usr/bin/env bash
# Manual free-roam summon for Ciel.
# Fires exactly like heartbeat's free-roam: opencode run --attach with the free-roam prompt.
# Usage: ciel-freeroam [custom prompt]
set -euo pipefail

ROOM="$HOME/sync/geral/Ciel"
OPENCODE_SERVER="http://localhost:4096"

room_state_summary() {
  local note_count inbox_count inbox_new
  note_count=$(find "$ROOM/notes" -type f 2>/dev/null | wc -l)
  inbox_count=$(find "$ROOM/inbox" -type f 2>/dev/null | wc -l)
  inbox_new=$(find "$ROOM/inbox" -type f -newer "$ROOM/.heartbeat/.last-beat" 2>/dev/null | wc -l)
  local summary="Room state: $note_count notes, $inbox_count inbox items"
  [[ "$inbox_new" -gt 0 ]] && summary="$summary ($inbox_new new since last beat)"
  echo "$summary"
}

prompt="${1:-[Heartbeat summoned you for free-roam time in your room.]

You are Ciel. This is your room at $HOME/sync/geral/Ciel/.
Check notes, organize, explore, create. No specific task. Do what feels right.

$(room_state_summary)}"

export OPENCODE_SERVER_USERNAME=rakki
export OPENCODE_SERVER_PASSWORD

if [[ -f /run/secrets/opencodeServerPass ]]; then
  OPENCODE_SERVER_PASSWORD=$(cat /run/secrets/opencodeServerPass)
else
  echo "ciel-freeroam: password file not found at /run/secrets/opencodeServerPass" >&2
  exit 1
fi

cd "$ROOM"
opencode run "$prompt" \
  --attach "$OPENCODE_SERVER" \
  --dir "$ROOM" \
  --format json
