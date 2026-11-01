#!/usr/bin/env bash

set -euo pipefail

# Start the headless herdr server, create a workspace for $PWD, auto-launch
# the selected agent TUI (AGENTBOX_AGENT: opencode2|claude|codex) in its root pane, then attach the client. The client blocks until
# the user detaches; bwrap then tears down the namespace (killing the server).

herdr server >/dev/null 2>&1 &

socket="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"
for _ in $(seq 1 50); do
  [ -S "$socket" ] && break
  sleep 0.1
done
if [ ! -S "$socket" ]; then
  echo "Error: herdr server did not create its socket at $socket within 5s." >&2
  exit 1
fi

resp=$(herdr workspace create --cwd "$PWD" --no-focus)
root_pane=$(printf '%s' "$resp" | jq -r '.result.root_pane.pane_id // empty')
if [ -z "$root_pane" ]; then
  echo "Error: could not create a herdr workspace for $PWD. Response:" >&2
  printf '%s\n' "$resp" >&2
  exit 1
fi

case "${AGENTBOX_AGENT:-opencode2}" in
  claude) agent=claude ;;
  codex) agent=codex ;;
  *) agent=opencode2 ;;
esac

herdr pane run "$root_pane" "$agent"

herdr
