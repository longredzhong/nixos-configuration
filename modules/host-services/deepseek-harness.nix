# DeepSeek Harness Web UI as an HM user-level systemd service.
#
# The npm distribution is installed once into a user-owned runtime directory so
# the service can run under standalone Home Manager on a non-NixOS host.
# Harness state (sessions, settings, credentials and profiles) lives separately
# under this module's DSH_HOME.
#
# Everything that names a deployment — the Tailscale Service the browser opens,
# the app capability Serve forwards for tagged clients, the OpenObserve streams
# and the OTEL host attribute — is an option, so a second host reuses this
# reviewed startup path instead of copying it. The defaults describe the
# reference deployment (the NUC); users/longred/<host>.nix sets the rest.
{
  config,
  lib,
  pkgs,
  hostname,
  ...
}:
let
  cfg = config.hostServices.deepseekHarness;
  inherit (cfg)
    dshVersion
    serviceHost
    appCapability
    runtimeDir
    dshHome
    openobserveEndpoint
    ;
  node = pkgs.nodejs_22;
  npm = pkgs.nodejs-slim_22.npm;
  webProfileDir = "${dshHome}/profiles/web";
  webProfileManifest = "${webProfileDir}/package.json";
  sessionPluginName = "@longred/deepseek-harness-opencode-session";
  sessionPluginPath = "${pkgs.deepseek-harness-opencode-session}/lib/node_modules/${sessionPluginName}";
  observabilityPluginName = "@longred/deepseek-harness-observability";
  observabilityPluginPath = "${pkgs.deepseek-harness-observability}/lib/node_modules/${observabilityPluginName}";
  otelPluginName = "dsh-otel";
  otelPluginPath = "${pkgs.dsh-otel}/lib/node_modules/${otelPluginName}";

  # Bundles this module contributes to the web profile, in patch order.
  profilePlugins = [
    {
      name = sessionPluginName;
      path = sessionPluginPath;
    }
    {
      name = observabilityPluginName;
      path = observabilityPluginPath;
    }
    {
      name = otelPluginName;
      path = otelPluginPath;
    }
  ];

  # Session telemetry destination. The credential is the OpenObserve ingestion
  # token the collector already uses: this module and openobserve-agent.nix are
  # imported together for this host, and OpenObserve ingestion tokens are
  # organization scoped, so a separate token would carry the same privilege.
  # Split them when per-service rotation is wanted.
  openobserveLedgerStream = cfg.ledgerStream;
  openobserveOpsStream = cfg.opsStream;
  # GenAI traces and metrics emitted by the dsh-otel plugin over OTLP/HTTP.
  openobserveOtlpStream = cfg.otlpStream;
  openobserveToken = config.age.secrets.openobserve-agent-token.path;
  dshEntry = "${runtimeDir}/node_modules/@deepseek-ai/dsh/lib/bin.js";
  settingsClient = "${runtimeDir}/node_modules/@deepseek-ai/dsh-client-ui-settings/lib/client.js";
  connectionClient = "${runtimeDir}/node_modules/@deepseek-ai/dsh-client-connection/lib/index.js";
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

    # Initialize the shipped web profile before adding the local bundles. This
    # keeps the profile's own manifest and patch-reload policy under dsh's
    # control while making the bundles reproducible from the Home Manager
    # generation.
    if [ ! -f '${webProfileManifest}' ]; then
      DSH_HOME='${dshHome}' \
        '${node}/bin/node' --expose-internals "$entry" \
        --profile web --dump-default-config >/dev/null
    fi

    DSH_PROFILE='${webProfileDir}' \
      DSH_PROFILE_MANIFEST='${webProfileManifest}' \
      DSH_PROFILE_PLUGINS='${builtins.toJSON profilePlugins}' \
      '${pkgs.python3}/bin/python3' - <<'PY'
    import json
    import os
    import pathlib

    profile_dir = pathlib.Path(os.environ["DSH_PROFILE"])
    manifest_path = pathlib.Path(os.environ["DSH_PROFILE_MANIFEST"])
    plugins = json.loads(os.environ["DSH_PROFILE_PLUGINS"])

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    dependencies = manifest.setdefault("dependencies", {})
    profile = manifest.setdefault("dsh", {}).setdefault("profile", {})
    bundles = profile.setdefault("bundles", [])

    for plugin in plugins:
        plugin_name = plugin["name"]
        plugin_path = pathlib.Path(plugin["path"])

        dependencies[plugin_name] = f"file:{plugin_path}"
        if plugin_name not in bundles:
            bundles.append(plugin_name)

        plugin_link = profile_dir / "node_modules" / plugin_name
        if plugin_link.is_symlink():
            if plugin_link.resolve() != plugin_path.resolve():
                plugin_link.unlink()
        elif plugin_link.exists():
            raise SystemExit(
                "deepseek-harness: refusing to replace an existing custom plugin at "
                f"{plugin_link}"
            )

        plugin_link.parent.mkdir(parents=True, exist_ok=True)
        if not plugin_link.exists():
            plugin_link.symlink_to(plugin_path, target_is_directory=True)

    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    PY

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
    new = 'const persistence = ctx.remote.$host.isLoopback || location.hostname === "${serviceHost}" ? "host" : "memory";'
    legacy = 'const persistence = "host";'

    if new in source:
        raise SystemExit(0)
    if source.count(old) == 1:
        source = source.replace(old, new)
    elif source.count(legacy) == 1:
        # Migrate the first deployed revision of this repository's patch.
        source = source.replace(legacy, new)
    else:
        raise SystemExit(
            "deepseek-harness: unsupported dsh settings bundle; "
            f"expected one remote-settings guard in {path}"
        )

    path.write_text(source, encoding="utf-8")
    print(f"deepseek-harness: enabled trusted remote settings in {path}")
    PY

    # Browser authentication: accept either a Tailscale Serve identity
    # assertion (user-owned devices) or a granted Tailscale app capability
    # (tagged devices) forwarded by the local HTTP proxy, and keep the signed
    # fallback cookie alive for a year. Version-sensitive and fail closed: an
    # unrecognized bundle stops the service instead of losing auth.
    connection_client='${connectionClient}'
    '${pkgs.python3}/bin/python3' - "$connection_client" <<'PY'
    import pathlib
    import sys

    path = pathlib.Path(sys.argv[1])
    if not path.is_file():
        raise SystemExit(f"deepseek-harness: missing connection client bundle: {path}")

    source = path.read_text(encoding="utf-8")

    # Keep the signed browser cookie for a year so the launch-token URL is
    # needed only for the rare fallback, not for routine access.
    old_default = "cookieMaxAgeDays: z.natural().min(1).default(30),"
    new_default = "cookieMaxAgeDays: z.natural().min(1).default(365),"

    # The marker and the injected block are versioned. Earlier revisions of this
    # repository injected only the login-based block; recognize that exact text
    # and upgrade it instead of leaving a released host on weaker authentication.
    marker_v1 = "Accept a Tailscale Serve identity assertion as browser authentication."
    marker_v2 = "Accept a Tailscale Serve identity assertion or app capability as browser authentication."
    anchor = "\t/**\n\t* Verify the authority-bound browser cookie on a Host request."
    auth_anchor = "isAuthenticated(request) {\n\t\tconst authority = requestAuthority(request.headers);"
    auth_replacement = "isAuthenticated(request) {\n\t\tif (this.isTailscaleIdentity(request)) return true;\n\t\tconst authority = requestAuthority(request.headers);"

    block_v1 = (
        "\t/**\n"
        "\t* Accept a Tailscale Serve identity assertion as browser authentication.\n"
        "\t* Serve strips any client-supplied copy and sets the header only for an\n"
        "\t* authenticated, user-owned peer, so a present login on a loopback request\n"
        "\t* proves the request reached this loopback-only server through the\n"
        "\t* deployment's Tailscale HTTP proxy. Funnel requests stay unauthenticated.\n"
        "\t* @param request - request headers plus optional socket facts.\n"
        "\t* @returns true only for a non-empty identity login on a loopback connection.\n"
        "\t*/\n"
        "\tisTailscaleIdentity(request) {\n"
        "\t\tconst login = header(request.headers, \"tailscale-user-login\");\n"
        "\t\tif (login === void 0 || login.trim() === \"\") return false;\n"
        "\t\tif (header(request.headers, \"tailscale-funnel-request\") !== void 0) return false;\n"
        "\t\tconst address = request.socket?.remoteAddress;\n"
        "\t\tif (typeof address === \"string\" && address !== \"::1\" && !address.startsWith(\"127.\") && !address.startsWith(\"::ffff:127.\")) return false;\n"
        "\t\treturn true;\n"
        "\t}\n"
        "\t/**\n"
        "\t* Verify the authority-bound browser cookie on a Host request."
    )
    block_v2 = (
        "\t/**\n"
        "\t* Accept a Tailscale Serve identity assertion or app capability as browser authentication.\n"
        "\t* Serve strips any client-supplied copy and only sets these headers for\n"
        "\t* requests that arrive through the deployment's Tailscale HTTP proxy. A\n"
        "\t* user-owned peer supplies a login; a tagged peer never does, so this\n"
        "\t* deployment grants tagged clients the app capability that Serve forwards\n"
        "\t* in Tailscale-App-Capabilities. Both headers are trusted only on a\n"
        "\t* loopback connection and never when Funnel marks the request.\n"
        "\t* @param request - request headers plus optional socket facts.\n"
        "\t* @returns true only for a loopback request carrying a trusted identity.\n"
        "\t*/\n"
        "\tisTailscaleIdentity(request) {\n"
        "\t\tif (header(request.headers, \"tailscale-funnel-request\") !== void 0) return false;\n"
        "\t\tconst address = request.socket?.remoteAddress;\n"
        "\t\tif (typeof address === \"string\" && address !== \"::1\" && !address.startsWith(\"127.\") && !address.startsWith(\"::ffff:127.\")) return false;\n"
        "\t\tconst login = header(request.headers, \"tailscale-user-login\");\n"
        "\t\tif (login !== void 0 && login.trim() !== \"\") return true;\n"
        "\t\tconst capabilities = header(request.headers, \"tailscale-app-capabilities\");\n"
        "\t\treturn capabilities !== void 0 && capabilities.includes(\"${appCapability}\");\n"
        "\t}\n"
        "\t/**\n"
        "\t* Verify the authority-bound browser cookie on a Host request."
    )

    def extend_cookie(text):
        return text.replace(old_default, new_default)

    if marker_v2 in source:
        if old_default in source:
            path.write_text(extend_cookie(source), encoding="utf-8")
            print(f"deepseek-harness: extended browser-session lifetime in {path}")
        raise SystemExit(0)

    if marker_v1 in source:
        if source.count(block_v1) != 1:
            raise SystemExit(
                "deepseek-harness: unsupported dsh connection client; "
                f"expected one previous identity block in {path}"
            )
        source = extend_cookie(source.replace(block_v1, block_v2))
        path.write_text(source, encoding="utf-8")
        print(f"deepseek-harness: upgraded Tailscale app-capability authentication in {path}")
        raise SystemExit(0)

    if source.count(old_default) != 1:
        raise SystemExit(
            "deepseek-harness: unsupported dsh connection client; "
            f"expected one cookieMaxAgeDays default in {path}"
        )
    if source.count(anchor) != 1:
        raise SystemExit(
            "deepseek-harness: unsupported dsh connection client; "
            f"expected one browser-auth JSDoc anchor in {path}"
        )
    if source.count(auth_anchor) != 1:
        raise SystemExit(
            "deepseek-harness: unsupported dsh connection client; "
            f"expected one isAuthenticated implementation in {path}"
        )

    source = extend_cookie(source)
    source = source.replace(anchor, block_v2)
    source = source.replace(auth_anchor, auth_replacement)
    path.write_text(source, encoding="utf-8")
    print(f"deepseek-harness: enabled Tailscale identity authentication in {path}")
    PY

    test -f "$entry"
    test -f '${sessionPluginPath}/package.json'
    test -f '${observabilityPluginPath}/package.json'
    test -f '${otelPluginPath}/package.json'
  '';

  startHarness = pkgs.writeShellScript "deepseek-harness-start" ''
    set -euo pipefail

    # agenix publishes the ingestion credential under ''${XDG_RUNTIME_DIR}, so
    # the path is expanded here rather than in the unit's Environment=, where
    # the value would depend on systemd's own variable expansion. Every other
    # service module in this repository resolves the same path the same way.
    export DSH_OBSERVABILITY_TOKEN_FILE="${openobserveToken}"

    # dsh-otel exports GenAI traces and metrics over OTLP/HTTP. Point it at
    # OpenObserve with the same ingestion credential and a stream-name header so
    # the spans land in their own stream. The standard OTEL_* variables win over
    # the plugin's cordis config; content capture stays off.
    otel_auth="$(cat "${openobserveToken}")"
    if [ -z "$otel_auth" ]; then
      echo "deepseek-harness: OpenObserve authentication header is empty" >&2
      exit 1
    fi
    export OTEL_EXPORTER_OTLP_ENDPOINT='${openobserveEndpoint}'
    export OTEL_EXPORTER_OTLP_HEADERS="Authorization=$otel_auth,stream-name=${openobserveOtlpStream}"
    export OTEL_SERVICE_NAME='deepseek-harness'
    export OTEL_RESOURCE_ATTRIBUTES='service.namespace=longred,deployment.environment=home-lab,host.name=${hostname}'

    # systemd attaches StandardOutput/StandardError before it creates any
    # managed directory, so an append: target below %L (or %S) fails with
    # status=209/STDOUT on a first start and restart-loops forever. Keep the
    # unit on journald and redirect the launch-token log here instead, where
    # this script has already created the directory. The token still stays out
    # of journald.
    log_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/log/deepseek-harness"
    install -d -m 0700 "$log_dir"
    touch "$log_dir/web.log"
    chmod 600 "$log_dir/web.log"

    # Nix-built Node cannot provide the loader internals through the native
    # fallback used by the current HMR dependency. Pass this Node-only flag
    # before the dsh entrypoint; NODE_OPTIONS is rejected for this flag.
    #
    # dsh stays on loopback. The Tailscale Service terminates TLS and
    # reverse-proxies to this port, injecting its identity headers, which the
    # patched connection bundle accepts as authentication. There is no local
    # TCP forward, so a remote tailnet peer cannot reach the backend with a
    # spoofed identity header.
    exec '${node}/bin/node' \
      --expose-internals \
      '${dshEntry}' \
      web \
      --host 127.0.0.1 \
      --port ${toString cfg.port} \
      --trusted-host ${serviceHost} \
      --trusted-host ${serviceHost}:443 \
      --no-open \
      >>"$log_dir/web.log" 2>&1
  '';
