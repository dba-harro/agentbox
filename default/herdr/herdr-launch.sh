#!/usr/bin/env bash

set -euo pipefail

# Start the headless herdr server, create a workspace for $PWD, auto-launch
# the selected agent TUI (AGENTBOX_AGENT: opencode2|claude|codex|pi) in its
# root pane, then attach the client. AGENTBOX_AGENT=shell leaves the root pane
# as a plain shell. The client blocks until the user detaches; bwrap then tears
# down the namespace (killing the server).

# Claude only: pick the account (config dir) before the server starts, so every
# pane in this session inherits CLAUDE_CONFIG_DIR. 'personal' is ~/.claude,
# anything else ~/.claude-NAME. --claude-account skips the picker.
if [ "${AGENTBOX_AGENT:-opencode2}" = claude ]; then
  account="${AGENTBOX_CLAUDE_ACCOUNT:-}"
  if [ -z "$account" ]; then
    account=personal
    if [ -t 0 ] && [ -t 1 ] && command -v fzf >/dev/null 2>&1; then
      accounts=(personal work)
      for d in "$HOME"/.claude-*/; do
        n="${d%/}"
        n="${n##*/.claude-}"
        case "$n" in
          shared|personal|work|""|*[!a-z0-9_-]*) continue ;;
        esac
        accounts+=("$n")
      done
      account=$(printf '%s\n' "${accounts[@]}" \
        | fzf --prompt='Claude account > ' --height=~10 --reverse) || account=personal
    fi
  fi
  if [ "$account" = personal ]; then
    claude_dir="$HOME/.claude"
  else
    claude_dir="$HOME/.claude-$account"
  fi
  if [ ! -d "$claude_dir" ]; then
    echo "Error: Claude account dir $claude_dir does not exist on the host." >&2
    echo "Start the sandbox with --claude-account $account to create it." >&2
    exit 1
  fi
  export CLAUDE_CONFIG_DIR="$claude_dir"
fi

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
  pi) agent=pi ;;
  shell) agent= ;;
  *) agent=opencode2 ;;
esac

[ -n "$agent" ] && herdr pane run "$root_pane" "$agent"

herdr
