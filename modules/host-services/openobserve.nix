# OpenObserve single-node service on the Fedora NUC.
#
# The SQLite metadata, WAL, and local cache stay on /data. Stream data is
# written to the dedicated Garage S3 bucket created by the provisioning step.
# The container uses host networking so it can reach Garage on 127.0.0.1:3900;
# OpenObserve itself is bound to the NUC's Tailscale address only.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.hostServices) proxyEnvironment;

  openobserveImage = "public.ecr.aws/zinclabs/openobserve:v1.0.0";
  openobserveDataDir = "/data/openobserve";
  openobserveDataVolume = "${openobserveDataDir}/data";
  openobserveEnvFile = "${openobserveDataDir}/openobserve.env";
  listenAddress = "100.100.10.1";
  httpPort = 5080;
  grpcPort = 5081;
  bucketName = "openobserve";
  keyName = "openobserve";

  garageConfig = "${config.xdg.configHome}/garage/garage.toml";
  garageRpcSecret = config.age.secrets.garage-rpc-secret.path;
  garageAdminToken = config.age.secrets.garage-admin-token.path;
  garage = "${pkgs.garage_2}/bin/garage";
  podman = "${pkgs.podman}/bin/podman";
  coreutils = "${pkgs.coreutils}/bin";
  grep = "${pkgs.gnugrep}/bin/grep";
  awk = "${pkgs.gawk}/bin/awk";
  openssl = "${pkgs.openssl}/bin/openssl";

  # --- alerting -----------------------------------------------------------
  # Alert rules and their notification destination are provisioned through the
  # OpenObserve API so that they live in this repository and survive a rebuild.
  # The routes below were verified against the running instance: alert rules
  # live under /api/v2/<org>/alerts, while message templates and destinations
  # live under /api/<org>/alerts/.
  alertOrg = "default";
  alertTemplateName = "ntfy";
  alertDestinationName = "ntfy";

  # Publishing topic on the notification host. hosts/longred-vm/ntfy.nix grants
  # anonymous write-only access to exactly this topic.
  alertTopic = "homelab-alerts";
  ntfyPublishUrl = "https://longred-vm.tail388af.ts.net/${alertTopic}";

  curl = "${pkgs.curl}/bin/curl";
  cut = "${coreutils}/cut";
  seq = "${coreutils}/seq";

  # The destination POSTs the rendered body to the topic path, where the body
  # becomes the notification text; the rest of the notification metadata travels
  # as headers. Only template variables confirmed against the running instance
  # are used here.
  alertTemplateFile = pkgs.writeText "openobserve-alert-template.json" (
    builtins.toJSON {
      name = alertTemplateName;
      type = "http";
      body = ''
        {alert_level}: {alert_name}
        {alert_description}
        threshold {alert_operator} {alert_threshold}, current {alert_agg_value}
        stream {stream_name} at {alert_trigger_time_str}'';
    }
  );

  alertDestinationFile = pkgs.writeText "openobserve-alert-destination.json" (
    builtins.toJSON {
      name = alertDestinationName;
      type = "http";
      url = ntfyPublishUrl;
      method = "post";

      # Required for an alert destination: without a template the destination is
      # stored as a pipeline destination and cannot be attached to an alert.
      template = alertTemplateName;

      skip_tls_verify = false;
      headers = {
        Title = "OpenObserve alert";
        Priority = "4";
        Tags = "rotating_light";
        "Content-Type" = "text/plain; charset=utf-8";
      };
    }
  );

  # Thresholds are set against measured baselines rather than round numbers: the
  # NUC's 1-minute load peaked at 20.01 with the disks idle enough that most of
  # it is wait time, its /data volume keeps roughly 1.37 TB free, and the
  # thinkbook's / already sits near 79% used.
  alertRules = [
    {
      name = "node_disk_space_low";
      stream = "system_filesystem_usage";
      description = "Free space below 50 GiB on a monitored mountpoint.";
      operator = ">=";
      threshold = 1;
      silence = 360;
      sql = ''
        SELECT count(*) AS low_mountpoints FROM "system_filesystem_usage"
        WHERE state = 'free' AND value < 50000000000
          AND (mountpoint = '/' OR mountpoint = '/data' OR mountpoint = '/home')
      '';
    }
    {
      name = "node_load_average_high";
      stream = "system_cpu_load_average_1m";
      description = "1-minute load average reached 32; the measured peak on the NUC is about 20 and is dominated by disk wait.";
      operator = ">=";
      threshold = 32;
      silence = 60;
      sql = ''
        SELECT max(value) AS max_load FROM "system_cpu_load_average_1m"
      '';
    }
    {
      name = "garage_disk_available_low";
      stream = "garage_local_disk_avail";
      description = "Garage reports less than 200 GB available on its data volume.";
      operator = "<";
      threshold = 200000000000;
      silence = 360;
      sql = ''
        SELECT min(value) AS available_bytes FROM "garage_local_disk_avail"
        WHERE volume = 'data'
      '';
    }
  ];

  alertRuleFiles = map (rule: {
    inherit (rule) name;
    file = pkgs.writeText "openobserve-alert-${rule.name}.json" (
      builtins.toJSON {
        name = rule.name;
        stream_type = "metrics";
        stream_name = rule.stream;
        is_real_time = false;
        description = rule.description;
        query_condition = {
          type = "sql";
          sql = rule.sql;
        };
        trigger_condition = {
          period = 15;
          operator = rule.operator;
          threshold = rule.threshold;
          frequency = 5;
          frequency_type = "minutes";
          silence = rule.silence;
        };
        destinations = [ alertDestinationName ];
        enabled = true;
      }
    );
  }) alertRules;

  # One "<name> <payload-file>" line per rule, so the shell side stays a plain
  # loop instead of a generated block of conditionals.
  alertRuleManifest = pkgs.writeText "openobserve-alert-rules.manifest" (
    lib.concatMapStrings (rule: "${rule.name} ${rule.file}\n") alertRuleFiles
  );

  provisionAlerts = pkgs.writeShellScript "openobserve-alerts-provision" ''
    set -euo pipefail

    env_file='${openobserveEnvFile}'
    base='http://127.0.0.1:${toString httpPort}'
    org='${alertOrg}'

    # The root credential is generated on first start and stays on the data
    # disk. Read it at runtime; never print it.
    root_email="$('${grep}' -m1 '^ZO_ROOT_USER_EMAIL=' "$env_file" | '${cut}' -d= -f2-)"
    root_password="$('${grep}' -m1 '^ZO_ROOT_USER_PASSWORD=' "$env_file" | '${cut}' -d= -f2-)"
    if [ -z "$root_email" ] || [ -z "$root_password" ]; then
      echo "openobserve-alerts: no root credential in $env_file" >&2
      exit 1
    fi

    # A refused or half-open connection is expected while the container is
    # still starting, so this probe stays silent and only reports the status
    # code. The readiness loop below is what decides success.
    status() {
      '${curl}' -s --max-time 15 -o /dev/null -w '%{http_code}' \
        -u "$root_email:$root_password" "$base$1" 2>/dev/null || true
    }

    get() {
      '${curl}' -fsS -u "$root_email:$root_password" "$base$1"
    }

    post() {
      '${curl}' -fsS -u "$root_email:$root_password" -X POST \
        -H 'Content-Type: application/json' --data-binary "@$2" "$base$1" >/dev/null
    }

    # Probe an authenticated route rather than /healthz: a listener that accepts
    # connections but cannot serve the API yet must not count as ready.
    ready=""
    for attempt in $('${seq}' 1 60); do
      if [ "$(status "/api/$org/streams")" = "200" ]; then
        ready=1
        break
      fi
      sleep 2
    done
    if [ -z "$ready" ]; then
      echo "openobserve-alerts: the API did not become reachable" >&2
      exit 1
    fi

    if [ "$(status "/api/$org/alerts/templates/${alertTemplateName}")" != "200" ]; then
      post "/api/$org/alerts/templates" '${alertTemplateFile}'
      echo "openobserve-alerts: created template ${alertTemplateName}"
    fi

    if [ "$(status "/api/$org/alerts/destinations/${alertDestinationName}")" != "200" ]; then
      post "/api/$org/alerts/destinations?module=alert" '${alertDestinationFile}'
      echo "openobserve-alerts: created destination ${alertDestinationName}"
    fi

    alert_list="$(get "/api/v2/$org/alerts")"
    while read -r name file; do
      [ -n "$name" ] || continue
      if printf '%s' "$alert_list" | '${grep}' -qF "\"$name\""; then
        continue
      fi
      post "/api/v2/$org/alerts" "$file"
      echo "openobserve-alerts: created alert rule $name"
    done < '${alertRuleManifest}'
  '';

  provisionOpenObserve = pkgs.writeShellScript "openobserve-provision" ''
    set -euo pipefail

    data_dir='${openobserveDataDir}'
    env_file='${openobserveEnvFile}'
    bucket='${bucketName}'
    key_name='${keyName}'

    ensure_setting() {
      local variable="$1"
      local value="$2"
      if ! '${grep}' -q "^''${variable}=" "$env_file"; then
        printf '%s=%s\n' "$variable" "$value" >>"$env_file"
      fi
    }

    garage() {
      '${garage}' \
        --config '${garageConfig}' \
        --rpc-secret-file "${garageRpcSecret}" \
        --admin-token-file "${garageAdminToken}" \
        "$@"
    }

    '${coreutils}/mkdir' -p "${openobserveDataVolume}"
    '${coreutils}/chmod' 700 "$data_dir"

    # Credentials are generated once and kept on the data disk. Do not put
    # them in the Nix expression: that would copy them into /nix/store.
    if [ -f "$env_file" ]; then
      for variable in \
        ZO_ROOT_USER_EMAIL \
        ZO_ROOT_USER_PASSWORD \
        ZO_S3_ACCESS_KEY \
        ZO_S3_SECRET_KEY; do
        if ! '${grep}' -q "^''${variable}=." "$env_file"; then
          echo "openobserve: $env_file is missing $variable" >&2
          exit 1
        fi
      done
      # Move small, low-volume workloads out of the local WAL promptly. These
      # values keep the NUC's S3 durability delay bounded without changing
      # stream retention policy.
      ensure_setting ZO_MAX_FILE_RETENTION_TIME 60
      ensure_setting ZO_FILE_PUSH_INTERVAL 10
      # OpenObserve refuses to deliver an alert webhook to any address that
      # resolves into private space, which includes loopback, the LAN and the
      # Tailscale range. The only notification endpoint this deployment has is
      # the self-hosted ntfy on the tailnet, so the guard has to be off for
      # alerting to work at all.
      #
      # Compensating controls, because this disables a real protection:
      #   - the HTTP listener binds the Tailscale address only (ZO_HTTP_ADDR),
      #     so no LAN or public client can reach the API;
      #   - the organization has a single root user, so the "untrusted tenant
      #     makes the server fetch an internal URL" threat does not apply here.
      # Revisit if a second user or an untrusted ingestion path is ever added.
      ensure_setting ZO_SKIP_SSRF_CHECKS true
      '${coreutils}/chmod' 600 "$env_file"
      exit 0
    fi

    # Garage may have been started before its RPC endpoint is ready. Use
    # `status` here because the pinned Garage 2.3.0 CLI has no `health`
    # subcommand.
    for attempt in $(seq 1 60); do
      if garage status >/dev/null 2>&1; then
        break
      fi
      if [ "$attempt" -eq 60 ]; then
        echo "openobserve: Garage did not become healthy within 120 seconds" >&2
        exit 1
      fi
      sleep 2
    done

    if ! garage bucket info "$bucket" >/dev/null 2>&1; then
      garage bucket create "$bucket" >/dev/null
    fi

    # Garage prints the secret only when a key is created (and, on current
    # versions, when key info is requested with --show-secret). Keeping the
    # parsing here makes a partially completed first start recoverable.
    if ! garage key info "$key_name" >/dev/null 2>&1; then
      garage key create "$key_name" >/dev/null
    fi

    key_info="$(garage key info --show-secret "$key_name")"
    access_key="$(printf '%s\n' "$key_info" | '${awk}' -F': *' '$1 == "Key ID" { print $2; exit }')"
    secret_key="$(printf '%s\n' "$key_info" | '${awk}' -F': *' '$1 == "Secret key" { print $2; exit }')"
    if [ -z "$access_key" ] || [ -z "$secret_key" ]; then
      echo "openobserve: Garage did not return credentials for key $key_name" >&2
      echo "openobserve: rotate the key or run 'garage key info --show-secret $key_name' manually" >&2
      exit 1
    fi

    # OpenObserve needs object read/write/list/delete access. Bucket-owner
    # administration is intentionally not granted to the application key.
    garage bucket allow --read --write "$bucket" --key "$key_name" >/dev/null

    root_password="O2!OpenObserve-$('${openssl}' rand -hex 24)"
    tmp_file="$('${coreutils}/mktemp' "$data_dir/.openobserve.env.XXXXXX")"
    trap '${coreutils}/rm -f "$tmp_file"' EXIT
    {
      printf 'ZO_ROOT_USER_EMAIL=%s\n' 'root@openobserve.local'
      printf 'ZO_ROOT_USER_PASSWORD=%s\n' "$root_password"
      printf 'ZO_LOCAL_MODE=%s\n' 'true'
      printf 'ZO_LOCAL_MODE_STORAGE=%s\n' 's3'
      printf 'ZO_META_STORE=%s\n' 'sqlite'
      printf 'ZO_DATA_DIR=%s\n' '/data'
      printf 'ZO_S3_PROVIDER=%s\n' 's3'
      printf 'ZO_S3_SERVER_URL=%s\n' 'http://127.0.0.1:3900'
      printf 'ZO_S3_REGION_NAME=%s\n' 'garage'
      printf 'ZO_S3_BUCKET_NAME=%s\n' "$bucket"
      printf 'ZO_S3_BUCKET_PREFIX=%s\n' 'openobserve/'
      printf 'ZO_S3_ACCESS_KEY=%s\n' "$access_key"
      printf 'ZO_S3_SECRET_KEY=%s\n' "$secret_key"
      # Garage is an S3-compatible HTTP/1.1 endpoint. Path-style requests are
      # required because a loopback endpoint cannot resolve bucket subdomains.
      printf 'ZO_S3_FEATURE_FORCE_HOSTED_STYLE=%s\n' 'false'
      printf 'ZO_S3_FEATURE_HTTP1_ONLY=%s\n' 'true'
      printf 'ZO_MAX_FILE_RETENTION_TIME=%s\n' '60'
      printf 'ZO_FILE_PUSH_INTERVAL=%s\n' '10'
      printf 'ZO_HTTP_ADDR=%s\n' '${listenAddress}'
      printf 'ZO_HTTP_PORT=%s\n' '${toString httpPort}'
      printf 'ZO_GRPC_ADDR=%s\n' '${listenAddress}'
      printf 'ZO_GRPC_PORT=%s\n' '${toString grpcPort}'
      printf 'ZO_WEB_URL=%s\n' 'http://${listenAddress}:${toString httpPort}'
      printf 'ZO_TELEMETRY=%s\n' 'false'
      # See the note in the existing-file branch above: the alert destination is
      # a tailnet address, which the SSRF guard would otherwise refuse.
      printf 'ZO_SKIP_SSRF_CHECKS=%s\n' 'true'
      printf 'ZO_MMDB_DISABLE_DOWNLOAD=%s\n' 'true'
      printf 'RUST_LOG=%s\n' 'info'
    } >"$tmp_file"
    '${coreutils}/chmod' 600 "$tmp_file"
    '${coreutils}/mv' "$tmp_file" "$env_file"
    trap - EXIT
    echo "openobserve: Garage bucket/key initialized and local env file created"
  '';

  startOpenObserve = pkgs.writeShellScript "openobserve-start" ''
    set -euo pipefail

    openobserve_pid=""
    loopback_pid=""

    cleanup() {
      trap - EXIT INT TERM
      if [ -n "$loopback_pid" ]; then
        kill "$loopback_pid" 2>/dev/null || true
      fi
      if [ -n "$openobserve_pid" ]; then
        kill "$openobserve_pid" 2>/dev/null || true
      fi
      wait "$loopback_pid" 2>/dev/null || true
      wait "$openobserve_pid" 2>/dev/null || true
    }
    trap cleanup EXIT INT TERM

    '${podman}' run \
      --name openobserve \
      --rm \
      --replace \
      --pull missing \
      --network host \
      --security-opt label=disable \
      --http-proxy=false \
      --env-file '${openobserveEnvFile}' \
      --volume '${openobserveDataVolume}:/data' \
      '${openobserveImage}' &
    openobserve_pid=$!

    # The built-in MCP server (https://<instance>/api/<org>/mcp) executes its
    # tools through OpenObserve's own HTTP API, which it calls at
    # http://localhost:<ZO_HTTP_PORT>. This service binds the Tailscale address
    # only (--network host plus ZO_HTTP_ADDR), so nothing answers on loopback
    # and every MCP tool call fails with "error sending request for url
    # (http://localhost:<ZO_HTTP_PORT>/...)". Bridge the same port on loopback
    # only: the unit shares the host network namespace, so this is the address
    # the container sees, and no new address is reachable from the network.
    '${pkgs.socat}/bin/socat' \
      TCP-LISTEN:${toString httpPort},bind=127.0.0.1,reuseaddr,fork \
      TCP:${listenAddress}:${toString httpPort} &
    loopback_pid=$!

    wait -n "$openobserve_pid" "$loopback_pid"
  '';
