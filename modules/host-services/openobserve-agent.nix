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
  inherit (config.hostServices.openobserveAgent) endpoint journaldStream tracesStream;

  collector = pkgs.opentelemetry-collector-contrib;
  collectorConfig = "${config.xdg.configHome}/opentelemetry-collector/config.yaml";
  authHeader = config.age.secrets.openobserve-agent-token.path;
  requiresLocalOpenObserve = config.hostServices.openobserveAgent.requiresLocalOpenObserve;
  garageTelemetryEnabled = hostname == "nuc";
  garageTracesStream = "${hostname}_garage_traces";
  traceSamplingPercentage = config.hostServices.openobserveAgent.garageTraceSamplingPercentage;
  excludedLogUnits = config.hostServices.openobserveAgent.excludeLogUnits;

  # Drop high-volume, self-referential journald sources before export:
  # OpenObserve's own access logs otherwise dominate nuc_journald.
  logFilterProcessorConfig = lib.optionalString (excludedLogUnits != []) (
    lib.concatStringsSep "\n" (
      [
        "      filter/drop-excluded-logs:"
        "        error_mode: ignore"
        "        log_conditions:"
      ]
      ++ map (
        unit: "          - 'log.body[\"_SYSTEMD_USER_UNIT\"] == \"${unit}\" or log.body[\"_SYSTEMD_UNIT\"] == \"${unit}\"'"
      ) excludedLogUnits
    )
  );

  # Garage emits millions of S3 request spans per day; sample them before
  # batching so traces stay useful without dominating storage.
  garageSamplerProcessorConfig = lib.optionalString garageTelemetryEnabled (
    lib.concatStringsSep "\n" [
      "      probabilistic_sampler/garage-traces:"
      "        sampling_percentage: ${toString traceSamplingPercentage}"
    ]
  );

  # Multi-disk / btrfs monitoring fix. gopsutil (used by hostmetrics) treats
  # every non-root mount of a device as a bind mount and drops it unless
  # include_virtual_filesystems is enabled, which hides btrfs subvolumes such
  # as "/" and "/home". Enabling it also exposes tmpfs, /proc, /sys and
  # container overlays, so we filter those back out with the pseudo-filesystem
  # and volatile mount-point patterns used by node_exporter and common Grafana
  # dashboards. Subvolumes that share one device are de-duplicated in the
  # dashboard queries instead of here.
  filesystemScraperConfig = lib.concatStringsSep "\n" [
    "          filesystem:"
    "            include_virtual_filesystems: true"
    "            metrics:"
    "              system.filesystem.utilization:"
    "                enabled: true"
    "            exclude_fs_types:"
    "              match_type: regexp"
    "              fs_types:"
    "                - '^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|efivarfs|erofs|fuse\\..*|fuse-overlayfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|ramfs|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tmpfs|tracefs)$'"
    "            exclude_mount_points:"
    "              match_type: regexp"
    "              mount_points:"
    "                - '^/(dev|proc|sys|mnt/wslg|snap/.+|var/lib/docker/.+|var/lib/containers/storage/.+|var/lib/kubelet/.+)(/.*)?$'"
  ];

  logPipelineProcessors =
    [ "resource_detection/system" ]
    ++ lib.optional (excludedLogUnits != []) "filter/drop-excluded-logs"
    ++ [ "memory_limiter" "batch" ];

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
      "              scrape_timeout: 25s"
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
      "          processors: [resource_detection/system, resource/garage, probabilistic_sampler/garage-traces, memory_limiter, batch]"
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
    ${filesystemScraperConfig}
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
    ${logFilterProcessorConfig}
    ${garageSamplerProcessorConfig}

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
              receivers: [host_metrics, otlp]
              processors: [resource_detection/system, memory_limiter, batch]
              exporters: [otlp_http/openobserve-metrics]
            logs:
              receivers: [journald]
              processors: [${lib.concatStringsSep ", " logPipelineProcessors}]
              exporters: [otlp_http/openobserve-logs]
            traces:
              receivers: [otlp]
              processors: [resource_detection/system, memory_limiter, batch]
              exporters: [otlp_http/openobserve-traces]
    ${garagePipelineConfig}
  '';

  # Materialize the generated config as its own store file and reference that
  # store path from ExecStart. With the stable ~/.config symlink in ExecStart a
  # config-only change left the systemd unit byte-identical, so Home Manager
  # (sd-switch) never restarted the collector. The store path changes with the
  # content, so a config change now changes the unit and restarts the service.
  collectorConfigFile = pkgs.writeText "opentelemetry-collector-config.yaml" collectorConfigText;

  startCollector = pkgs.writeShellScript "openobserve-agent-start" ''
    set -euo pipefail

    auth="$(cat "${authHeader}")"
    if [ -z "$auth" ]; then
      echo "openobserve-agent: authentication header is empty" >&2
      exit 1
    fi

    export OPENOBSERVE_AUTH="$auth"
    exec '${collector}/bin/otelcol-contrib' --config '${collectorConfigFile}'
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

    garageTraceSamplingPercentage = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 1;
      description = ''
        Percentage of Garage S3 spans kept by the probabilistic sampler.
        Garage emits millions of spans per day; lowering this shrinks trace
        volume while keeping a representative sample.
      '';
    };

    excludeLogUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "openobserve.service" ];
      description = ''
        systemd units whose journald records are dropped before export.
        OpenObserve's own access logs otherwise dominate the journald stream.
      '';
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
    home.file."${collectorConfig}".source = collectorConfigFile;

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
        # The collector only talks to Tailscale/loopback endpoints. Keep proxy
        # variables unset so OTLP exports do not take an extra local-proxy hop,
        # which previously showed up as export timeouts and failed scrapes.
        Environment = [
          "no_proxy=localhost,127.0.0.1,::1,100.64.0.0/10,172.16.100.10"
          "NO_PROXY=localhost,127.0.0.1,::1,100.64.0.0/10,172.16.100.10"
        ];
        ExecStart = startCollector;
        Restart = "always";
        RestartSec = "10s";
        TimeoutStartSec = "30s";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
