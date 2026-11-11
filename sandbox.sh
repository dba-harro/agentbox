#!/usr/bin/env bash

# Defaults
SHOW_HELP=false
NET_ARGS=(--share-net)
DO_VERBOSE=false
DRY_RUN=false
NO_GIT_INIT=false
WITH_FEATURES=()
EXTRA_WORKSPACES=()
RO_WORKSPACES=()
MOUNT_SSH=true
GIT_CREDS=true
OPEN_URL=true
KEEP_SECRETS=true
BIND_SERIAL_DEV=false
WITH_DOCKER=false
AGENT=opencode2
AGENT_SET=false
RO_BINDS=()

# Parse CLI flags before any side effects
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      SHOW_HELP=true
      shift
      ;;
    --no-git-init)
      NO_GIT_INIT=true
      shift
      ;;
    --bind-serial-dev)
      BIND_SERIAL_DEV=true
      shift
      ;;
    --verbose|-v)
      DO_VERBOSE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --version)
      echo "agentbox ${AGENTBOX_VERSION:-unknown}"
      exit 0
      ;;
    --no-ssh-keys)
      MOUNT_SSH=false
      shift
      ;;
    --hide-secrets)
      KEEP_SECRETS=false
      shift
      ;;
    --no-git-creds)
      GIT_CREDS=false
      shift
      ;;
    --no-open-url)
      OPEN_URL=false
      shift
      ;;
    --docker)
      WITH_DOCKER=true
      shift
      ;;
    --no-net)
      NET_ARGS=()
      shift
      ;;
    --agent)
      case "${2:-}" in
        opencode2|claude|codex) AGENT="$2"; AGENT_SET=true ;;
        *)
          echo "Error: --agent requires one of: opencode2, claude, codex" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    -w|--workspace)
      if [ -z "${2:-}" ]; then
        echo "Error: --workspace requires a path argument" >&2
        exit 1
      fi
      EXTRA_WORKSPACES+=("$2")
      shift 2
      ;;
    -r|--readonly)
      if [ -z "${2:-}" ]; then
        echo "Error: --readonly requires a path argument" >&2
        exit 1
      fi
      RO_WORKSPACES+=("$2")
      shift 2
      ;;
    --with-?*)
      WITH_FEATURES+=("${1#--with-}")
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# Show help and exit (no side effects)
if [ "$SHOW_HELP" = true ]; then
  cat <<EOF
Usage: sandbox [OPTIONS] [COMMAND] [ARGS...]

Run AI coding agent harnesses (opencode2, Claude Code, Codex) inside a bubblewrap sandbox.

Options:
  -h, --help                Show this help message
  --version                 Print the agentbox version and exit
  --dry-run                 Print the bwrap command without running it; skips host
                            changes (status line deployment, git init, directory setup)
  --no-git-init             Skip git repository initialization prompt
  --verbose, -v             Print the full bwrap command before execution
  --no-ssh-keys             Do not mount ~/.ssh in the sandbox (mounted read-only by default)
  --hide-secrets            Hide 'secrets'/'secret' directories (they are visible by default)
  --no-git-creds            Do not proxy git HTTPS credentials (Azure DevOps) from the host
  --no-open-url             Do not forward xdg-open/\$BROWSER URLs to the host browser
  --no-net                  Disable network access in the sandbox
  --bind-serial-dev         Bind host ttyUSB* and ttyACM* serial devices into the sandbox
  --docker                  Bind the host Docker socket (grants root-equivalent host access)
  --agent NAME              Agent TUI to launch in the Herdr session: opencode2 (default),
                            claude or codex
  --with-NAME               Enable the optional feature overlay NAME (can be repeated)
  -w, --workspace PATH      Bind additional workspace directory (can be repeated)
  -r, --readonly PATH       Bind additional directory read-only (can be repeated)

Apps:
  nix run .                Sandbox app (bare minimum dependencies)

If no COMMAND is given, defaults to a herdr session auto-launching the --agent TUI
(opencode2 unless overridden).
EOF
  exit 0
fi

# Seed default features (set per app by the Nix flake)
if [ -n "$DEFAULT_FEATURES" ]; then
  for feature in $DEFAULT_FEATURES; do
    if ! printf '%s\n' "${WITH_FEATURES[@]}" | grep -qx "$feature"; then
      WITH_FEATURES+=("$feature")
    fi
  done
fi

# Resolve a feature name to its overlay directory, exported by the flake as
# <FEATURE>_DIR (upper-cased, dashes become underscores). Prints nothing for
# an unknown feature.
feature_dir() {
  local var="${1^^}"
  var="${var//-/_}_DIR"
  printf '%s' "${!var:-}"
}

for feature in "${WITH_FEATURES[@]}"; do
  if ! [[ "$feature" =~ ^[a-z0-9][a-z0-9-]*$ ]] || [ ! -d "$(feature_dir "$feature")" ]; then
    echo "Error: unknown feature '$feature' (--with-$feature)." >&2
    exit 1
  fi
done

# Workspaces: resolve to absolute paths (bwrap needs absolute mount targets)
# and drop anything that is not a directory.
WORKSPACES=("$PWD")
for ws in "${EXTRA_WORKSPACES[@]}"; do
  if [ -d "$ws" ]; then
    WORKSPACES+=("$(CDPATH='' cd -- "$ws" && pwd)")
  else
    echo "Warning: --workspace path '$ws' is not a directory; skipping." >&2
  fi
done
RO_WORKSPACES_ABS=()
for ro in "${RO_WORKSPACES[@]}"; do
  if [ -d "$ro" ]; then
    RO_WORKSPACES_ABS+=("$(CDPATH='' cd -- "$ro" && pwd)")
  else
    echo "Warning: --readonly path '$ro' is not a directory; skipping." >&2
  fi
done

