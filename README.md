# agentbox

Sandboxed environment for AI coding agent harnesses -- opencode2, Claude Code and Codex -- running via Nix with Bubblewrap isolation.

## Documentation

- [Overview](docs/overview.md) -- High-level architecture and components
- [Sandbox](docs/sandbox.md) -- Bubblewrap sandbox CLI flags and bind mounts
- [Commands](docs/commands.md) -- Custom `/commit`, `/docs`, `/tuicr` commands
- [Skills](docs/skills.md) -- Herdr and tuicr skills available to the agent
- [Prompts](docs/prompts.md) -- Agent instruction files (general, karpathy, sandbox)
- [Configuration](docs/configuration.md) -- opencode.jsonc, Herdr config, tuicr config, Nix flake

## Features

- **Bubblewrap sandbox** (`sandbox.sh`) -- Isolates the agent harnesses from the host filesystem to reduce secret exposure risk
- **Multiple harnesses** -- opencode2 (default, auto-launched), Claude Code and Codex are all available (plus the T3 Code desktop app, `t3code-desktop`) inside the sandbox, with their state persisted in `~/.local/share/opencode` + `~/.local/state/opencode`, `~/.claude` and `~/.codex`
- **Herdr terminal workspace** -- Agent-native session that auto-launches the selected agent TUI (opencode2 by default)
- **OmniRoute plugin** -- Official opencode v2 plugin (`@omniroute/opencode-plugin-v2`), built from a pinned source checkout and opt-in via a host `~/.config/opencode/omniroute.json`
- **Podman** (`--with-podman`) -- Nested rootless podman inside the sandbox (single uid, host networking, persistent image storage), see [Sandbox](docs/sandbox.md#podman)
- **tuicr** -- TUI code review tool with vim keybindings, launched via `/tuicr` command in a Herdr tab
- **Custom opencode2 commands** -- `/commit` (conventional commits), `/docs` (documentation generation), `/tuicr` (code review)
- **Custom agent instructions** -- General guidelines and Karpathy-style coding rules concatenated into a global `AGENTS.md`, plus a sandbox prompt for all three harnesses
- **Version-pinned** -- All tools and dependencies pinned via the Nix flake lockfile

## Usage

In your repository root run:

```sh
nix run github:nix-dba/agentbox --refresh --accept-flake-config
```

Or from the cloned repo directly:

```sh
nix run . --refresh --accept-flake-config
```

To start a different agent TUI in the Herdr session (`opencode2` is the default):

```sh
nix run . -- --agent codex   # or: claude, opencode2
```

## Quitting

Press **`ctrl+b q`** to quit. This detaches the Herdr client; because the Herdr
server runs inside the bubblewrap sandbox, quitting also tears down the sandbox
and all its processes. Re-run `nix run .` for a fresh session.

## Apps

The flake provides one sandbox app:

- **`nix run .`** -- Sandbox with bare minimum dependencies

See [docs/sandbox.md](docs/sandbox.md) for available CLI flags (`--no-net`, `--no-ssh-keys`, `--hide-secrets`, `--no-git-creds`, `--agent`, etc.).
