# Configuration

## opencode.jsonc

File: `default/opencode.jsonc` (native opencode2 shape)

General opencode2 configuration:
- **update**: `"disable"` -- updates are managed by Nix
- **plugins**: the official OmniRoute v2 plugin, added by `sandbox.sh` only when the host provides `~/.config/opencode/omniroute.json`; it is referenced by its Nix store path via the `${OMNIROUTE_PLUGIN_V2}` placeholder (substituted by `sandbox.sh`)
- **compaction**: `auto: false` -- automatic context compaction is disabled
- **permissions**: ordered rule array (last match wins) allowing `read` and `external_directory` on all resources

`sandbox.sh` merges this file with the `opencode.jsonc` of every enabled `--with-*` feature via `merge-jsonc.js` (comments and trailing commas allowed) and mounts the result, as plain JSON, at `~/.config/opencode/opencode.jsonc`.

Instructions are no longer listed in `opencode.jsonc`. opencode2 loads them from `AGENTS.md`, which `sandbox.sh` generates by concatenating the bundled prompt files (`general.md`, `karpathy.md`).

### OmniRoute plugin configuration

The plugin is opt-in. `sandbox.sh` adds it to the generated config only when a host `~/.config/opencode/omniroute.json` exists and contains a non-empty JSON object. That object is passed through as the plugin's `options`, so the host supplies the gateway settings. With no file, no OmniRoute plugin is added (there is no URL probing and no default gateway).

Example `~/.config/opencode/omniroute.json` (`baseURL` is required; omit the credential keys when you use the connected credential instead):

```json
{
  "baseURL": "https://omni-route.k8s.lan",
  "providerId": "omniroute",
  "apiKey": "sk-omniroute-…",
  "managementReadToken": "…"
}
```

`baseURL` is the gateway root (no `/v1` suffix needed). See the plugin [README](https://github.com/diegosouzapw/OmniRoute/blob/v3.8.51/@omniroute/opencode-plugin-v2/README.md) for the full option list (`displayName`, `enrichment`, `usableOnly`, `visibleModels` / `hiddenModels`, `modelCacheTtlMs`, ...).

#### Credentials

The plugin needs a gateway key, resolved in this order:

1. **Connected credential** (recommended) -- connect through opencode's auth flow (`opencode auth`, or the Connect action in the model picker). Nothing is written to `omniroute.json`.
2. **`apiKey` in `~/.config/opencode/omniroute.json`** -- per-user override; the key ends up in a plaintext config file.
3. **`OMNIROUTE_API_KEY`** environment variable.

The gateway's `/api/*` endpoints (combos, provider health, enrichment) usually need a separate **management** token. Set `managementReadToken` in `omniroute.json` (or export `OMNIROUTE_MANAGEMENT_API_KEY`); when both are set the option wins. If unset, it falls back to `apiKey` with a startup warning.

If none yields a key, the catalog is empty and the plugin logs it once at startup rather than leaving a silent empty model list.

### Refreshing the model list

The catalog is fetched once when the plugin is loaded. When models are added,
reloaded, or removed on the gateway, refresh the list with:

- the `/reload` slash command (command palette entry "Reload configuration"), or
- `opencode2 reload` from a shell.

The plugin caches the catalog for 5 minutes (`modelCacheTtlMs`, default
`300000` ms) and persists it to `~/.local/share/opencode/plugins/omniroute-<providerId>.json`
(or `$OPENCODE_DATA_DIR/plugins/…`). A reload within the cache window reuses the
snapshot instead of hitting the gateway. To force a fresh fetch, delete the
snapshot file before reloading, or lower `modelCacheTtlMs` in the plugin
`options`.

## Herdr Configuration

Files:
- `default/herdr/config.toml` -- Herdr session configuration
- `default/herdr/herdr-launch.sh` -- default sandbox command

The launcher starts a headless Herdr server, creates a workspace for the current
directory, auto-launches the `--agent` TUI (`opencode2` by default) in its root pane,
then attaches the client.
`config.toml` disables onboarding and background update checks, and sets the
default shell to `bash`.

## tuicr Config

File: `default/tuicr/config.toml`

Code review TUI settings:
- `diff_view = "side-by-side"`
- `appearance = "dark"`
- `mouse = true`
- `leader = ","`
- `review_watch_interval_ms = 1000`

## Nix Flake

File: `flake.nix`

Flake outputs:
- `devShells.default` -- shell with all dependencies (bash, bubblewrap, bun, opencode2 (logo blanked), tuicr, herdr, jq, git, gitui, curl, gh, wl-clipboard, uv, claude-code, codex, t3code-desktop, python3 with pyyaml)
- `apps.default` -- run the `sandbox` script
- `packages.default` -- the built sandbox wrapper
- `packages.omniroute-plugin-v2` -- the built OmniRoute opencode v2 plugin
- `formatter.default` -- `nixfmt` wrapper (formats all `*.nix` files or specified paths)

Flake inputs:
- `nixpkgs` (nixpkgs-unstable)
- `llm-agents.nix` (provides opencode2, tuicr, herdr, claude-code, codex, t3code-desktop packages)
- `omniroute-src` (pinned `diegosouzapw/OmniRoute` checkout, source for the v2 plugin)

Extra substituter: `https://cache.numtide.com`

## Provider Configuration

Example `~/.config/opencode/opencode.json` for a llama.cpp endpoint:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "llama.cpp": {
      "name": "llama-server",
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": {
        "baseURL": "https://llama-cpp.k8s.lan/v1"
      },
      "models": {
        "Qwen3.5-27B-Q3-KV8": {
          "name": "Qwen3.5-27B-Q3-KV8",
          "capabilities": {
            "input": ["text"],
            "output": ["text"]
          },
          "limit": {
            "context": 240000,
            "output": 65536
          }
        },
        "Gemma4-31B-Q3-KV8": {
          "name": "Gemma4-31B-Q3-KV8",
          "capabilities": {
            "input": ["text"],
            "output": ["text"]
          },
          "limit": {
            "context": 150000,
            "output": 65536
          }
        }
      }
    }
  }
}
```

When integrated with omni-route, the provider catalog is published by the plugin (see [OmniRoute plugin configuration](#omniroute-plugin-configuration)). The host `~/.config/opencode/omniroute.json` supplies the gateway settings.

### LLaMa.cpp Server Config

Example `config.ini` for a NVIDIA RTX 3090:

```ini
[*]
models-autoload = 0
sleep-idle-seconds = 600
warmup = 0
fit = 1
mmap = 0
fit-target = 400
cache-ram = 16384
parallel = 1
ctx-checkpoints = 128
cache-prompt = 1

