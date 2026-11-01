# Sandbox

The bubblewrap sandbox (`sandbox.sh`) provides a security boundary around opencode2 sessions.

## Usage

```sh
nix run github:nix-dba/agentbox --refresh --accept-flake-config
```

Or from the cloned repo directly:

```sh
nix run . --refresh --accept-flake-config
```

## Apps

The flake provides one sandbox app:

- **`nix run .`** -- Sandbox with bare minimum dependencies

## CLI Flags

Defined in `sandbox.sh`:

| Flag | Description |
|------|-------------|
| `--agent NAME` | Agent TUI auto-launched in the Herdr session: `opencode2` (default), `claude` or `codex`. Ignored when an explicit command is given |
| `--no-git-init` | Skip git repository initialization prompt |
| `--verbose`, `-v` | Print the full bwrap command before execution |
| `--dry-run` | Print the full bwrap command and exit without starting the sandbox. Skips host changes (status line deployment, `~/.claude.json` import, git init, host directory creation) and the `$HOME` confirmation prompt |
| `--version` | Print the agentbox version (git revision of the flake) and exit |
| `--no-ssh-keys` | Do not mount `~/.ssh` in the sandbox (mounted read-only by default) |
| `--hide-secrets` | Hide `secrets`/`secret` directories in workspaces (they are visible by default) |
| `--no-net` | Disable network access in the sandbox |
| `--docker` | Bind the host Docker socket (`/var/run/docker.sock`). Off by default: socket access is root-equivalent on the host, and containers are not restricted by `--no-net` |
| `--bind-serial-dev` | Bind host `ttyUSB*`/`ttyACM*` serial devices (and `/dev/serial`) into the sandbox; requires membership in the `dialout` group |
| `--with-NAME` | Enable the optional feature overlay `NAME/` (repeatable; unknown names are rejected). No overlays are bundled yet, see `AGENTS.md` |
| `-w`, `--workspace PATH` | Bind additional workspace directory (repeatable) |
| `-r`, `--readonly PATH` | Bind additional directory read-only (repeatable) |

## Behavior

- Creates necessary directories (`~/.config/opencode`, `~/.opencode`, etc.) before sandbox entry
- If the current directory is not a git repo, prompts to initialize one
- Relative `-w`/`-r` paths are resolved to absolute paths; paths that are not directories are skipped with a warning
- If a workspace (`$PWD`, `-w` or `-r`) is your home directory or contains it, a warning is printed and an interactive `y/N` confirmation is required; without a terminal the sandbox refuses to start
- Uses an isolated Herdr config/state (temp directories) to avoid polluting host Herdr state
- OpenCode state (`~/.local/state/opencode`) is a per-sandbox mirror: the selected model (`model.json`), prompt history, and TUI layout are seeded from the host and copied back on exit, so they survive restarts and are shared by every session in the sandbox. Runtime files (`service.json`, `locks/`) are not persisted
- Claude Code state persists in the host `~/.claude` directory, mounted read-write and exported as `CLAUDE_CONFIG_DIR`: settings, credentials (`~/.claude/.credentials.json`), global config/trust/MCP state (`~/.claude/.claude.json`, imported once from a pre-existing host `~/.claude.json`) and session transcripts all survive restarts
- Deploys the bundled Claude Code status line (`default/claude/statusline.sh`) to `~/.claude/statusline.sh` and adds a `statusLine` entry to `~/.claude/settings.json` on every start. It is idempotent, backs up the settings file before changing it, and leaves a `statusLine` owned by another command untouched
- Codex state persists in the host `~/.codex` directory, mounted read-write: auth, config and session history survive restarts
- Default command is `herdr-launch.sh` which starts a Herdr session and auto-launches the `--agent` TUI (opencode2 by default)
- If arguments are provided, they are passed directly as the sandbox command instead
- Network binds (`resolv.conf`, `hosts`, `nsswitch.conf`) are conditional on `--no-net`; the Docker socket is only bound with `--docker`
- Wayland socket is auto-detected and mounted for GUI clipboard support
- SSH keys are mounted read-only by default (a hardened temp copy); pass `--no-ssh-keys` to leave `~/.ssh` out of the sandbox
- Skills and commands are mounted as read-only bind mounts under `~/.config/opencode/skills/` and `~/.config/opencode/commands/`, plus per-feature overlays for enabled `--with-*` flags
- `--hide-secrets` shadows `secrets`/`secret` directories in all workspaces, including `-r` read-only ones
- TLS: the host system CA bundle (first of `/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`, `/etc/ssl/ca-bundle.pem`, `/etc/ssl/cert.pem`) is exported as `SSL_CERT_FILE`, `NIX_SSL_CERT_FILE`, `GIT_SSL_CAINFO` and `NODE_EXTRA_CA_CERTS`, so locally trusted CAs work with certificate verification enabled. An inherited `NODE_TLS_REJECT_UNAUTHORIZED` is removed
- Timezone: `/etc/localtime` (recreated as a symlink when it is one on the host), `/etc/zoneinfo` and `/etc/timezone` are exposed read-only, so local times match the host
- The exit status of the sandboxed command is passed through
- Workspace binds (`$PWD` and `-w` paths) are applied **before** all sandbox-internal mounts, so running from a parent of the config/state paths (e.g. `~` or `~/.config/opencode`) cannot shadow the prepared environment
- A workspace that contains a protected system mount root (`/`, `/usr`, `/bin`, `/lib`, `/lib64`, `/sbin`, `/nix`, `/etc`, `/proc`, `/sys`, `/dev`, `/run`) is rejected with an error, since such a bind would shadow the sandbox's system mounts
- The bundled prompts plus any enabled feature prompts are concatenated into a single global `~/.config/opencode/AGENTS.md` (opencode2 loads instructions from `AGENTS.md`; the config `instructions` field is accepted but not resolved in V2)

## Sandbox Bind Mounts

The sandbox mounts:
- System: `/usr`, `/lib`, `/lib64`, `/bin`, `/sbin`, `/nix`, `/sys`, `/proc`, `/dev`
- Network files (conditional): `/etc/resolv.conf`, `/etc/hosts`, `/etc/nsswitch.conf`
- Docker socket (only with `--docker`): `/var/run/docker.sock`
- TLS/SSL: `/etc/ssl`, `/etc/pki`, `/etc/ca-certificates`, `/etc/nix`, `/etc/static`
- Timezone: `/etc/localtime`, `/etc/zoneinfo`, `/etc/timezone`
- User config: `~/.config/opencode` (per-sandbox writable copy of the host directory; changes are discarded on exit), `~/.config/tuicr` (tmpfs), `~/.config/git`, `~/.config/nix`, `~/.claude` (read-write, exported as `CLAUDE_CONFIG_DIR`), `~/.codex` (read-write), `~/.config/anthropic`
- User data: `~/.cache/opencode`, `~/.local/share/opencode`, `~/.local/state/opencode`
- Herdr: isolated temp config and state directories

Mounts are applied in order and a later bind on an ancestor path shadows earlier child mounts. Workspace binds are therefore applied before the internal home/config/state mounts, which guarantees the sandbox's prepared environment wins. Workspaces that contain a protected system mount root are rejected (see [Behavior](#behavior)).
