# Feature Overlay System

The sandbox uses a feature overlay system to conditionally include optional tools.
Each `--with-<name>` flag maps to a sibling directory `<name>/` next to `default/`.
Bundled overlays: `podman/` (`--with-podman`). `--with-<name>` for an unknown
feature is rejected.

## Directory structure

```
default/                   # base config — always included, no optional features
├── opencode.jsonc         # base config (no feature-specific additions)
├── prompts/               # general.md, karpathy.md, sandbox.md
├── skill/                 # tuicr/, herdr/
├── command/               # commit.md, docs.md, tuicr.md
├── claude/                # statusline.sh (deployed to ~/.claude)
├── herdr/                 # config.toml, herdr-launch.sh
└── tuicr/                 # config.toml

podman/                    # --with-podman (nested rootless podman)
├── containers/            # containers.conf, storage.conf, policy.json, registries.conf
└── prompts/               # podman.md

<feature>/                 # optional overlay for --with-<feature>
├── opencode.jsonc         # optional — only feature-specific additions
├── prompts/               # optional — concatenated into AGENTS.md
└── skill/                 # optional — subdirectories bound into skills/
```

## How it works

Each feature directory can contain any subset of:
- `opencode.jsonc` — deep-merged into the base jsonc (objects merge recursively, arrays concatenate, scalars overlay)
- `prompts/` — `.md` files concatenated into the global `$HOME/.config/opencode/AGENTS.md`,
  and appended to the sandbox prompt given to Claude Code and Codex
- `skill/` — subdirectories bound into `$HOME/.config/opencode/skills/`

The merge script at `merge-jsonc.js` (`merge-jsonc.js <base> [overlay ...] <out>`)
handles JSONC comment and trailing-comma stripping and the deep-merge. Its output
is plain JSON.

`sandbox.sh` parses `--with-<name>` generically and resolves the feature directory
from the environment variable `<NAME>_DIR` (upper-cased, dashes become
underscores, e.g. `--with-foo-bar` → `FOO_BAR_DIR`).

## Adding a new feature

1. Create `<feature>/` directory with optional `opencode.jsonc`, `prompts/`, `skill/`
2. In `flake.nix`: add `export <FEATURE>_DIR="${./<feature>}"` to the sandbox text block
3. In `sandbox.sh`: only if the feature needs extra setup beyond the overlay
   (dir creation, extra binds, ...), add it to the feature setup loop
   (`# Feature setup (per --with-<name> flags)`). No flag parsing change is needed.
4. Document the feature in `docs/` (see `docs/sandbox.md`).
