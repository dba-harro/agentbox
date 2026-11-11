#!/bin/sh
# Sandbox side of the agentbox open-url proxy (see server.sh).
#
# Installed as xdg-open (first on PATH) and as $BROWSER inside the sandbox.
# Forwards http(s) URLs over a unix socket to the host, which opens them in
# the user's default browser. Used e.g. for MCP OAuth logins: the localhost
# callback works because the sandbox shares the host network namespace.
sock=${AGENTBOX_OPEN_URL_SOCK:-/run/agentbox/open-url.sock}
url=${1:-}

if [ -z "$url" ]; then
  echo "usage: xdg-open URL" >&2
  exit 1
fi

case "$url" in
  http://* | https://*) ;;
  *)
    echo "agentbox: only http(s) URLs can be opened in the host browser: $url" >&2
    exit 1
    ;;
esac

if [ -S "$sock" ] &&
  reply=$(printf 'url=%s\n' "$url" | socat -t 10 - "UNIX-CONNECT:$sock" 2>/dev/null) &&
  [ "$reply" = ok ]; then
  echo "agentbox: opened in host browser: $url" >&2
  exit 0
fi

echo "agentbox: could not open the host browser; open this URL manually:" >&2
echo "$url" >&2
exit 1
