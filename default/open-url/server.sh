#!/usr/bin/env bash
# Host side of the agentbox open-url proxy.
#
# sandbox.sh runs this once per connection (socat UNIX-LISTEN,fork EXEC) on
# the HOST, outside the sandbox. It reads one "url=<url>" line from the
# sandbox client and opens it in the host's default browser.
#
# Only http:// and https:// URLs are accepted: file:// and custom schemes
# (vscode://, ms-teams://, ...) would launch host applications with
# sandbox-controlled arguments. Full URLs are not logged, since OAuth URLs
# carry state/PKCE values; only the host part is.
set -u

log_file=${AGENTBOX_PROXY_LOG:-/dev/null}
max_len=8192

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$log_file" 2>/dev/null || true
}

reply() {
  printf '%s\n' "$1"
  exit 0
}

IFS= read -r -n "$((max_len + 5))" line || [ -n "$line" ] || reply denied
url=${line#url=}
[ "$url" != "$line" ] || { log "deny: malformed request"; reply denied; }

# Host part for logging: strip scheme, then path/query/fragment, then userinfo.
host=${url#*://}
host=${host%%[/?#]*}
host=${host##*@}
host=${host:0:255}

if [ "${#url}" -gt "$max_len" ]; then
  log "deny host=$host: URL too long"
  reply denied
fi
# http(s) only; no whitespace or control characters anywhere.
if ! [[ $url =~ ^https?://[^[:space:][:cntrl:]]+$ ]]; then
  log "deny host=$host: not a plain http(s) URL"
  reply denied
fi

if command -v xdg-open >/dev/null 2>&1; then
  opener=(xdg-open)
elif [ -n "${BROWSER:-}" ]; then
  opener=("$BROWSER")
else
  log "fail host=$host: no xdg-open or \$BROWSER on the host"
  reply failed
fi

cd / || reply failed
# Detached: xdg-open may block until a newly started browser exits.
setsid "${opener[@]}" "$url" </dev/null >/dev/null 2>&1 &
log "open host=$host"
reply ok
