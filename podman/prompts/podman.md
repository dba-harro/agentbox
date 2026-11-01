# Podman

Rootless `podman` is available inside this sandbox, with these limits:

- **Single uid.** Containers only have `root` (uid 0); there are no other uids.
  Anything that switches user fails: `USER` directives, `su`/`sudo`, `setpriv`,
  `useradd` + `chown`. Run and build as root.
- **apt** drops privileges by default; use `apt-get -o APT::Sandbox::User=root ...`
  (or set it in `/etc/apt/apt.conf.d/` in the Containerfile).
- **Host networking only.** Containers share the sandbox network namespace:
  `-p`/`--publish` has no effect, services listen directly on the sandbox
  ports, and `--network` with a custom network does not work.
- **No cgroups.** `--memory`, `--cpus` and similar resource limits are unavailable.
- No systemd, quadlets, `podman machine` or pods with private networks.
- The warning `"/" is not a shared mount` is expected and harmless.
- Image storage persists across sandbox restarts.
