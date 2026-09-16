# mihomo (Clash Meta) rule-based proxy as a Home Manager user service.
#
# The service listens on a local mixed HTTP/SOCKS port, serves the metacubexd
# dashboard from its own RESTful controller, and renders its runtime config
# from a checked-in template plus runtime secret files. Subscription URLs and
# node credentials stay out of the Nix store and are written mode 0600 into
# the systemd state directory.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hostServices.mihomo;

  # Track nixpkgs-unstable so the controller/API security fixes land without
  # waiting for the stable channel.
  mihomoPkg = pkgs.unstable.mihomo;

  template = ../../config/mihomo/config.template.yaml;
  renderer = ../../config/mihomo/render.py;
  metricsScript = ../../config/mihomo/metrics.py;

  # Secrets the user drops in themselves (subscription URL, custom nodes and
  # rules) live under XDG config; everything mihomo writes at runtime (rendered
  # config, controller secret, provider/rule caches, GEO databases) lives under
  # the systemd StateDirectory, which is separate and private.
  secretDir = "${config.xdg.configHome}/mihomo";
  stateDir = "${config.xdg.stateHome}/mihomo";

  renderConfig = pkgs.writeShellScript "mihomo-render-config" ''
    set -euo pipefail
    install -d -m 0700 '${stateDir}' '${stateDir}/providers'
    exec '${pkgs.python3}/bin/python3' '${renderer}' \
      '${template}' \
      '${cfg.subscriptionUrlFile}' \
      '${cfg.customProxiesFile}' \
      '${cfg.customRulesFile}' \
      '${cfg.rulesOverrideUrl}' \
      '${cfg.controllerHost}:${toString cfg.controllerPort}' \
      '${if cfg.allowLan then "true" else "false"}' \
      '${lib.concatStringsSep "," cfg.lanAllowedIps}' \
      '${stateDir}'
  '';

  startMihomo = pkgs.writeShellScript "mihomo-start" ''
    set -euo pipefail
    # Never let mihomo (or its provider downloads) consult an ambient proxy
    # that may point back at this very listener.
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    export no_proxy=localhost,127.0.0.1,::1 NO_PROXY=localhost,127.0.0.1,::1
    exec '${lib.getExe mihomoPkg}' \
      -d '${stateDir}' \
      -f '${stateDir}/config.yaml' \
      -ext-ui '${pkgs.metacubexd}'
  '';

  collectMetrics = pkgs.writeShellScript "mihomo-collect-metrics" ''
    set -euo pipefail
    exec '${pkgs.python3}/bin/python3' '${metricsScript}' \
      'http://${cfg.controllerHost}:${toString cfg.controllerPort}' \
      '${stateDir}/controller.secret' \
      '${cfg.metrics.otlpEndpoint}'
  '';
