#!/bin/sh
# Sandbox side of the agentbox git credential proxy (see server.sh).
#
# Configured as git's only credential helper inside the sandbox. Forwards
# "get" and "erase" requests over a unix socket to the host, where the user's
# real credential helper (e.g. Git Credential Manager) answers them. "store"
# is a no-op: the host helper already keeps its own tokens.
sock=${AGENTBOX_GIT_CRED_SOCK:-/run/agentbox/git-cred.sock}

case "${1:-}" in
  get | erase) ;;
  *) cat >/dev/null; exit 0 ;;
esac

[ -S "$sock" ] || { cat >/dev/null; exit 0; }

# -t/-T: allow time for an interactive browser login on the host.
{ printf 'action=%s\n' "$1"; cat; printf '\n'; } |
  socat -t 300 -T 300 - "UNIX-CONNECT:$sock" 2>/dev/null
exit 0