[Gemma4-31B-Q3-KV8]
hf-repo = unsloth/gemma-4-31B-it-GGUF
hf-file = gemma-4-31B-it-UD-Q3_K_XL.gguf
jinja = 1
ctx-size = 150000
temp = 1.0
top-p = 0.95
top-k = 64
main-gpu = 0
cache-type-k = q8_0
cache-type-v = q8_0
no-mmproj = 1
flash-attn = 1
split-mode = none

[Qwen3.6-35B-A3B-Q4-KV8]
hf-repo = unsloth/Qwen3.6-35B-A3B-GGUF
hf-file = Qwen3.6-35B-A3B-UD-Q4_K_S.gguf
jinja = 1
ctx-size = 262144
temp = 0.7
min-p = 0.0
top-p = 0.95
top-k = 20
presence-penalty = 1.5
repeat-penalty = 1.0
main-gpu = 0
cache-type-k = q8_0
cache-type-v = q8_0
split-mode = none

[Qwen3.6-27B-Q4-KV8-MTP]
hf-repo = unsloth/Qwen3.6-27B-MTP-GGUF
hf-file = Qwen3.6-27B-IQ4_NL.gguf
jinja = 1
ctx-size = 170000
temp = 0.6
min-p = 0.0
top-p = 0.95
top-k = 20
presence-penalty = 0.0
repeat-penalty = 1.0
main-gpu = 0
cache-type-k = q8_0
cache-type-v = q8_0
no-mmproj = 1
split-mode = none
spec-type = draft-mtp
spec-draft-n-max = 3
draft-p-min = 0.0
reasoning-format = deepseek
```

### llama-cpp Server (Kubernetes)

```yaml
app:
  image:
    repository: ghcr.io/ggml-org/llama.cpp
    tag: "server-cuda"
  env:
    NVIDIA_VISIBLE_DEVICES: all
    NVIDIA_DRIVER_CAPABILITIES: all
    LLAMA_CACHE: "/models"
  args:
    - --port
    - "8080"
    - --host
    - 0.0.0.0
    - --models-preset
    - /models/config.ini
```

### Nginx Relay

```nginx
http {
  server {
    listen 8080;
    server_name _;

    location / {
      proxy_pass https://llama-cpp.$TAILNET_ID.ts.net;
      proxy_set_header Host llama-cpp.$TAILNET_ID.ts.net;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto http;
      proxy_ssl_server_name on;
    }
  }
}
```