in
{
  imports = [ ./proxy.nix ];

  options.hostServices.mihomo = {
    enable = lib.mkEnableOption "mihomo rule-based proxy with a local dashboard";

    mixedPort = lib.mkOption {
      type = lib.types.port;
      default = 7890;
      description = "Local mixed HTTP/SOCKS proxy port.";
    };

    controllerHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Interface the RESTful controller and dashboard bind to. Set this to a
        LAN or Tailscale address to expose the dashboard there; the metrics
        collector follows the same address.
      '';
    };

    controllerPort = lib.mkOption {
      type = lib.types.port;
      default = 9091;
      description = "RESTful controller and dashboard port (9090 is Cockpit on the NUC).";
    };

    allowLan = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the mixed proxy port accepts LAN clients. When enabled, only
        addresses in lanAllowedIps may use the proxy unless the list is empty.
      '';
    };

    lanAllowedIps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "127.0.0.0/8" "100.64.0.0/10" ];
      description = ''
        CIDRs allowed to use the mixed proxy port when allowLan is enabled.
        Empty means mihomo's default (any reachable host), which is only
        suitable on a trusted network.
      '';
    };

    subscriptionUrlFile = lib.mkOption {
      type = lib.types.str;
      default = "${secretDir}/subscription.url";
      description = ''
        Runtime file (mode 0600) containing the subscription URL.
        A missing file starts mihomo with custom nodes and DIRECT only.
        Point this at config.age.secrets.<name>.path to use Agenix.
      '';
    };

    customProxiesFile = lib.mkOption {
      type = lib.types.str;
      default = "${secretDir}/custom.yaml";
      description = ''
        Runtime file (mode 0600) containing custom proxies as Clash YAML.
        They are rendered as top-level `proxies` so dialer-proxy chains between
        them resolve; include-all groups still pick them up. A missing or empty
        file renders an empty list.
      '';
    };

    customRulesFile = lib.mkOption {
      type = lib.types.str;
      default = "${secretDir}/rules.yaml";
      description = ''
        Runtime file (mode 0600) containing custom rules as a Clash YAML
        `rules:` list. The entries are prepended to the rules from the
        override document (Clash Party `+rules` semantics). A missing file adds
        no custom rules.
      '';
    };

    rulesOverrideUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://raw.githubusercontent.com/mihomo-party-org/override-hub/main/yaml/ACL4SSR_Online_Full_WithIcon.yaml";
      description = ''
        URL of the Clash override document that supplies proxy-groups,
        rule-providers and rules. The subscription provider only carries nodes.
        The document is fetched at render time and cached; when it is
        unreachable the last good copy is reused.
      '';
    };

    takeOverProxy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Point hostServices.proxyUrl at this local mihomo instance.";
    };

    metrics = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Sample the controller API and forward OTLP metrics to the local collector.";
      };
      interval = lib.mkOption {
        type = lib.types.str;
        default = "30s";
        description = "Sampling interval for mihomo-metrics.timer.";
      };
      otlpEndpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:4318/v1/metrics";
        description = "OTLP/HTTP metrics endpoint (the local OpenTelemetry Collector).";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [ mihomoPkg ];

      # The runtime inputs are credentials. The service runs with
      # ProtectHome=read-only so it cannot tighten them itself; do it once per
      # activation instead (this runs outside the service sandbox).
      home.activation.mihomoSecrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p -m 0700 '${secretDir}'
        for f in '${cfg.subscriptionUrlFile}' '${cfg.customProxiesFile}' '${cfg.customRulesFile}'; do
          if [ -e "$f" ]; then
            run chmod 0600 "$f"
          fi
        done
      '';

      systemd.user.services.mihomo = {
        Unit = {
          Description = "mihomo rule-based proxy (mixed :${toString cfg.mixedPort}, dashboard ${cfg.controllerHost}:${toString cfg.controllerPort})";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
          # A broken config makes mihomo exit immediately; without a start
          # limit that becomes an endless restart storm (hundreds of attempts).
          StartLimitIntervalSec = 180;
          StartLimitBurst = 10;
        };
        Service = {
          ExecStartPre = renderConfig;
          ExecStart = startMihomo;
          StateDirectory = "mihomo";
          StateDirectoryMode = "0700";
          Restart = "on-failure";
          RestartSec = "10s";
          TimeoutStartSec = "90s";
          UMask = "0077";
          LimitNOFILE = 1000000;

          # Hardening mirroring the non-TUN parts of the NixOS mihomo module.
          # mihomo is a Go binary (no JIT), so MemoryDenyWriteExecute is safe.
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictNamespaces = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "bpf"
          ];
          DeviceAllow = "";
          ReadWritePaths = [ stateDir ];
        };
        Install.WantedBy = [ "default.target" ];
      };
    }

    (lib.mkIf cfg.takeOverProxy {
      hostServices.proxyUrl = "http://127.0.0.1:${toString cfg.mixedPort}";
    })

    (lib.mkIf cfg.metrics.enable {
      systemd.user.services.mihomo-metrics = {
        Unit = {
          Description = "Forward mihomo traffic and memory samples to the OpenTelemetry Collector";
          After = [ "mihomo.service" ];
          Requires = [ "mihomo.service" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = collectMetrics;
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      systemd.user.timers.mihomo-metrics = {
        Unit.Description = "Sample mihomo metrics for OpenObserve";
        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = cfg.metrics.interval;
          Unit = "mihomo-metrics.service";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
  ]);
}
