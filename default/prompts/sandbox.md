# Sandbox

You are running inside an agentbox sandbox (bubblewrap, unprivileged user
namespace), not directly on the host. Keep this in mind:

- **Only the workspaces are real.** Writes to the workspace directories listed
  below land on the host and persist. Read-only paths cannot be changed.
- **Everything else is ephemeral or read-only.** `/tmp`, `/run` and most of
  `$HOME` are private and discarded on exit; `/usr`, `/nix` and the bound
  `/etc` files are read-only.
- **No root.** `sudo`, system package managers and writing system paths do not
  work. Get extra tools with `nix shell nixpkgs#<pkg>` or `nix run`
  (needs network).
- **Isolated processes.** Host processes are not visible, and everything started
  here is killed when the sandbox exits; there is no systemd.
- The session runs in a herdr terminal multiplexer (see the herdr skill).
- If something fails because of the sandbox (missing path, permission, network),
  say so instead of working around the isolation.
