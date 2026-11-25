# Overview

This repository provides a Nix flake-based sandbox for AI coding agent harnesses. It packages opencode2, Claude Code, Codex and pi with:

- **Bubblewrap sandbox** (`sandbox.sh`) -- isolates the harnesses from the host filesystem to reduce secret exposure risk
- **Herdr** terminal workspace (agent-native session) that auto-launches the harness picked from an fzf menu at startup (or set with `--agent`)
- **OmniRoute** -- official opencode v2 plugin (`@omniroute/opencode-plugin-v2`), built from source and opt-in via a host `~/.config/opencode/omniroute.json`
- **tuicr** -- TUI code review tool with vim keybindings, launched via `/tuicr` command
- **Custom opencode2 commands**: `/commit`, `/docs`, `/tuicr`
- **Custom agent instructions**: general guidelines and Karpathy-style coding rules, concatenated into a global `AGENTS.md`, plus a sandbox prompt for opencode2, Claude Code, Codex and pi

All tools and dependencies are version-pinned via the Nix flake lockfile for reproducible environments.
