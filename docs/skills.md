# Skills

Skills are defined in `default/skill/` and mounted into the opencode2 agent's skill directory (`~/.config/opencode/skills/`).

## herdr Skill

File: `default/skill/herdr/SKILL.md`

The official Herdr agent skill. Teaches opencode2 to control the session it runs in: inspect and split panes, run commands, read output, wait for state changes, and coordinate sibling agents via the `herdr` CLI. Guarded by `HERDR_ENV=1`.

## tuicr Skill

File: `default/skill/tuicr/SKILL.md`

Launches the `tuicr` code review TUI in a new Herdr tab via `tuicr-wrapper.sh`. Validates prerequisites (tuicr installed, git repo, inside Herdr), creates a tab and runs tuicr with `herdr tab create` + `herdr pane run`, and captures any instructions exported via stdout markers.
