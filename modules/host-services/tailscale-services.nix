# Tailscale Services host configuration for a Home Manager target.
#
# The huJSON file is the source of truth for service endpoints. The user-level
# unit installs it into the Tailscale config directory, applies it with
# `tailscale serve set-config`, and advertises each declared service. Service
# definitions and host approval are intentionally managed in the Tailscale
# admin console; the local client can only configure the service host.
#
# One huJSON file describes one host's services, so a second host points this
# module at its own file; the installed file keeps the source file's name.
{
  config,
  lib,
  pkgs,
  hostname,
  ...
}:
let
  cfg = config.hostServices.tailscaleServices;
  serviceConfigFile = cfg.serviceConfigFile;
  serviceConfigPath = "${config.xdg.configHome}/tailscale/${baseNameOf serviceConfigFile}";
  serviceConfig = builtins.fromJSON (builtins.readFile serviceConfigFile);
  serviceNames = lib.attrNames serviceConfig.services;
  tailscale = "/usr/bin/tailscale";

  parseEndpointPort =
    endpoint:
    let
      match = builtins.match "tcp:([0-9]+)" endpoint;
    in
    if match == null then
      throw "Tailscale Service endpoint must use tcp:<port>: ${endpoint}"
    else
      builtins.elemAt match 0;

  parseTarget =
    target:
    let
      match = builtins.match "([a-z-]+)://([^:]+):([0-9]+)" target;
    in
    if match == null then
      throw "Tailscale Service target must use <protocol>://<host>:<port>: ${target}"
    else
      {
        protocol = builtins.elemAt match 0;
        host = builtins.elemAt match 1;
        port = builtins.elemAt match 2;
      };

  # Map one Service endpoint to the raw ServeConfig handler the CLI imports.
  #
  # `tcp://` forwards raw TCP and `tls-terminated-tcp://` terminates TLS before
  # forwarding; both keep the backend protocol opaque. `http://`/`https://`
  # instead make tailscaled terminate TLS and reverse-proxy the request, which
  # is what lets it inject its identity headers for the backend to consume.
  #
  # A service definition may add an `appCaps` list. The capability names are
  # forwarded to web backends in `Tailscale-App-Capabilities`; unlike the
  # identity headers, Serve populates this for both user-owned and tagged
  # peers, so a tagged client can authenticate with a granted capability
  # instead of a login. Only `http://`/`https://` endpoints can carry it.
  rawEndpoint =
    service: definition: endpoint: target:
    let
      targetSpec = parseTarget target;
      serviceName = lib.removePrefix "svc:" service;
      tlsName = "${serviceName}.${cfg.tailnetDomain}";
      backend = "${targetSpec.host}:${targetSpec.port}";
      port = parseEndpointPort endpoint;
      appCaps = definition.appCaps or [ ];
      tcpTarget = {
        TCPForward = backend;
      };
      webTarget = targetSpec.protocol == "http" || targetSpec.protocol == "https";
      web = {
        "${tlsName}:${port}" = {
          Handlers."/" = {
            Proxy = "${targetSpec.protocol}://${backend}";
          }
          // lib.optionalAttrs (appCaps != [ ]) {
            AcceptAppCaps = appCaps;
          };
        };
      };
    in
    assert lib.assertMsg (
      appCaps == [ ] || webTarget
    ) "Tailscale Service ${service}: appCaps requires an http:// or https:// endpoint";
    {
      inherit port web webTarget;
      tcp =
        if targetSpec.protocol == "tcp" then
          tcpTarget
        else if targetSpec.protocol == "tls-terminated-tcp" then
          tcpTarget // { TerminateTLS = tlsName; }
        else if webTarget then
          { HTTPS = true; }
        else
          throw "Unsupported Tailscale Service target protocol for ${service}: ${targetSpec.protocol}";
    };

  rawService =
    service: definition:
    let
      endpoints = lib.mapAttrsToList (rawEndpoint service definition) definition.endpoints;
      tcp = builtins.listToAttrs (
        map (entry: {
          name = entry.port;
          value = entry.tcp;
        }) endpoints
      );
      web = lib.foldl' (acc: entry: acc // entry.web) { } (lib.filter (entry: entry.webTarget) endpoints);
    in
    {
      TCP = tcp;
    }
    // lib.optionalAttrs (web != { }) { Web = web; };

  # Keep generating the raw ServeConfig instead of feeding `set-config` the
  # versioned file directly. Verified against tailscale 1.102.3 -- re-check on
  # upgrade, see docs/tailscale-services.md:
  #
  # * The versioned file format has no member for app capabilities. `set-config`
  #   rejects both `appCaps` and `acceptAppCaps` with `unknown object member
  #   name ... within "/services/<svc>"`, and `get-config` emits no such member
  #   even for a service that has `AcceptAppCaps` applied. Only the imperative
  #   form can set it:
  #     tailscale serve --service=<svc> --accept-app-caps=<cap> --https=<port> <target>
  #   so moving to the versioned file would silently drop the capability that
  #   lets tagged devices authenticate.
  # * Applying this host's endpoints in the versioned format fails outright on
  #   the remote raw-TCP endpoint: `service "svc:openobserve": failed to apply
  #   TCP serve: unable to expand target: must be a URL starting with one of the
  #   supported schemes: [tcp unix]`.
  #
  # `set-config --all` still accepts the raw shape and applies it faithfully
  # (with a deprecation warning), so the checked-in huJSON stays the source of
  # truth and this conversion stays until the file format can express both.
  rawServeConfigFile = pkgs.writeText "tailscale-services-raw.json" (
    builtins.toJSON {
      Services = lib.mapAttrs rawService serviceConfig.services;
    }
  );

  applyServices = pkgs.writeShellScript "tailscale-services-apply" ''
    set -euo pipefail

    tailscale='${tailscale}'
    config='${rawServeConfigFile}'

    if [ ! -x "$tailscale" ]; then
      echo "tailscale-services: expected Tailscale CLI at $tailscale" >&2
      exit 1
    fi

    if ! "$tailscale" status --json >/dev/null 2>&1; then
      echo "tailscale-services: tailscaled is not ready" >&2
      exit 1
    fi

    # Clear each service before changing raw TCP to TLS-terminated TCP. The
    # Serve API rejects changing the handler type in place.
    ${lib.concatMapStringsSep "\n" (service: ''
      "$tailscale" serve drain '${service}' || true
      "$tailscale" serve clear '${service}' || true
    '') serviceNames}

    # The current Tailscale CLI requires --all before the positional file.
    # This is a legacy raw ServeConfig import because it is the only format
    # that preserves both TerminateTLS and TCPForward on Tailscale 1.102.x.
    "$tailscale" serve set-config --all "$config"

    # Advertise each service independently. A service that is not yet defined
    # or approved in the Tailscale admin console fails here, and because the
    # previous step applies the whole Serve config at once, aborting on the
    # first failure would not change any outcome for that service while
    # leaving later services unadvertised. Report every failure instead.
    #
    # The unit deliberately stays active in that case: Restart=on-failure
    # would otherwise re-run the drain/clear/set-config sequence every five
    # minutes, repeatedly disturbing services that are already working. The
    # warning below is the signal, and the portal reports the same condition
    # as a degraded service.
    failed=""
    ${lib.concatMapStringsSep "\n" (service: ''
      if ! "$tailscale" serve advertise '${service}'; then
        echo "tailscale-services: advertise ${service} failed; is it defined and approved in the Tailscale admin console?" >&2
        failed="$failed ${service}"
      fi
    '') serviceNames}

    if [ -n "$failed" ]; then
      echo "tailscale-services: not advertised:$failed" >&2
    fi
  '';
in
{
  options.hostServices.tailscaleServices = {
    enable = lib.mkEnableOption "this host's Tailscale Services configuration";

    serviceConfigFile = lib.mkOption {
      type = lib.types.path;
      default = ../../config/tailscale/nuc-services.hujson;
      description = ''
        huJSON file declaring this host's `svc:` endpoints and optional
        `appCaps`. It is installed under the Tailscale config directory with the
        same file name.
      '';
    };

    tailnetDomain = lib.mkOption {
      type = lib.types.str;
      default = (import ../../lib/tailnet.nix).domain;
      description = "DNS suffix of the tailnet the service names resolve in.";
    };

    description = lib.mkOption {
      type = lib.types.str;
      default = "Tailscale Services host configuration for ${hostname}";
      description = "Description of the generated systemd user unit.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file."${serviceConfigPath}".source = serviceConfigFile;

    systemd.user.services.tailscale-services = {
      Unit = {
        Description = cfg.description;
        After = [
          "network-online.target"
        ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = applyServices;
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "5min";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
