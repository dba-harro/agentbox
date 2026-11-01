# Custom Commands

Custom opencode2 commands are defined in `default/command/` as Markdown files and installed under `~/.config/opencode/commands/`.

## `/commit`

File: `default/command/commit.md`

Creates well-formatted git commits with conventional commit messages. Workflow:
1. Runs `git status --porcelain` to check for changes
2. Auto-stages all modified files if nothing is staged
3. Analyzes the diff to determine commit type (feat, fix, docs, etc.)
4. Generates a conventional commit message and executes the commit
5. Confirms commit hash and provides a summary

Message format: `<type>: <description>` with imperative mood, under 72 characters. Does not push.

## `/docs`

File: `default/command/docs.md`

Generates and maintains repository documentation in `docs/` and updates `README.md`. Workflow:
1. Analyzes the repository by reading `flake.nix`, `justfile`, `README.md`
2. Creates or updates per-component files in `docs/`
3. Updates the README with a `## Documentation` section linking to generated docs

Only documents facts existing in the repository source code.

## `/tuicr`

File: `default/command/tuicr.md`

Launches the tuicr TUI for interactive code review of local git changes. Delegates to `tuicr-wrapper.sh`.
