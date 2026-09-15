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
  listenHost = "100.100.10.1";
  runtimeDir = "${config.home.homeDirectory}/.local/share/deepseek-harness/runtime";
  dshHome = "${config.home.homeDirectory}/.local/share/deepseek-harness/home";
  dshEntry = "${runtimeDir}/node_modules/@deepseek-ai/dsh/lib/bin.js";
  settingsClient = "${runtimeDir}/node_modules/@deepseek-ai/dsh-client-ui-settings/lib/client.js";
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

    # @deepseek-ai/dsh-client-ui-settings currently disables its settings
    # mirror whenever the browser URL is non-loopback, even when the server
    # has explicitly trusted that authority with --trusted-host. The NUC's
    # HTTPS endpoint is a single-user, Tailscale-approved service, so allow
    # the already-authenticated browser session to use the Host settings
    # mirror. Keep this patch version-sensitive and fail closed if the
    # upstream bundle changes instead of silently losing settings support.
    settings_client='${settingsClient}'
    '${pkgs.python3}/bin/python3' - "$settings_client" <<'PY'
    import pathlib
    import sys

    path = pathlib.Path(sys.argv[1])
    if not path.is_file():
        raise SystemExit(f"deepseek-harness: missing settings client bundle: {path}")

    source = path.read_text(encoding="utf-8")
    old = 'const persistence = ctx.remote.$host.isLoopback ? "host" : "memory";'
    new = 'const persistence = "host";'

    if new in source:
        raise SystemExit(0)
    if source.count(old) != 1:
        raise SystemExit(
            "deepseek-harness: unsupported dsh settings bundle; "
            f"expected one remote-settings guard in {path}"
        )

    path.write_text(source.replace(old, new), encoding="utf-8")
    print(f"deepseek-harness: enabled trusted remote settings in {path}")
    PY

    test -f "$entry"
  '';

  startHarness = pkgs.writeShellScript "deepseek-harness-start" ''
    # Nix-built Node cannot provide the loader internals through the native
    # fallback used by the current HMR dependency. Pass this Node-only flag
    # before the dsh entrypoint; NODE_OPTIONS is rejected for this flag.
    set -euo pipefail

    harness_pid=""
    proxy_pid=""

    cleanup() {
      trap - EXIT INT TERM
      if [ -n "$proxy_pid" ]; then
        kill "$proxy_pid" 2>/dev/null || true
      fi
      if [ -n "$harness_pid" ]; then
        kill "$harness_pid" 2>/dev/null || true
      fi
      wait "$proxy_pid" 2>/dev/null || true
      wait "$harness_pid" 2>/dev/null || true
    }
    trap cleanup EXIT INT TERM

    # dsh-host-webserver currently accepts only 127.0.0.1 or 0.0.0.0 as its
    # host value. Keep dsh on loopback and expose the exact Tailscale address
    # through a local TCP forward in the same systemd service.
    '${node}/bin/node' \
      --expose-internals \
      '${dshEntry}' \
      web \
      --host 127.0.0.1 \
      --port 3080 \
      --trusted-host ${listenHost}:3080 \
      --trusted-host deepseek-harness.tail388af.ts.net \
      --trusted-host deepseek-harness.tail388af.ts.net:443 \
      --no-open &
    harness_pid=$!

    '${pkgs.socat}/bin/socat' \
      'TCP-LISTEN:3080,bind=${listenHost},reuseaddr,fork' \
      'TCP:127.0.0.1:3080' &
    proxy_pid=$!

    wait -n "$harness_pid" "$proxy_pid"
  '';
in
{
  imports = [ ./proxy.nix ];

  home.packages = [ node ];

  systemd.user.services.deepseek-harness = {
    Unit = {
      Description = "DeepSeek Harness Web UI (Tailscale ${listenHost}:3080 via loopback backend)";
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
