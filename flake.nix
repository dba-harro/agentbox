{
  description = "Sandboxed AI coding agent harnesses (opencode2, Claude Code, Codex, Pi)";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix";
    omniroute-src = {
      url = "github:diegosouzapw/OmniRoute/v3.8.51";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      llm-agents,
      omniroute-src,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      agents = llm-agents.packages.${system};

      # opencode2 with the startup/CLI logo blanked out.
      #
      # The llm-agents opencode2 package installs the prebuilt release tarball
      # (no source), so we patch the compiled binary instead: right after the
      # tarball is unpacked, blank-logo.py replaces the logo art strings with
      # equal-length spaces (byte count is preserved, so the binary stays
      # intact and the wrapBuddy fixup in the next phase is unaffected).
      #
      # opencode2 ships inside a top-level `package/` directory (sourceRoot),
      # so the binary path is resolved with find rather than a fixed relative
      # path. The patch is anchored + assertion-guarded: if a future release
      # changes or removes the logo art, the build fails with a clear message
      # instead of silently doing nothing (see patches/blank-logo.py).
      opencode2NoLogo = agents.opencode2.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
        postUnpack = (old.postUnpack or "") + ''
          opencode_bin=$(find . -type f -path '*/bin/opencode' | head -n1)
          if [ -z "$opencode_bin" ]; then
            echo "ERROR: could not locate the opencode2 binary after unpack" >&2
            exit 1
          fi
          python3 ${./patches/blank-logo.py} "$opencode_bin"
        '';
      });

      lightShellInputs = with pkgs; [
        bash
        bubblewrap
        bun
        opencode2NoLogo
        agents.tuicr
        agents.herdr
        jq
        git
        socat
        gitui
        curl
        gh
        wl-clipboard
        uv
        podman
        agents.claude-code
        agents.codex
        agents.multica
        agents.pi
        (python3.withPackages (ps: [ ps.pyyaml ]))
      ];

      # Official OmniRoute OpenCode v2 plugin, built from the pinned OmniRoute
      # source checkout. The package ships a root server.js entrypoint that
      # OpenCode probes; dist/ alone is not enough, so it must land in $out.
      #
      # dist/index.js imports `{ Plugin } from "@opencode/plugin"` at runtime.
      # A `file://` plugin has no install step, so the host's Bun loader resolves
      # bare specifiers from the plugin directory's own node_modules; without it
      # the plugin dies with `Cannot find package '@opencode/plugin'`. The host
      # only virtualizes `@opencode/plugin/tui`, not the server root. Ship the
      # runtime closure of that peer dependency in $out/node_modules.
      omniroutePluginV2 =
        let
          # The upstream package-lock.json omits `resolved` URLs for many
          # packages, which makes npm's offline cache incomplete. Overlay a
          # complete lockfile (regenerated with `npm install
          # --package-lock-only`) so fetchNpmDeps can cache every tarball.
          #
          # @opencode/plugin is promoted from devDependencies to dependencies
          # so `npm prune --omit=dev` in installPhase keeps it (and its
          # closure) while dropping the build toolchain. The lockfile tracks
          # that promotion.
          omniroute-plugin-v2-src =
            pkgs.runCommand "opencode-plugin-v2-src"
              {
                nativeBuildInputs = [ pkgs.jq ];
              }
              ''
                cp -r ${omniroute-src}/@omniroute/opencode-plugin-v2 $out
                chmod -R +w $out
                cp ${./nix/opencode-plugin-v2-package-lock.json} $out/package-lock.json
                jq 'del(.devDependencies["@opencode/plugin"])
                    | .dependencies["@opencode/plugin"] = "2.0.12"' \
                  "$out/package.json" > "$out/package.json.tmp"
                mv "$out/package.json.tmp" "$out/package.json"
              '';
        in
        (pkgs.buildNpmPackage.override { nodejs = pkgs.nodejs_22; }) {
          pname = "opencode-plugin-v2";
          version = "0.1.0";
          src = omniroute-plugin-v2-src;
          npmDepsHash = "sha256-/jL0NbjwOVxEUntyD3Cw/QtWrJo0xwC9eqSnsjwAxm8=";
          installPhase = ''
            runHook preInstall
            # Drop the build toolchain (tsup/typescript/...); keep zod, the
            # @opencode/plugin peer, and its runtime closure.
            npm prune --omit=dev --no-save
            mkdir -p $out
            cp -r dist package.json server.js $out/
            cp -r node_modules $out/node_modules
            runHook postInstall
          '';
        };

      makeSandbox =
        {
          name,
          packages,
          defaultFeatures,
        }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = packages;
          text = ''
            export SKILL_DIR="${./default/skill}"
            export COMMANDS_DIR="${./default/command}"
            export PROMPTS_DIR="${./default/prompts}"
            export OPENCODE_JSONC="${./default/opencode.jsonc}"
            export HERDR_CONFIG="${./default/herdr/config.toml}"
            export HERDR_LAUNCHER="${./default/herdr/herdr-launch.sh}"
            export CLAUDE_STATUSLINE="${./default/claude/statusline.sh}"
            export TUICR_CONFIG="${./default/tuicr/config.toml}"
            export MERGE_SCRIPT="${./merge-jsonc.js}"
            export AGENTBOX_VERSION="${self.shortRev or self.dirtyShortRev or "unknown"}"
            export DEFAULT_FEATURES="${defaultFeatures}"
            export OMNIROUTE_PLUGIN_V2="${omniroutePluginV2}"
            export PODMAN_DIR="${./podman}"
            export GIT_CRED_DIR="${./default/git-cred}"
            export OPEN_URL_DIR="${./default/open-url}"
          ''
          + builtins.readFile ./sandbox.sh;
        };

      sandbox-light = makeSandbox {
        name = "sandbox";
        packages = lightShellInputs;
        defaultFeatures = "";
      };
    in
    {
      devShells.${system} = {
        default = pkgs.mkShell {
          buildInputs = lightShellInputs;
        };
      };
      apps.${system} = {
        default = {
          type = "app";
          program = "${sandbox-light}/bin/sandbox";
        };
      };
      packages.${system} = {
        default = sandbox-light;
        omniroute-plugin-v2 = omniroutePluginV2;
      };
      formatter.${system} = pkgs.writeShellApplication {
        name = "nixfmt-wrapper";
        runtimeInputs = [
          pkgs.findutils
          pkgs.nixfmt
        ];
        text = ''
          if [ $# -eq 0 ]; then
            find . -name '*.nix' -exec nixfmt {} +
          else
            nixfmt "$@"
          fi
        '';
      };
    };
}
