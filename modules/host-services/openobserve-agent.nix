# Rootless OpenTelemetry host agent for the managed Linux machines.
#
# This follows OpenObserve's Linux integration: it exports host metrics and
# journald logs to OpenObserve. The collector runs as the managed user so it
# also observes Home Manager services without requiring a system-wide install.
{
  config,
  lib,
  pkgs,
  hostname,
  ...
}:
let
  inherit (config.hostServices) proxyEnvironment;
  inherit (config.hostServices.openobserveAgent) endpoint journaldStream tracesStream;

  collector = pkgs.opentelemetry-collector-contrib;
  collectorConfig = "${config.xdg.configHome}/opentelemetry-collector/config.yaml";
  authHeader = config.age.secrets.openobserve-agent-token.path;
  requiresLocalOpenObserve = config.hostServices.openobserveAgent.requiresLocalOpenObserve;
  garageTelemetryEnabled = hostname == "nuc";
  garageTracesStream = "${hostname}_garage_traces";

  garageReceiverConfig = lib.optionalString garageTelemetryEnabled (
    lib.concatStringsSep "\n" [
      "      otlp/garage:"
      "        protocols:"
      "          grpc:"
      "            endpoint: 127.0.0.1:4319"
      "      prometheus/garage:"
      "        config:"
      "          scrape_configs:"
      "            - job_name: garage"
      "              scrape_interval: 30s"
      "              static_configs:"
      "                - targets:"
      "                    - 127.0.0.1:3903"
    ]
  );

  garageExporterConfig = lib.optionalString garageTelemetryEnabled (
    lib.concatStringsSep "\n" [
      "      otlp_http/openobserve-garage-traces:"
      "        endpoint: ${endpoint}"
      "        headers:"
      ("          Authorization: \"" + "$" + "{env:OPENOBSERVE_AUTH}\"")
      "          stream-name: ${garageTracesStream}"
    ]
  );

  garagePipelineConfig = lib.optionalString garageTelemetryEnabled (
    lib.concatStringsSep "\n" [
      "        metrics/garage:"
      "          receivers: [prometheus/garage]"
      "          processors: [resource_detection/system, resource/garage, memory_limiter, batch]"
      "          exporters: [otlp_http/openobserve-metrics]"
      "        traces/garage:"
      "          receivers: [otlp/garage]"
      "          processors: [resource_detection/system, resource/garage, memory_limiter, batch]"
      "          exporters: [otlp_http/openobserve-garage-traces]"
    ]
  );

  collectorConfigText = ''
        receivers:
          journald:
            directory: /var/log/journal
          host_metrics:
            root_path: /
            collection_interval: 30s
            scrapers:
              cpu:
              disk:
              filesystem:
              load:
              memory:
              network:
              paging:
              processes:
          otlp:
            protocols:
              grpc:
                endpoint: 127.0.0.1:4317
              http:
                endpoint: 127.0.0.1:4318
    ${garageReceiverConfig}

        processors:
          resource_detection/system:
            detectors: [system]
            system:
              hostname_sources: [os]
          resource/garage:
            attributes:
              - key: service.name
                value: garage
                action: upsert
              - key: service.namespace
                value: longred
                action: upsert
              - key: deployment.environment
                value: home-lab
                action: upsert
          memory_limiter:
            check_interval: 1s
            limit_percentage: 75
            spike_limit_percentage: 15
          batch:
            send_batch_size: 1000
            timeout: 10s

        extensions:
          zpages:

        exporters:
          otlp_http/openobserve-metrics:
            endpoint: ${endpoint}
            headers:
              Authorization: "''${env:OPENOBSERVE_AUTH}"
          otlp_http/openobserve-logs:
            endpoint: ${endpoint}
            headers:
              Authorization: "''${env:OPENOBSERVE_AUTH}"
              stream-name: ${journaldStream}
          otlp_http/openobserve-traces:
            endpoint: ${endpoint}
            headers:
              Authorization: "''${env:OPENOBSERVE_AUTH}"
              stream-name: ${tracesStream}
    ${garageExporterConfig}

        service:
          extensions: [zpages]
          pipelines:
            metrics:
              receivers: [host_metrics]
              processors: [resource_detection/system, memory_limiter, batch]
              exporters: [otlp_http/openobserve-metrics]
            logs:
              receivers: [journald]
              processors: [resource_detection/system, memory_limiter, batch]
              exporters: [otlp_http/openobserve-logs]
            traces:
              receivers: [otlp]
              processors: [resource_detection/system, memory_limiter, batch]
              exporters: [otlp_http/openobserve-traces]
    ${garagePipelineConfig}
  '';

  startCollector = pkgs.writeShellScript "openobserve-agent-start" ''
    set -euo pipefail

    auth="$(cat "${authHeader}")"
    if [ -z "$auth" ]; then
      echo "openobserve-agent: authentication header is empty" >&2
      exit 1
    fi

    export OPENOBSERVE_AUTH="$auth"
    exec '${collector}/bin/otelcol-contrib' --config '${collectorConfig}'
  '';
in
{
  options.hostServices.openobserveAgent = {
    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://100.100.10.1:5080/api/default";
      description = "OpenObserve OTLP base endpoint for this machine.";
    };

    journaldStream = lib.mkOption {
      type = lib.types.str;
      default = "${hostname}_journald";
      description = "OpenObserve stream receiving journald records.";
    };

    tracesStream = lib.mkOption {
      type = lib.types.str;
      default = "${hostname}_traces";
      description = "OpenObserve stream receiving OTLP traces.";
    };

    requiresLocalOpenObserve = lib.mkOption {
      type = lib.types.bool;
      default = hostname == "nuc";
      description = "Whether this collector follows a local OpenObserve service.";
    };
  };

  imports = [ ./proxy.nix ];

  config = {
    age.secrets.openobserve-agent-token.file = ../../secrets/openobserve-agent-token.age;
    age.identityPaths = [
      "${config.home.homeDirectory}/.ssh/id_ed25519"
      "/etc/ssh/ssh_host_ed25519_key"
    ];

    home.packages = [ collector ];
    home.file."${collectorConfig}".text = collectorConfigText;

    systemd.user.services.openobserve-agent = {
      Unit = {
        Description = "OpenObserve ${hostname} host telemetry agent";
        PartOf = lib.optional requiresLocalOpenObserve "openobserve.service";
        After = [
          "agenix.service"
          "network-online.target"
        ]
        ++ lib.optional requiresLocalOpenObserve "openobserve.service";
        Requires = [ "agenix.service" ] ++ lib.optional requiresLocalOpenObserve "openobserve.service";
        Wants = [ "network-online.target" ];
      };
      Service = {
        Environment = proxyEnvironment;
        ExecStart = startCollector;
        Restart = "always";
        RestartSec = "10s";
        TimeoutStartSec = "30s";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