in
{
  imports = [ ./proxy.nix ];

  options.hostServices.deepseekHarness = {
    enable = lib.mkEnableOption "the DeepSeek Harness Web UI user service";

    dshVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.1.6-alpha.1";
      description = "Pinned @deepseek-ai/dsh version installed into the user runtime.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3080;
      description = "Loopback port the web server binds; the Tailscale Service proxies to it.";
    };

    runtimeDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/deepseek-harness/runtime";
      description = ''
        npm install root for the harness distribution.

        Give a host that also runs hostServices.deepseekHarnessAcp its own
        directory: both modules install the same package and patch the same
        bundle files, and their provisioning steps do not share a lock, so one
        tree can be written by two units at once.
      '';
    };

    dshHome = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/deepseek-harness/home";
      description = ''
        Harness home holding this service's sessions, settings, credentials and
        profiles. A host that also runs the ACP profile keeps the two homes
        apart, because the storages backend has no cross-process write lock.
      '';
    };

    serviceHost = lib.mkOption {
      type = lib.types.str;
      default = "deepseek-harness.tail388af.ts.net";
      description = ''
        Tailscale Service DNS name the browser opens. It is the trusted Host for
        the settings mirror and the authority the browser session is bound to,
        so it must match the `svc:` entry that proxies to this port.
      '';
    };

    appCapability = lib.mkOption {
      type = lib.types.str;
      default = "example.com/cap/deepseek-harness";
      description = ''
        App capability granted to tagged clients, which Serve forwards in
        Tailscale-App-Capabilities. The tailnet policy grant and the `appCaps`
        entry of the same Tailscale Service must use this name; give each host
        its own so one grant cannot authenticate another host's service.
      '';
    };

    openobserveEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://100.100.10.1:5080/api/default";
      description = "OpenObserve base endpoint receiving this host's session telemetry and OTLP export.";
    };

    ledgerStream = lib.mkOption {
      type = lib.types.str;
      default = "${hostname}_dsh_ledger";
      description = "OpenObserve stream receiving projected session events.";
    };

    opsStream = lib.mkOption {
      type = lib.types.str;
      default = "${hostname}_dsh_ops";
      description = "OpenObserve stream receiving agent error signals.";
    };

    otlpStream = lib.mkOption {
      type = lib.types.str;
      default = "${hostname}_dsh_llm";
      description = "OpenObserve stream receiving GenAI traces and metrics over OTLP/HTTP.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ node ];

    # Same declaration as openobserve-agent.nix, and the same value, so the
    # module merge keeps one definition. The harness exports session telemetry
    # with this ingestion credential.
    age.secrets.openobserve-agent-token.file = ../../secrets/openobserve-agent-token.age;
    age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

    systemd.user.services.deepseek-harness = {
      Unit = {
        Description = "DeepSeek Harness Web UI (Tailscale ${serviceHost} identity-proxied to loopback 127.0.0.1:${toString cfg.port})";
        After = [
          "agenix.service"
          "network-online.target"
        ];
        Requires = [ "agenix.service" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        WorkingDirectory = config.home.homeDirectory;
        ExecStartPre = ensureRuntime;
        ExecStart = startHarness;
        Environment = config.hostServices.proxyEnvironment ++ [
          "DSH_HOME=${dshHome}"
          # Keeps the shipped session-telemetry-otel row switched off: it only
          # implements FEEDBACK_ONLY and would otherwise upload feedback to its
          # default endpoint (https://harness-telemetry.deepseeksvc.com/v1/logs).
          # @longred/deepseek-harness-observability replaces it.
          "DSH_TELEMETRY_DISABLED=1"
          "DSH_OBSERVABILITY_URL=${openobserveEndpoint}"
          "DSH_OBSERVABILITY_LEDGER_STREAM=${openobserveLedgerStream}"
          "DSH_OBSERVABILITY_OPS_STREAM=${openobserveOpsStream}"
          "all_proxy="
          "ALL_PROXY="
          # A user-level service has the desktop environment available, but the
          # native picker would open on the NUC display instead of in the Web UI.
          "DISPLAY="
          "WAYLAND_DISPLAY="
        ];
        # The harness prints its launch-token URL to stdout. startHarness creates
        # the 0600 log file and redirects the Node process to it, so the token
        # does not persist in journald (see the ordering note there).
        Restart = "always";
        RestartSec = "5s";
        TimeoutStartSec = "15min";
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