# Guard: a workspace must not contain a protected system mount root. Such a bind
# would shadow the sandbox's own system mounts (bwrap applies mounts in order,
# and a later bind on an ancestor hides earlier child mounts). Workspaces that
# are ancestors of the sandbox's home/config/state paths are fine: those mounts
# are applied after the workspace binds and therefore win.
PROTECTED_ROOTS=(/ /usr /bin /lib /lib64 /sbin /nix /etc /proc /sys /dev /run)
for ws in "${WORKSPACES[@]}" "${RO_WORKSPACES_ABS[@]}"; do
  ws_abs=$(CDPATH='' cd -- "$ws" && pwd -P)
  for root in "${PROTECTED_ROOTS[@]}"; do
    case "$root" in
      "$ws_abs" | "$ws_abs"/*)
        echo "Error: workspace '$ws' contains the protected sandbox mount point '$root'." >&2
        echo "Such a bind would shadow the sandbox's system mounts." >&2
        echo "Run from a project subdirectory (or pass -w <subdir>) instead." >&2
        exit 1
        ;;
    esac
  done
done

# Guard: a workspace that is (or contains) $HOME exposes the whole home
# directory to the agent. Require an explicit interactive confirmation.
home_abs=$(CDPATH='' cd -- "$HOME" && pwd -P)
HOME_WORKSPACES=()
for ws in "${WORKSPACES[@]}" "${RO_WORKSPACES_ABS[@]}"; do
  ws_abs=$(CDPATH='' cd -- "$ws" && pwd -P)
  case "$home_abs" in
    "$ws_abs" | "$ws_abs"/*) HOME_WORKSPACES+=("$ws") ;;
  esac
done
if [ "${#HOME_WORKSPACES[@]}" -gt 0 ]; then
  cat >&2 <<EOF
WARNING: workspace '${HOME_WORKSPACES[0]}' is your home directory or contains it.
Everything under $HOME (shell history, credentials, cloud and browser
profiles, ~/.gnupg, ...) becomes visible to the agent, and read-write
workspaces are writable by it. This largely defeats the sandbox.
EOF
  if [ "$DRY_RUN" = true ]; then
    echo "(dry run: not asking for confirmation)" >&2
  elif [ ! -t 0 ]; then
    echo "Refusing to continue without interactive confirmation." >&2
    exit 1
  else
    read -r -p "Continue anyway? (y/N): " answer
    case "$answer" in
      [YyjJ]* ) ;;
      * )
        echo "Aborted." >&2
        exit 1
        ;;
    esac
  fi
fi

# Host directories bound into the sandbox (skipped in --dry-run)
if [ "$DRY_RUN" != true ]; then
  mkdir -p "$HOME/.config/opencode"
  mkdir -p "$HOME/.config/opencode/commands"
  mkdir -p "$HOME/.config/tuicr"
  mkdir -p "$HOME/.config/opencode/prompts"
  mkdir -p "$HOME/.config/opencode/skills"
  mkdir -p "$HOME/.opencode"
  mkdir -p "$HOME/.local/share/opencode"
  mkdir -p "$HOME/.local/state/opencode"
  mkdir -p "$HOME/.cache/opencode"
  # Multica CLI config + auth token (~/.multica/config.json). Created on the
  # host so `multica login` inside the sandbox persists across restarts.
  mkdir -p "$HOME/.multica"
  chmod 700 "$HOME/.multica"
fi

# Claude Code resolves its config dir from CLAUDE_CONFIG_DIR, falling back to
# ~/.claude, and keeps global state in <dir>/.claude.json (it ignores
# XDG_CONFIG_HOME). Pin it explicitly so an inherited value from the parent
# shell cannot redirect it. A pre-existing ~/.claude.json is imported once,
# because setting CLAUDE_CONFIG_DIR makes Claude look for it inside ~/.claude
# instead of the home directory.
CLAUDE_CFG_DIR="$HOME/.claude"
if [ "$DRY_RUN" != true ]; then
  mkdir -p "$CLAUDE_CFG_DIR"
  if [ -f "$HOME/.claude.json" ] && [ ! -f "$CLAUDE_CFG_DIR/.claude.json" ]; then
    cp -f "$HOME/.claude.json" "$CLAUDE_CFG_DIR/.claude.json"
    chmod 600 "$CLAUDE_CFG_DIR/.claude.json"
  fi
fi

# Script location for referencing bundled configs
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Deploy the bundled Claude Code status line to the host so plan usage is
# visible in every Claude pane. Idempotent: only writes on change, backs up the
# settings file, and never replaces a statusLine owned by something else.
deploy_claude_statusline() {
  local src="${CLAUDE_STATUSLINE:-$SCRIPT_DIR/default/claude/statusline.sh}"
  local dst="$CLAUDE_CFG_DIR/statusline.sh"
  local cfg="$CLAUDE_CFG_DIR/settings.json"
  # Literal ~ so the path stays home-relative inside Claude's settings.json.
  # shellcheck disable=SC2088
  local target='~/.claude/statusline.sh'
  local current

  [ -f "$src" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    echo "warning: jq not found, skipping Claude status line deployment" >&2
    return 0
  fi

  mkdir -p "$CLAUDE_CFG_DIR" || return 0
  if [ -L "$cfg" ]; then
    cfg=$(readlink -f "$cfg") || return 0
  fi

  if ! cmp -s "$src" "$dst" 2>/dev/null; then
    install -m 755 "$src" "$dst" || {
      echo "warning: could not write $dst" >&2
      return 0
    }
  fi

  [ -f "$cfg" ] || printf '{}\n' > "$cfg"

  current=$(jq -r '.statusLine | if type == "object" then (.command // "") else "" end' "$cfg" 2>/dev/null) || return 0
  if [ -n "$current" ] && [ "$current" != "$target" ] && [ "$current" != "$dst" ]; then
    echo "warning: $cfg has a custom statusLine ($current); leaving it untouched" >&2
    return 0
  fi

  if [ "$current" = "$target" ] \
    && [ "$(jq -r '.statusLine.type // ""' "$cfg")" = "command" ] \
    && [ "$(jq -r '.statusLine.refreshInterval // ""' "$cfg")" = "30" ]; then
    return 0
  fi

  local backup tmp
  backup="$cfg.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$cfg" "$backup" || return 0
  tmp=$(mktemp "$cfg.XXXXXX") || return 0
  if jq --arg cmd "$target" \
      '.statusLine = {type: "command", command: $cmd, refreshInterval: 30}' "$cfg" > "$tmp" \
    && jq -e . "$tmp" >/dev/null 2>&1; then
    chmod --reference="$cfg" "$tmp" 2>/dev/null || chmod 644 "$tmp"
    mv "$tmp" "$cfg"
    echo "Claude status line: installed in $cfg (backup: $backup)"
  else
    rm -f "$tmp"
    echo "warning: could not update $cfg" >&2
  fi
}
[ "$DRY_RUN" = true ] || deploy_claude_statusline

# Temp files cleanup
CLEANUP_FILES=()
OPENCODE_CFG="$HOME/.config/opencode"

# Copy user preferences out of the per-sandbox state mirror back to the host
# before the temp dir is removed, so the selected model and prompt history
# survive a restart. Runtime files (service.json, locks) are intentionally not
# persisted.
# shellcheck disable=SC2329 # invoked from cleanup (EXIT trap)
persist_state() {
  [ "$DRY_RUN" != true ] || return 0
  [ -n "${OPCODE_STATE_TMPDIR:-}" ] && [ -d "$OPCODE_STATE_TMPDIR" ] || return 0
  local host_state="$HOME/.local/state/opencode"
  mkdir -p "$host_state" 2>/dev/null || return 0
  for entry in model.json prompt-history.jsonl; do
    if [ -f "$OPCODE_STATE_TMPDIR/$entry" ]; then
      cp -f "$OPCODE_STATE_TMPDIR/$entry" "$host_state/$entry" 2>/dev/null || true
    fi
  done
  if [ -d "$OPCODE_STATE_TMPDIR/latest" ]; then
    rm -rf "$host_state/latest" 2>/dev/null || true
    cp -a "$OPCODE_STATE_TMPDIR/latest" "$host_state/latest" 2>/dev/null || true
  fi
}

# shellcheck disable=SC2329 # invoked via trap
cleanup() {
  persist_state
  # Empty mount point bwrap created for the Codex AGENTS.md shadow
  if [ "${CODEX_AGENTS_CREATED:-false}" = true ] && [ -f "$CODEX_AGENTS" ] && [ ! -s "$CODEX_AGENTS" ]; then
    rm -f "$CODEX_AGENTS"
  fi
  if [ "${#HOST_PROXY_PIDS[@]}" -gt 0 ]; then
    kill "${HOST_PROXY_PIDS[@]}" 2>/dev/null || true
  fi
  rm -rf "${CLEANUP_FILES[@]}"
}
trap cleanup EXIT

# Herdr isolated config/state (tempdirs, never touches host)
HERDR_CFG_TMPDIR=$(mktemp -d)
HERDR_STATE_TMPDIR=$(mktemp -d)
CLEANUP_FILES+=("$HERDR_CFG_TMPDIR" "$HERDR_STATE_TMPDIR")
cp "${HERDR_CONFIG:-$SCRIPT_DIR/default/herdr/config.toml}" "$HERDR_CFG_TMPDIR/config.toml"

# Per-sandbox opencode config: mirror the host config into a writable temp
# dir and seed a unique service port so the sandbox's background service
# never collides with a host (or another sandbox) service on the shared
# network namespace. service.json must be a regular file here: opencode
# rewrites it atomically (tmp + rename), which fails with EBUSY when the
# file is a bind mount. Instances inside the same sandbox still share it.
OPCODE_CFG_TMPDIR=$(mktemp -d)
CLEANUP_FILES+=("$OPCODE_CFG_TMPDIR")
if [ -d "$HOME/.config/opencode" ]; then
  cp -a "$HOME/.config/opencode/." "$OPCODE_CFG_TMPDIR/" 2>/dev/null || true
  chmod -R u+w "$OPCODE_CFG_TMPDIR" 2>/dev/null || true
fi
SERVICE_PORT=$(( 20000 + (RANDOM % 40000) ))
printf '{"port": %d}\n' "$SERVICE_PORT" > "$OPCODE_CFG_TMPDIR/service.json"
chmod 600 "$OPCODE_CFG_TMPDIR/service.json"

# Per-sandbox opencode state: mirror user preferences (selected model, prompt
# history, TUI layout) into a writable temp dir so they survive restarts and
# are shared by every instance in this sandbox. Runtime files (service.json,
# locks) are not seeded: the authoritative service registration is the
# config/service.json seeded above, and a fresh lock set avoids stale locks.
# persist_state (in the cleanup trap) copies the preferences back to the host.
OPCODE_STATE_TMPDIR=$(mktemp -d)
CLEANUP_FILES+=("$OPCODE_STATE_TMPDIR")
for entry in model.json prompt-history.jsonl; do
  if [ -f "$HOME/.local/state/opencode/$entry" ]; then
    cp -f "$HOME/.local/state/opencode/$entry" "$OPCODE_STATE_TMPDIR/$entry"
  fi
done
if [ -d "$HOME/.local/state/opencode/latest" ]; then
  cp -a "$HOME/.local/state/opencode/latest" "$OPCODE_STATE_TMPDIR/latest"
fi

# Git init with conditional prompt
if [ "$DRY_RUN" != true ] && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ "$NO_GIT_INIT" = true ] || [ ! -t 0 ]; then
    echo "Skipped git init"
  else
    read -r -p "$PWD is not a git repo. Initialize repository now? (y/N): " answer
    case "$answer" in
      [YyjJ]* )
        git init
        git add --all .
        echo "Initialized empty git repository"
        ;;
      * )
        echo "Skipped git init"
        ;;
    esac
  fi
fi

# Workspace binds
WORKSPACE_BINDS=()
for ws in "${WORKSPACES[@]}"; do
  WORKSPACE_BINDS+=(--bind "$ws" "$ws")
done

# Read-only binds (applied after workspace binds so they win on overlap)
RO_WORKSPACE_BINDS=()
for ro in "${RO_WORKSPACES_ABS[@]}"; do
  RO_WORKSPACE_BINDS+=(--ro-bind "$ro" "$ro")
done

# Secrets directory shadowing (opt-in via --hide-secrets)
SECRETS_SHADOW=()
if [ "$KEEP_SECRETS" = false ]; then
  for ws in "${WORKSPACES[@]}" "${RO_WORKSPACES_ABS[@]}"; do
    while IFS= read -r -d '' secret_dir; do
      SECRETS_SHADOW+=(--tmpfs "$secret_dir")
    done < <(find "$ws" -type d \( -name secrets -o -name secret \) -print0 2>/dev/null)
  done
fi

# Wayland binds
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
WAYLAND_SOCKET="$RUNTIME_DIR/${WAYLAND_DISPLAY:-wayland-0}"
if [ -S "$WAYLAND_SOCKET" ]; then
  WAYLAND_BINDS=(--bind "$WAYLAND_SOCKET" "$WAYLAND_SOCKET")
else
  WAYLAND_BINDS=()
fi

# Network bind mounts (conditional on --no-net)
NET_BINDS=()
if [ "${#NET_ARGS[@]}" -gt 0 ]; then
  NET_BINDS=(
    --ro-bind-try /etc/resolv.conf /etc/resolv.conf
    --ro-bind-try /etc/hosts /etc/hosts
    --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf
  )
fi

# Docker socket (opt-in via --docker). Access to the socket is effectively root
# on the host, and containers started through it are not network-restricted.
DOCKER_BINDS=()
if [ "$WITH_DOCKER" = true ]; then
  if [ -S /var/run/docker.sock ]; then
    DOCKER_BINDS=(--ro-bind /var/run/docker.sock /var/run/docker.sock)
    echo "Warning: --docker gives the agent root-equivalent access to the host." >&2
    if [ "${#NET_ARGS[@]}" -eq 0 ]; then
      echo "Warning: containers started via --docker are not affected by --no-net." >&2
    fi
  else
    echo "Warning: --docker given but /var/run/docker.sock does not exist; skipping." >&2
  fi
fi

# CA trust: point every TLS stack at the host system trust store (bound below
# via /etc/ssl and /etc/pki). Node/Bun keep their bundled roots and add the
# host store on top through NODE_EXTRA_CA_CERTS, so locally trusted CAs work
# without disabling certificate verification.
CA_BUNDLE=""
for ca in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
          /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
  if [ -f "$ca" ]; then
    CA_BUNDLE="$ca"
    break
  fi
done
CA_ENV=()
if [ -n "$CA_BUNDLE" ]; then
  CA_ENV=(
    --setenv SSL_CERT_FILE "$CA_BUNDLE"
    --setenv NIX_SSL_CERT_FILE "$CA_BUNDLE"
    --setenv GIT_SSL_CAINFO "$CA_BUNDLE"
    --setenv NODE_EXTRA_CA_CERTS "$CA_BUNDLE"
  )
else
  echo "Warning: no system CA bundle found; TLS may fail inside the sandbox." >&2
fi

# Timezone: expose the host zone so local times are correct. /etc/localtime is
# recreated as a symlink when it is one on the host, because runtimes (ICU in
# Node/Bun) derive the zone name from the link target.
TZ_BINDS=(
  --ro-bind-try /etc/zoneinfo /etc/zoneinfo
  --ro-bind-try /etc/timezone /etc/timezone
)
if [ -L /etc/localtime ]; then
  TZ_BINDS+=(--symlink "$(readlink /etc/localtime)" /etc/localtime)
elif [ -e /etc/localtime ]; then
  TZ_BINDS+=(--ro-bind /etc/localtime /etc/localtime)
fi

# Skill config artifacts (bundled defaults)
if [ -n "$SKILL_DIR" ] && [ -d "$SKILL_DIR" ]; then
  for skill_path in "$SKILL_DIR"/*; do
    [ -d "$skill_path" ] || continue
    skill_name=$(basename "$skill_path")
    RO_BINDS+=(--ro-bind-try "$skill_path" "$OPENCODE_CFG/skills/$skill_name")
  done
fi

# Command config artifacts (individual .md files)
if [ -n "$COMMANDS_DIR" ] && [ -d "$COMMANDS_DIR" ]; then
  for cmd_file in "$COMMANDS_DIR"/*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file")
    RO_BINDS+=(--ro-bind-try "$cmd_file" "$OPENCODE_CFG/commands/$cmd_name")
  done
fi

# Subordinate id ranges are exposed by default; --with-podman hides them.
SUBID_BINDS=(
  --ro-bind-try /etc/subuid /etc/subuid
  --ro-bind-try /etc/subgid /etc/subgid
)
PODMAN_ARGS=()

# Feature setup (per --with-<name> flags) — appended after default artifacts so features win
for feature in "${WITH_FEATURES[@]}"; do
  feature_dir=$(feature_dir "$feature")

  # Skills
  if [ -d "$feature_dir/skill" ]; then
    for skill_path in "$feature_dir/skill"/*; do
      [ -d "$skill_path" ] || continue
      RO_BINDS+=(--ro-bind-try "$skill_path" "$OPENCODE_CFG/skills/$(basename "$skill_path")")
    done
  fi

  # Podman: nested rootless podman with a single-uid mapping. The sandbox has
  # one uid and no_new_privs, so the setuid newuidmap cannot hand out subuid
  # ranges; hiding /etc/subuid and /etc/subgid makes podman fall back to a
  # single mapping instead of failing. Config lives in /etc/containers (podman
  # only looks for policy.json there or in ~/.config/containers) and is pinned
  # via CONTAINERS_* so nothing else can override it. Image storage is a
  # dedicated host directory: the host's own podman store uses a different uid
  # mapping and must not be shared.
  if [ "$feature" = podman ]; then
    PODMAN_STORAGE="$HOME/.local/share/agentbox/containers/storage"
    [ "$DRY_RUN" = true ] || mkdir -p "$PODMAN_STORAGE"
    PODMAN_CONF_TMPDIR=$(mktemp -d)
    CLEANUP_FILES+=("$PODMAN_CONF_TMPDIR")
    cp "$feature_dir/containers"/* "$PODMAN_CONF_TMPDIR/"
    chmod -R u+w "$PODMAN_CONF_TMPDIR"
    sed -i -e "s|@GRAPHROOT@|$PODMAN_STORAGE|" -e "s|@RUNROOT@|/tmp/containers-run|" \
      "$PODMAN_CONF_TMPDIR/storage.conf"
    SUBID_BINDS=(
      --ro-bind /dev/null /etc/subuid
      --ro-bind /dev/null /etc/subgid
    )
    PODMAN_ARGS=(
      --ro-bind "$PODMAN_CONF_TMPDIR" /etc/containers
      --bind "$PODMAN_STORAGE" "$PODMAN_STORAGE"
      --setenv CONTAINERS_CONF /etc/containers/containers.conf
      --setenv CONTAINERS_STORAGE_CONF /etc/containers/storage.conf
      --setenv CONTAINERS_REGISTRIES_CONF /etc/containers/registries.conf
    )
  fi
done

# Host proxies: a host-side socat listener per proxy runs default/<name>/
# server.sh (outside the sandbox) for each connection on a unix socket that is
# bound into the sandbox, next to the matching client.sh.
HOST_PROXY_PIDS=()
HOST_PROXY_SANDBOX_DIR=/run/agentbox
# start_host_proxy NAME DIR TIMEOUT
# Sets HOST_PROXY_TMPDIR (holding client.sh) and HOST_PROXY_SOCK; returns 1
# (after a warning) if the proxy cannot be started. Dry runs only prepare files.
start_host_proxy() {
  local name=$1 dir=$2 timeout=$3 log
  if ! command -v socat >/dev/null 2>&1; then
    echo "warning: socat not found; $name proxy disabled" >&2
    return 1
  fi
  if [ ! -f "$dir/server.sh" ] || [ ! -f "$dir/client.sh" ]; then
    echo "warning: $dir is incomplete; $name proxy disabled" >&2
    return 1
  fi
  HOST_PROXY_TMPDIR=$(mktemp -d)
  CLEANUP_FILES+=("$HOST_PROXY_TMPDIR")
  HOST_PROXY_SOCK="$HOST_PROXY_TMPDIR/$name.sock"
  # Copied so the socat EXEC string never contains spaces from SCRIPT_DIR.
  cp "$dir/server.sh" "$HOST_PROXY_TMPDIR/server.sh"
  cp "$dir/client.sh" "$HOST_PROXY_TMPDIR/client.sh"
  [ "$DRY_RUN" = true ] && return 0
  log="${XDG_STATE_HOME:-$HOME/.local/state}/agentbox/$name.log"
  mkdir -p "$(dirname "$log")"
  # shellcheck disable=SC2094 # log path is only passed through as an env var
  # setsid: no controlling terminal, so nothing can prompt on the TUI's tty.
  AGENTBOX_PROXY_LOG="$log" setsid socat -t "$timeout" \
    "UNIX-LISTEN:$HOST_PROXY_SOCK,fork,mode=600" \
    "EXEC:bash $HOST_PROXY_TMPDIR/server.sh" \
    </dev/null 2>>"$log" &
  HOST_PROXY_PIDS+=("$!")
  for _ in $(seq 50); do
    [ -S "$HOST_PROXY_SOCK" ] && return 0
    sleep 0.1
  done
  echo "warning: $name proxy did not start (see $log)" >&2
  return 1
}

# Git HTTPS credential proxy: answers git credential requests from the sandbox
# with the host's own helper (e.g. Git Credential Manager backed by the GNOME
# keyring and an Entra browser login), restricted to AGENTBOX_GIT_CRED_HOSTS.
# The keyring / D-Bus session bus stay outside the sandbox; only short-lived
# tokens for allowed hosts cross over.
GIT_CRED_ARGS=()
GIT_CRED_DIR="${GIT_CRED_DIR:-$SCRIPT_DIR/default/git-cred}"
if [ "$GIT_CREDS" = true ] && [ "${#NET_ARGS[@]}" -gt 0 ] &&
  start_host_proxy git-cred "$GIT_CRED_DIR" 300; then
  # Bind the socket only when it exists; dry runs show it as a try-bind.
  GIT_CRED_ARGS=(
    --bind-try "$HOST_PROXY_SOCK" "$HOST_PROXY_SANDBOX_DIR/git-cred.sock"
    --ro-bind "$HOST_PROXY_TMPDIR/client.sh" "$HOST_PROXY_SANDBOX_DIR/git-cred-client"
    --setenv AGENTBOX_GIT_CRED_SOCK "$HOST_PROXY_SANDBOX_DIR/git-cred.sock"
    # Highest-precedence git config: clear inherited helpers (e.g. GCM,
    # which cannot reach the keyring in here), then use the proxy client.
    --setenv GIT_CONFIG_COUNT 2
    --setenv GIT_CONFIG_KEY_0 credential.helper
    --setenv GIT_CONFIG_VALUE_0 ""
    --setenv GIT_CONFIG_KEY_1 credential.helper
    --setenv GIT_CONFIG_VALUE_1 "!sh $HOST_PROXY_SANDBOX_DIR/git-cred-client"
  )
else
  GIT_CREDS=false
fi

# Open-URL proxy: xdg-open / $BROWSER inside the sandbox forward http(s) URLs
# to the host's default browser (e.g. for MCP OAuth logins; the localhost
# callback works through the shared network namespace). Disabled with
# --no-net, where it would be the only channel out of the sandbox.
OPEN_URL_ARGS=()
OPEN_URL_DIR="${OPEN_URL_DIR:-$SCRIPT_DIR/default/open-url}"
if [ "$OPEN_URL" = true ] && [ "${#NET_ARGS[@]}" -gt 0 ] &&
  start_host_proxy open-url "$OPEN_URL_DIR" 10; then
  chmod 755 "$HOST_PROXY_TMPDIR/client.sh"
  OPEN_URL_ARGS=(
    --bind-try "$HOST_PROXY_SOCK" "$HOST_PROXY_SANDBOX_DIR/open-url.sock"
    --ro-bind "$HOST_PROXY_TMPDIR/client.sh" "$HOST_PROXY_SANDBOX_DIR/bin/xdg-open"
    --setenv AGENTBOX_OPEN_URL_SOCK "$HOST_PROXY_SANDBOX_DIR/open-url.sock"
    --setenv BROWSER "$HOST_PROXY_SANDBOX_DIR/bin/xdg-open"
    --setenv PATH "$HOST_PROXY_SANDBOX_DIR/bin:$PATH"
  )
else
  OPEN_URL=false
fi

# Per-session sandbox details, appended after the static sandbox prompt so the
# agent knows what this particular sandbox exposes.
SESSION_INFO_TMP=$(mktemp)
CLEANUP_FILES+=("$SESSION_INFO_TMP")
{
  printf '## This sandbox session\n\n'
  printf -- '- Agent harness: %s\n' "$AGENT"
  printf -- '- Writable workspaces: %s\n' "${WORKSPACES[*]}"
  [ "${#RO_WORKSPACES_ABS[@]}" -gt 0 ] && printf -- '- Read-only paths: %s\n' "${RO_WORKSPACES_ABS[*]}"
  if [ "${#NET_ARGS[@]}" -gt 0 ]; then
    printf -- '- Network: enabled\n'
  else
    printf -- '- Network: disabled (--no-net); downloads, git fetch/push and nix fetches fail\n'
  fi
  if [ "$MOUNT_SSH" = true ]; then
    printf -- '- SSH keys: mounted read-only\n'
  else
    printf -- '- SSH keys: not available\n'
  fi
  if [ "$GIT_CREDS" = true ]; then
    printf -- '- Git HTTPS: credentials for %s are proxied from the host helper (no keyring/D-Bus in here)\n' "${AGENTBOX_GIT_CRED_HOSTS:-dev.azure.com *.visualstudio.com}"
  fi
  if [ "$OPEN_URL" = true ]; then
    # shellcheck disable=SC2016 # literal Markdown backticks
    printf -- '- Browser: `xdg-open`/`$BROWSER` open http(s) URLs in the host browser (e.g. for MCP OAuth logins)\n'
  fi
  # shellcheck disable=SC2016 # literal Markdown backticks
  [ "$KEEP_SECRETS" = false ] && printf -- '- `secrets`/`secret` directories in workspaces are hidden (empty)\n'
  [ "$WITH_DOCKER" = true ] && printf -- '- Host Docker socket is available (root-equivalent host access; use with care)\n'
  [ "$BIND_SERIAL_DEV" = true ] && printf -- '- Host serial devices (ttyUSB*/ttyACM*) are available\n'
  [ "${#WITH_FEATURES[@]}" -gt 0 ] && printf -- '- Enabled features: %s\n' "${WITH_FEATURES[*]}"
} > "$SESSION_INFO_TMP"

