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
  pluginLink = "${config.home.homeDirectory}/.config/opencode/node_modules/${pluginName}";
  openobserveEndpoint = "http://100.100.10.1:5080/api/default";
  openobserveTracesStream = "nuc_opencode_traces";
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
    plugin_link='${pluginLink}'
    plugin_path='${pluginPath}'

    mkdir -p "$(dirname "$config_file")" "$(dirname "$plugin_link")"
    if [ -e "$plugin_link" ] && [ ! -L "$plugin_link" ]; then
      backup="$plugin_link.hm-backup.$(date +%s)"
      mv "$plugin_link" "$backup"
      echo "opencode: backed up existing plugin to $backup" >&2
    fi
    ln -sfn "$plugin_path" "$plugin_link"

    O2_CONFIG="$config_file" \
      O2_PLUGIN_NAME='${pluginName}' \
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

    config.setdefault("$schema", "https://opencode.ai/config.json")
    plugins = config.get("plugin")
    if not isinstance(plugins, list):
        plugins = []
    if plugin_name not in plugins:
        plugins.append(plugin_name)
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

    # The plugin's current configuration interface uses OPENCODE_* variables.
    # Keep the standard OTEL_* variables too for the bundled OTLP exporters.
    export OPENCODE_ENABLE_TELEMETRY=1
    export OPENCODE_OTLP_ENDPOINT='${openobserveEndpoint}'
    export OPENCODE_OTLP_PROTOCOL='http/protobuf'
    export OPENCODE_OTLP_HEADERS="Authorization=$auth,stream-name=${openobserveTracesStream}"
    export OPENCODE_RESOURCE_ATTRIBUTES='service.namespace=longred,deployment.environment=home-lab,host.name=nuc'
    export OPENCODE_DISABLE_LOGS=1
    export OPENCODE_DISABLE_METRICS='session.count,token.usage,cost.usage,lines_of_code.count,lines_of_code.total,commit.count,tool.duration,cache.count,session.duration,message.count,session.token.total,session.cost.total,model.usage,retry.count'
    export OTEL_EXPORTER_OTLP_ENDPOINT='${openobserveEndpoint}'
    export OTEL_EXPORTER_OTLP_PROTOCOL='http/protobuf'
    export OTEL_EXPORTER_OTLP_HEADERS="Authorization=$auth,stream-name=${openobserveTracesStream}"
    export OTEL_SERVICE_NAME='opencode'
    export OTEL_RESOURCE_ATTRIBUTES="$OPENCODE_RESOURCE_ATTRIBUTES"

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