in
{
  imports = [ ./proxy.nix ];

  age.secrets.garage-rpc-secret.file = ../../secrets/garage-rpc-secret.age;
  age.secrets.garage-admin-token.file = ../../secrets/garage-admin-token.age;
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  systemd.user.services.openobserve = {
    Unit = {
      Description = "OpenObserve single-node observability platform";
      After = [
        "agenix.service"
        "garage.service"
        "network-online.target"
      ];
      Requires = [
        "agenix.service"
        "garage.service"
      ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Environment = proxyEnvironment;
      ExecStartPre = [
        "${coreutils}/mkdir -p ${openobserveDataVolume}"
        provisionOpenObserve
      ];
      ExecStart = startOpenObserve;
      ExecStop = "${podman} stop -t 20 openobserve";
      LimitNOFILE = 65535;
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "180s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Additive on purpose: this unit only creates alert templates, destinations
  # and rules through the API, so applying it leaves the running OpenObserve
  # container untouched. `Wants` rather than `Requires` keeps a provisioning
  # failure from taking the observability stack down with it; re-run it by hand
  # with `systemctl --user start openobserve-alerts` once the cause is fixed.
  systemd.user.services.openobserve-alerts = {
    Unit = {
      Description = "Provision OpenObserve alert templates, destinations and rules";
      After = [ "openobserve.service" ];
      Wants = [ "openobserve.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = provisionAlerts;
      RemainAfterExit = false;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
