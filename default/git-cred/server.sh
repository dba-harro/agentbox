#!/usr/bin/env bash
# Host side of the agentbox git credential proxy.
#
# sandbox.sh runs this once per connection (socat UNIX-LISTEN,fork EXEC) on
# the HOST, outside the sandbox. It reads one git credential request from the
# sandbox client, and answers it with the host's own credential helpers
# (e.g. Git Credential Manager + GNOME keyring + browser login), so the
# keyring and the D-Bus session bus never have to be exposed to the sandbox.
#
# Request format (from client.sh): "action=<get|erase>" followed by the
# standard git credential attributes, terminated by an empty line or EOF.
#
# Only https requests for hosts matching AGENTBOX_GIT_CRED_HOSTS
# (space-separated shell globs) are answered; everything else gets an empty
# reply, which git treats as "no credential". Tokens are never logged.
set -u

allowed_hosts=${AGENTBOX_GIT_CRED_HOSTS:-"dev.azure.com *.visualstudio.com"}
log_file=${AGENTBOX_GIT_CRED_LOG:-/dev/null}

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$log_file" 2>/dev/null || true
}

action=""
protocol=""
host=""
request=""
while IFS= read -r line; do
  [ -z "$line" ] && break
  case "$line" in
    action=*)
      action=${line#action=}
      continue
      ;;
    protocol=*) protocol=${line#protocol=} ;;
    host=*) host=${line#host=} ;;
  esac
  request+="$line"$'\n'
done

host_allowed=false
# shellcheck disable=SC2254 # unquoted on purpose: entries are glob patterns
for pattern in $allowed_hosts; do
  case "$host" in
    $pattern) host_allowed=true ;;
  esac
done

if [ "$protocol" != https ] || [ "$host_allowed" != true ]; then
  log "deny action=$action protocol=$protocol host=$host"
  exit 0
fi

# Never prompt on the terminal sandbox.sh was started from (it belongs to the
# sandbox TUI); browser-based logins (GCM OAuth via Entra) still work.
export GIT_TERMINAL_PROMPT=0
cd / || exit 0

case "$action" in
  get)
    if ! reply=$(printf '%s' "$request" | git credential fill 2>>"$log_file"); then
      log "get host=$host: no credential"
      exit 0
    fi
    # Forward only the fields git needs; drop anything else a helper returns
    # (e.g. oauth_refresh_token) so long-lived secrets stay on the host.
    printf '%s\n' "$reply" | while IFS= read -r line; do
      case "$line" in
        username=* | password=* | password_expiry_utc=*) printf '%s\n' "$line" ;;
      esac
    done
    log "get host=$host: ok"
    ;;
  erase)
    printf '%s' "$request" | git credential reject 2>>"$log_file" || true
    log "erase host=$host"
    ;;
  *)
    log "ignore action=$action host=$host"
    ;;
esac
exit 0
