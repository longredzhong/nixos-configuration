# DeepSeek Harness Web UI as an HM user-level systemd service (Fedora NUC).
#
# The npm distribution is installed once into a user-owned runtime directory so
# the service can use the same Home Manager target on a non-NixOS Fedora host.
# Harness state (sessions, settings, credentials and profiles) lives separately
# under ~/.local/share/deepseek-harness/home.
{
  config,
  pkgs,
  ...
}:
let
  node = pkgs.nodejs_22;
  npm = pkgs.nodejs-slim_22.npm;
  dshVersion = "0.1.5-rc.2";
  runtimeDir = "${config.home.homeDirectory}/.local/share/deepseek-harness/runtime";
  dshHome = "${config.home.homeDirectory}/.local/share/deepseek-harness/home";
  dshEntry = "${runtimeDir}/node_modules/@deepseek-ai/dsh/lib/bin.js";
  runtimeManifest = pkgs.writeText "deepseek-harness-package.json" ''
    {
      "private": true,
      "dependencies": {
        "@deepseek-ai/dsh": "${dshVersion}"
      }
    }
  '';

  ensureRuntime = pkgs.writeShellScript "deepseek-harness-install" ''
    set -euo pipefail

    runtime='${runtimeDir}'
    entry='${dshEntry}'
    expected='${dshVersion}'

    # npm is a separate nixpkgs output and its launcher resolves `node` through
    # PATH. Keep the runtime self-contained while retaining Fedora utilities.
    export PATH='${node}/bin:${npm}/bin:/usr/bin:/bin'
    mkdir -p "$runtime" '${dshHome}'

    if [ ! -f "$runtime/package.json" ]; then
      install -m 0644 '${runtimeManifest}' "$runtime/package.json"
    fi

    installed=""
    if [ -f "$runtime/node_modules/@deepseek-ai/dsh/package.json" ]; then
      installed="$(${node}/bin/node -e '
        const fs = require("node:fs");
        try {
          const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
          process.stdout.write(typeof manifest.version === "string" ? manifest.version : "");
        } catch (_) {
          process.exit(1);
        }
      ' "$runtime/node_modules/@deepseek-ai/dsh/package.json" 2>/dev/null || true)"
    fi

    if [ "$installed" != "$expected" ] || [ ! -x "$entry" ]; then
      echo "deepseek-harness: installing @deepseek-ai/dsh@$expected" >&2
      cd "$runtime"
      '${npm}/bin/npm' install \
        --omit=dev \
        --no-audit \
        --no-fund \
        --save-exact \
        "@deepseek-ai/dsh@$expected"
    fi

    test -f "$entry"
  '';

  startHarness = pkgs.writeShellScript "deepseek-harness-start" ''
    # Nix-built Node cannot provide the loader internals through the native
    # fallback used by the current HMR dependency. Pass this Node-only flag
    # before the dsh entrypoint; NODE_OPTIONS is rejected for this flag.
    exec '${node}/bin/node' \
      --expose-internals \
      '${dshEntry}' \
      web \
      --host 127.0.0.1 \
      --port 3080 \
      --no-open
  '';
in
{
  imports = [ ./proxy.nix ];

  home.packages = [ node ];

  systemd.user.services.deepseek-harness = {
    Unit = {
      Description = "DeepSeek Harness Web UI (loopback port 3080)";
      After = [
        "network-online.target"
      ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      WorkingDirectory = config.home.homeDirectory;
      ExecStartPre = ensureRuntime;
      ExecStart = startHarness;
      Environment = config.hostServices.proxyEnvironment ++ [
        "DSH_HOME=${dshHome}"
        "DSH_TELEMETRY_DISABLED=1"
        "all_proxy="
        "ALL_PROXY="
        # A user-level service has the desktop environment available, but the
        # native picker would open on the NUC display instead of in the Web UI.
        "DISPLAY="
        "WAYLAND_DISPLAY="
      ];
      Restart = "always";
      RestartSec = "5s";
      TimeoutStartSec = "15min";
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
