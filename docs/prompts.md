# Agent Prompts

Prompt files live in `default/prompts/` (base) and per-feature `prompts/` overlays. At session start `sandbox.sh` concatenates them into a single global `~/.config/opencode/AGENTS.md`, which is how opencode2 loads instructions (the V2 config `instructions` field is accepted but not resolved).

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
