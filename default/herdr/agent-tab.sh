#!/usr/bin/env bash

set -euo pipefail

# Open a new herdr tab running a harness. Bound in config.toml:
#   agent-tab.sh          -> the harness chosen at sandbox start ($AGENTBOX_AGENT)
#   agent-tab.sh --pick   -> choose one with fzf (run inside a herdr popup)
# "shell" opens a tab with a plain bash and launches nothing.

harnesses=(opencode2 claude codex pi shell)

if [ "${1:-}" = "--pick" ]; then
  agent=$(printf '%s\n' "${harnesses[@]}" |
    fzf --reverse --no-multi --prompt='harness> ' \
      --header='Open a new tab with (Esc cancels)') || exit 0
else
  agent="${AGENTBOX_AGENT:-opencode2}"
fi

case "$agent" in
  opencode2|claude|codex|pi|shell) ;;
  *) agent=opencode2 ;;
esac

resp=$(herdr tab create --focus --label "$agent")
pane=$(printf '%s' "$resp" | jq -r '.result.root_pane.pane_id // empty')
if [ -z "$pane" ]; then
  echo "Error: could not create a herdr tab. Response:" >&2
  printf '%s\n' "$resp" >&2
  exit 1
fi

[ "$agent" = shell ] || herdr pane run "$pane" "$agent"
