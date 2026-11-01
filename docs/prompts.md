# Agent Prompts

Prompt files live in `default/prompts/` (base) and per-feature `prompts/` overlays. At session start `sandbox.sh` concatenates them into a single global `~/.config/opencode/AGENTS.md`, which is how opencode2 loads instructions (the V2 config `instructions` field is accepted but not resolved). The sandbox prompt and feature prompts are also delivered to Claude Code and Codex (see [Sandbox](#sandbox-defaultpromptssandboxmd)).

## General (`default/prompts/general.md`)

Baseline agent behavior:
- Answer directly when no tools are needed
- Prefer the smallest set of reads, searches, and commands
- Escalate to planning only for non-trivial work
- Follow least privilege; ask before destructive/networked actions

## Karpathy (`default/prompts/karpathy.md`)

Behavioral guidelines to reduce LLM coding mistakes:
- Think before coding: surface tradeoffs, ask when unclear
- Simplicity first: minimum code, no speculative features
- Surgical changes: touch only what's needed, match existing style
- Goal-driven execution: define verifiable success criteria, loop until verified

## Sandbox (`default/prompts/sandbox.md`)

Tells the agent it runs inside the agentbox sandbox: only workspaces are persistent host paths, the rest is ephemeral or read-only, there is no root (use `nix shell`), and processes die with the sandbox. `sandbox.sh` appends a generated *This sandbox session* section (agent, writable workspaces, read-only paths, network on/off, SSH keys, hidden secrets, Docker socket, serial devices, enabled features).

Unlike the other prompts it reaches every harness:

| Harness | Delivered as |
|---------|--------------|
| opencode2 | Part of `~/.config/opencode/AGENTS.md` (with all other prompts) |
| Claude Code | `/etc/claude-code/CLAUDE.md` (managed memory, loaded in addition to `~/.claude/CLAUDE.md`) |
| Codex | `~/.codex/AGENTS.md`, shadowed read-only: the host file (if any) followed by the sandbox prompt. An empty mount point left behind when the host has no such file is removed on exit |

Claude Code and Codex get only the sandbox prompt and enabled feature prompts (e.g. `podman.md`), not `general.md`/`karpathy.md`. The Codex prompt is only added when `~/.codex` exists on the host.