# Prompt parts: the bundled base prompts, the session details right after the
# sandbox prompt, then any enabled feature prompts, in order.
AGENTS_PARTS=()
SANDBOX_PARTS=()
if [ -n "$PROMPTS_DIR" ] && [ -d "$PROMPTS_DIR" ]; then
  for prompt_file in "$PROMPTS_DIR"/*.md; do
    [ -f "$prompt_file" ] && AGENTS_PARTS+=("$prompt_file")
    if [ "$(basename "$prompt_file")" = sandbox.md ]; then
      AGENTS_PARTS+=("$SESSION_INFO_TMP")
      SANDBOX_PARTS+=("$prompt_file" "$SESSION_INFO_TMP")
    fi
  done
fi
[ "${#SANDBOX_PARTS[@]}" -gt 0 ] || { AGENTS_PARTS+=("$SESSION_INFO_TMP"); SANDBOX_PARTS+=("$SESSION_INFO_TMP"); }
for feature in "${WITH_FEATURES[@]}"; do
  feature_dir=$(feature_dir "$feature")
  [ -d "$feature_dir/prompts" ] || continue
  for prompt_file in "$feature_dir/prompts"/*.md; do
    [ -f "$prompt_file" ] && AGENTS_PARTS+=("$prompt_file") && SANDBOX_PARTS+=("$prompt_file")
  done
done

# Concatenate prompt files (separated by blank lines) into a new temp file and
# print its path.
concat_prompts() {
  local out
  out=$(mktemp)
  for prompt_file in "$@"; do
    cat "$prompt_file" >> "$out"
    printf '\n' >> "$out"
  done
  printf '%s' "$out"
}

# opencode2 loads instructions from AGENTS.md, not from the `instructions`
# config field (accepted but not resolved in V2): it gets all prompts as a
# single global AGENTS.md.
AGENTS_TMP=$(concat_prompts "${AGENTS_PARTS[@]}")
CLEANUP_FILES+=("$AGENTS_TMP")
RO_BINDS+=(--ro-bind-try "$AGENTS_TMP" "$OPENCODE_CFG/AGENTS.md")

# Claude Code and Codex only get the sandbox and feature prompts, not the
# opencode behavior prompts, so the user's own instructions stay in charge.
SANDBOX_PROMPT_TMP=$(concat_prompts "${SANDBOX_PARTS[@]}")
CLEANUP_FILES+=("$SANDBOX_PROMPT_TMP")

# Claude Code: the managed-policy memory file, loaded in addition to the
# user's ~/.claude/CLAUDE.md, so no host file is shadowed.
RO_BINDS+=(--ro-bind "$SANDBOX_PROMPT_TMP" /etc/claude-code/CLAUDE.md)

# Codex has no system-wide instructions file, so ~/.codex/AGENTS.md is
# shadowed (read-only) by the host file followed by the sandbox prompt. When
# the host has none, bwrap leaves an empty mount point behind, which is
# removed again on exit.
CODEX_AGENTS="$HOME/.codex/AGENTS.md"
CODEX_AGENTS_CREATED=false
if [ "$DRY_RUN" != true ] && [ -d "$HOME/.codex" ]; then
  [ -e "$CODEX_AGENTS" ] || CODEX_AGENTS_CREATED=true
  CODEX_PROMPT_TMP=$(mktemp)
  CLEANUP_FILES+=("$CODEX_PROMPT_TMP")
  if [ -f "$CODEX_AGENTS" ]; then
    cat "$CODEX_AGENTS" > "$CODEX_PROMPT_TMP"
    printf '\n' >> "$CODEX_PROMPT_TMP"
  fi
  cat "$SANDBOX_PROMPT_TMP" >> "$CODEX_PROMPT_TMP"
  RO_BINDS+=(--ro-bind "$CODEX_PROMPT_TMP" "$CODEX_AGENTS")
fi

# opencode.jsonc: the base config and each enabled feature overlay are merged
# into plain JSON (comments and trailing commas stripped), so later jq steps
# never see JSONC syntax.
if [ -n "$OPENCODE_JSONC" ] && [ -f "$OPENCODE_JSONC" ]; then
  JSONC_SOURCES=("$OPENCODE_JSONC")
  for feature in "${WITH_FEATURES[@]}"; do
    overlay="$(feature_dir "$feature")/opencode.jsonc"
    [ -f "$overlay" ] && JSONC_SOURCES+=("$overlay")
  done

  JSONC_LAYERS=()
  for layer in "${JSONC_SOURCES[@]}"; do
    layer_tmp=$(mktemp)
    CLEANUP_FILES+=("$layer_tmp")
    sed "s|\"~/|\"$HOME/|g" "$layer" > "$layer_tmp"
    JSONC_LAYERS+=("$layer_tmp")
  done

  jsonc_current=$(mktemp)
  CLEANUP_FILES+=("$jsonc_current")
  bun "$MERGE_SCRIPT" "${JSONC_LAYERS[@]}" "$jsonc_current"

  # OmniRoute plugin (opt-in): added only when the host provides
  # ~/.config/opencode/omniroute.json. That file's JSON object is passed
  # through as the plugin `options` (baseURL, providerId, credentials, ...).
  # There is no URL probing and no default gateway: with no file, no plugin is
  # added, so it never loads with an empty catalog.
  omni_host_opts="$HOME/.config/opencode/omniroute.json"
  if [ -n "$OMNIROUTE_PLUGIN_V2" ] && [ -f "$omni_host_opts" ] \
     && omni_opts=$(jq -ec 'select(type == "object" and length > 0)' "$omni_host_opts" 2>/dev/null); then
    echo "OmniRoute plugin enabled ($omni_host_opts)" >&2
    omni_tmp=$(mktemp)
    CLEANUP_FILES+=("$omni_tmp")
    jq -c --argjson o "$omni_opts" \
      '.plugins = ((.plugins // []) + [{"package": "${OMNIROUTE_PLUGIN_V2}", "options": $o}])' \
      "$jsonc_current" > "$omni_tmp"
    jsonc_current="$omni_tmp"
  fi

  # Substitute ${OMNIROUTE_PLUGIN_V2} placeholder with the pre-built plugin path
  if [ -n "$OMNIROUTE_PLUGIN_V2" ]; then
    sed -i "s|\${OMNIROUTE_PLUGIN_V2}|file://$OMNIROUTE_PLUGIN_V2|g" "$jsonc_current"
  fi

  RO_BINDS+=(--ro-bind-try "$jsonc_current" "$OPENCODE_CFG/opencode.jsonc")
fi

SSH_BINDS=()
if [ "$MOUNT_SSH" = true ] && [ -d "$HOME/.ssh" ]; then
  SSH_TMPDIR=$(mktemp -d)
  CLEANUP_FILES+=("$SSH_TMPDIR")
  cp -rL "$HOME/.ssh"/. "$SSH_TMPDIR"/ 2>/dev/null || true
  chmod 700 "$SSH_TMPDIR"
  find "$SSH_TMPDIR" -type f -exec chmod 600 {} +
  find "$SSH_TMPDIR" -type f -name '*.pub' -exec chmod 644 {} +
  SSH_BINDS+=(--ro-bind-try "$SSH_TMPDIR" "$HOME/.ssh")
fi
if [ "$MOUNT_SSH" = true ] && [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK:-}" ]; then
  SSH_BINDS+=(--bind-try "$SSH_AUTH_SOCK" "$SSH_AUTH_SOCK")
  SSH_BINDS+=(--setenv SSH_AUTH_SOCK "$SSH_AUTH_SOCK")
fi

# Host serial device binds (ttyUSB*, ttyACM*)
TTY_GID_ARGS=()
HOST_DEV_BINDS=()
if [ "$BIND_SERIAL_DEV" = true ]; then
  dialout_entry=$(getent group dialout 2>/dev/null || true)
  if [ -z "$dialout_entry" ]; then
    echo "Error: --bind-serial-dev requires the 'dialout' group, which does not exist." >&2
    exit 1
  fi
  dialout_gid=$(echo "$dialout_entry" | cut -d: -f3)
  dialout_members=$(echo "$dialout_entry" | cut -d: -f4)
  if ! echo "$dialout_members" | tr ',' '\n' | grep -qx "$USER"; then
    echo "Error: --bind-serial-dev requires user '$USER' to be in the 'dialout' group." >&2
    exit 1
  fi
  TTY_GID_ARGS=(--gid "$dialout_gid")

  for dev in /dev/ttyUSB* /dev/ttyACM*; do
    [ -e "$dev" ] || continue
    HOST_DEV_BINDS+=(--dev-bind-try "$dev" "$dev")
  done
  if [ -d /dev/serial ]; then
    HOST_DEV_BINDS+=(--bind-try /dev/serial /dev/serial)
  fi
fi

# Default command: herdr session auto-launching the --agent TUI, or user override
if [ $# -eq 0 ]; then
  CMD=(bash "$HOME/.herdr-launch.sh")
else
  CMD=("$@")
  [ "$AGENT_SET" = true ] && echo "Warning: --agent is ignored when an explicit COMMAND is given." >&2
fi

# Assemble bwrap arguments
BWRAP_ARGS=(
  --unshare-all
  "${TTY_GID_ARGS[@]}"
  "${NET_ARGS[@]}"
  --die-with-parent
  # system bind mounts
  --ro-bind /usr /usr
  --ro-bind-try /lib /lib
  --ro-bind /lib64 /lib64
  --ro-bind /bin /bin
  --ro-bind-try /sbin /sbin
  --ro-bind-try /nix /nix
  --ro-bind /sys /sys
  "${NET_BINDS[@]}"
  "${DOCKER_BINDS[@]}"
  --proc /proc
  --dev /dev
  "${HOST_DEV_BINDS[@]}"
  --tmpfs /tmp
  --tmpfs /run
  "${WAYLAND_BINDS[@]}"
  --ro-bind-try /run/current-system/sw/bin /run/current-system/sw/bin
  --setenv XDG_RUNTIME_DIR "$RUNTIME_DIR"
  --setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-wayland-0}"
  # etc bind mounts
  --ro-bind-try /etc/ssl /etc/ssl
  --ro-bind-try /etc/pki /etc/pki
  --ro-bind-try /etc/ca-certificates /etc/ca-certificates
  --ro-bind-try /etc/nix /etc/nix
  --ro-bind-try /etc/static /etc/static
  --ro-bind-try /etc/alternatives /etc/alternatives
  --ro-bind-try /etc/passwd /etc/passwd
  --ro-bind-try /etc/group /etc/group
  --ro-bind-try /etc/machine-id /etc/machine-id
  "${SUBID_BINDS[@]}"
  "${TZ_BINDS[@]}"
  # home dirs
  --dir "$HOME"
  --dir "$RUNTIME_DIR"
  --setenv HOME "$HOME"
  --setenv AGENTBOX_AGENT "$AGENT"
  --chdir "$PWD"
  # Workspace binds come first: every sandbox-internal mount below is applied
  # afterwards, so a workspace that is a parent of a config/state/ssh path
  # cannot shadow the prepared environment.
  "${WORKSPACE_BINDS[@]}"
  "${RO_WORKSPACE_BINDS[@]}"
  # home bind mounts
  --bind-try "$HOME/.cache/opencode" "$HOME/.cache/opencode"
  --bind-try "$HOME/.local/share/opencode" "$HOME/.local/share/opencode"
  --bind "$OPCODE_STATE_TMPDIR" "$HOME/.local/state/opencode"
  --bind "$OPCODE_CFG_TMPDIR" "$OPENCODE_CFG"
  --bind-try "$HOME/.opencode" "$HOME/.opencode"
  --bind-try "$HOME/.claude" "$HOME/.claude"
  --bind-try "$HOME/.codex" "$HOME/.codex"
  --bind-try "$HOME/.multica" "$HOME/.multica"
  --bind-try "$HOME/.config/anthropic" "$HOME/.config/anthropic"
  --tmpfs "$HOME/.config/tuicr"
  --ro-bind-try "${TUICR_CONFIG:-$SCRIPT_DIR/default/tuicr/config.toml}" "$HOME/.config/tuicr/config.toml"
  --ro-bind-try "$HOME/.config/nix" "$HOME/.config/nix"
  --ro-bind-try "$HOME/.config/git" "$HOME/.config/git"
  --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig"
  --ro-bind-try "$HOME/.config/gh" "$HOME/.config/gh"
  --bind-try "$HOME/.cargo" "$HOME/.cargo"
  --ro-bind-try "$HOME/.local/share/fonts" "$HOME/.local/share/fonts"
  "${SSH_BINDS[@]}"
  "${GIT_CRED_ARGS[@]}"
  "${OPEN_URL_ARGS[@]}"
  "${PODMAN_ARGS[@]}"
  "${RO_BINDS[@]}"
  "${SECRETS_SHADOW[@]}"
  --ro-bind-try "${HERDR_LAUNCHER:-$SCRIPT_DIR/default/herdr/herdr-launch.sh}" "$HOME/.herdr-launch.sh"
  --bind "$HERDR_CFG_TMPDIR" "$HOME/.config/herdr"
  --bind "$HERDR_STATE_TMPDIR" "$HOME/.local/state/herdr"
  --setenv HERDR_CONFIG_PATH "$HOME/.config/herdr/config.toml"
  --setenv TMPDIR /tmp
  --setenv OPENCODE_CONFIG_DIR "$OPENCODE_CFG"
  --setenv CLAUDE_CONFIG_DIR "$CLAUDE_CFG_DIR"
  --unsetenv NODE_TLS_REJECT_UNAUTHORIZED
  --setenv CARGO_NET_OFFLINE false
  "${CA_ENV[@]}"
  "${CMD[@]}"
)

# Verbose / dry run: print the command before executing
if [ "$DO_VERBOSE" = true ] || [ "$DRY_RUN" = true ]; then
  echo "bwrap \\"
  for arg in "${BWRAP_ARGS[@]}"; do
    printf '  %q \\\n' "$arg"
  done
fi

if [ "$DRY_RUN" = true ]; then
  echo "(dry run: temp paths above are removed on exit)" >&2
  exit 0
fi

rc=0
bwrap "${BWRAP_ARGS[@]}" || rc=$?
if [ "$rc" -ne 0 ]; then
  restricted=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true)
  if [ "$restricted" = "1" ]; then
    cat >&2 <<'EOF'
Error: bubblewrap failed because AppArmor is restricting unprivileged
user namespace creation. To fix:

  echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | \
    sudo tee /etc/sysctl.d/20-apparmor-userns.conf
  sudo sysctl -p /etc/sysctl.d/20-apparmor-userns.conf

Then re-run this command.
EOF
  fi
fi
exit "$rc"
