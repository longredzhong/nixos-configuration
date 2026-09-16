# OpenCode headless server as an HM user-level systemd service (Fedora NUC).
#
# The OpenObserve plugin is packaged by Nix and linked into OpenCode's local
# node_modules directory. The service exports traces directly to OpenObserve;
# host metrics and journald logs remain the responsibility of openobserve-agent.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  opencodeBin = "${config.home.homeDirectory}/.pixi/envs/opencode/bin/opencode";
  opencodeConfig = "${config.home.homeDirectory}/.config/opencode/opencode.jsonc";
  pluginName = "@devtheops/opencode-plugin-otel";
  pluginPath = "${pkgs.opencode-plugin-otel}/lib/node_modules/${pluginName}";
  # Where earlier generations symlinked the plugin for OpenCode's npm loader.
  # The config now passes an absolute Nix store path, so the link is removed on
  # the next service start.
  legacyPluginLink = "${config.home.homeDirectory}/.config/opencode/node_modules/${pluginName}";
  openobserveEndpoint = "http://100.100.10.1:5080/api/default";
  # One stream name covers all three OTLP signals; OpenObserve keeps a separate
  # stream per signal type, so this becomes nuc_opencode (traces),
  # nuc_opencode (metrics) and nuc_opencode (logs).
  openobserveStream = "nuc_opencode";
  openobserveToken = config.age.secrets.opencode-openobserve-token.path;

  # Browser origins allowed to interact with the HTTP server (opencode serve --cors).
  serveOrigins = [
    "http://100.100.10.1:4096"
    "https://opencode.tail388af.ts.net"
  ];
  corsArgs = lib.concatMapStringsSep " " (origin: "--cors ${origin}") serveOrigins;

  ensurePluginAndConfig = pkgs.writeShellScript "opencode-openobserve-preflight" ''
    set -euo pipefail

    config_file='${opencodeConfig}'
    legacy_link='${legacyPluginLink}'

    mkdir -p "$(dirname "$config_file")"

    # Older generations symlinked the plugin into OpenCode's npm node_modules
    # and declared it by package name, which made OpenCode install the package
    # from the npm registry on every start (and fail when the registry was not
    # reachable). Drop that stale link; the config below points at the Nix store.
    if [ -L "$legacy_link" ]; then
      rm -f "$legacy_link"
    fi

    O2_CONFIG="$config_file" \
      O2_PLUGIN_NAME='${pluginName}' \
      O2_PLUGIN_PATH='${pluginPath}' \
      '${pkgs.python3}/bin/python3' - <<'PY'
    import json
    import os
    import pathlib
    import re
    import shutil
    import tempfile
    import time

    path = pathlib.Path(os.environ["O2_CONFIG"])
    plugin_name = os.environ["O2_PLUGIN_NAME"]

    def strip_jsonc_comments(text: str) -> str:
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
        lines = []
        for line in text.splitlines():
            in_string = False
            escaped = False
            comment_at = None
            for index, char in enumerate(line):
                if escaped:
                    escaped = False
                    continue
                if char == "\\":
                    escaped = True
                    continue
                if char == '"':
                    in_string = not in_string
                    continue
                if not in_string and char == "/" and line[index : index + 2] == "//":
                    comment_at = index
                    break
            lines.append(line if comment_at is None else line[:comment_at])
        return "\n".join(lines)

    config = {}
    if path.exists() and path.stat().st_size > 0:
        try:
            config = json.loads(strip_jsonc_comments(path.read_text(encoding="utf-8")))
        except json.JSONDecodeError as error:
            raise SystemExit(f"Existing OpenCode config is not valid JSON/JSONC: {path} ({error})")
        if not isinstance(config, dict):
            raise SystemExit(f"Existing OpenCode config root is not an object: {path}")

    plugin_path = os.environ["O2_PLUGIN_PATH"]

    config.setdefault("$schema", "https://opencode.ai/config.json")
    plugins = config.get("plugin")
    if not isinstance(plugins, list):
        plugins = []
    # Drop the legacy package-name spec (OpenCode would install it from npm on
    # every start) and any stale store path from an older generation before
    # adding the current absolute path.
    plugins = [
        entry
        for entry in plugins
        if entry != plugin_name
        and not (
            isinstance(entry, str)
            and entry.startswith("/nix/store/")
            and entry.endswith(plugin_name)
        )
    ]
    if plugin_path not in plugins:
        plugins.append(plugin_path)
    config["plugin"] = plugins

    if path.exists() and path.read_text(encoding="utf-8") == json.dumps(config, indent=2) + "\n":
        raise SystemExit(0)

    if path.exists():
        backup = path.with_name(f"{path.name}.bak.{int(time.time())}")
        shutil.copy2(path, backup)

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="opencode.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(config, output, indent=2)
            output.write("\n")
        os.replace(temporary, path)
    except Exception:
        try:
            pathlib.Path(temporary).unlink()
        except FileNotFoundError:
            pass
        raise
    PY
  '';

  startOpenCode = pkgs.writeShellScript "opencode-start" ''
    set -euo pipefail

    auth="$(cat "${openobserveToken}")"
    if [ -z "$auth" ]; then
      echo "opencode: OpenObserve authentication header is empty" >&2
      exit 1
    fi

    # The plugin reads OPENCODE_* variables. Do not export
    # OTEL_EXPORTER_OTLP_*: OpenCode's own Effect/AI-SDK tracing reads those and
    # would export tens of thousands of internal spans (SessionProcessor.*,
    # sql.execute, http.server, Plugin.trigger, ...) into the same stream. They
    # carry no token accounting but still force OpenObserve to classify the
    # stream as an LLM stream and bury the plugin's real LLM spans.
    #
    # Metrics and log events stay enabled on purpose: the token/cost counters
    # (`token.usage`, `cost.usage`, `session.token.total`, `session.cost.total`)
    # and the session lifecycle log events are the usage signals this service is
    # observed for. Trace spans DO carry prompt and tool content
    # (`llm.input_messages`, `input.value`), and that capture has no per-field
    # opt-out; see docs/openobserve.md before widening access.
    export OPENCODE_ENABLE_TELEMETRY=1
    export OPENCODE_OTLP_ENDPOINT='${openobserveEndpoint}'
    export OPENCODE_OTLP_PROTOCOL='http/protobuf'
    export OPENCODE_OTLP_HEADERS="Authorization=$auth,stream-name=${openobserveStream}"
    export OPENCODE_RESOURCE_ATTRIBUTES='service.namespace=longred,deployment.environment=home-lab,host.name=nuc'

    exec '${opencodeBin}' serve --hostname 0.0.0.0 --port 4096 ${corsArgs}
  '';
in
{
  imports = [ ./proxy.nix ];

  age.secrets.opencode-openobserve-token.file = ../../secrets/opencode-openobserve-token.age;
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  systemd.user.services.opencode = {
    Unit = {
      Description = "OpenCode headless server with OpenObserve tracing (port 4096)";
      After = [
        "agenix.service"
        "network-online.target"
        "openobserve.service"
      ];
      Requires = [
        "agenix.service"
        "openobserve.service"
      ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStartPre = ensurePluginAndConfig;
      ExecStart = startOpenCode;
      # Route LLM/API traffic through the metacube proxy (see ~/.bashrc set_proxy).
      Environment = config.hostServices.proxyEnvironment;
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
