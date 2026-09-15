# Tailscale Services configuration for the Fedora NUC.
#
# The huJSON file is the source of truth for service endpoints. The user-level
# unit installs it into the Tailscale config directory, applies it with
# `tailscale serve set-config`, and advertises each declared service. Service
# definitions and host approval are intentionally managed in the Tailscale
# admin console; the local client can only configure the service host.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  serviceConfigFile = ../../config/tailscale/nuc-services.hujson;
  serviceConfigPath = "${config.xdg.configHome}/tailscale/nuc-services.hujson";
  serviceConfig = builtins.fromJSON (builtins.readFile serviceConfigFile);
  serviceNames = lib.attrNames serviceConfig.services;
  tailscale = "/usr/bin/tailscale";

  parseEndpointPort = endpoint:
    let
      match = builtins.match "tcp:([0-9]+)" endpoint;
    in
    if match == null then
      throw "Tailscale Service endpoint must use tcp:<port>: ${endpoint}"
    else
      builtins.elemAt match 0;

  parseTarget = target:
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

  rawEndpoint = service: endpoint: target:
    let
      targetSpec = parseTarget target;
      tlsName = "${lib.removePrefix "svc:" service}.tail388af.ts.net";
      targetConfig = {
        TCPForward = "${targetSpec.host}:${targetSpec.port}";
      };
    in
    {
      name = parseEndpointPort endpoint;
      value =
        if targetSpec.protocol == "tcp" then
          targetConfig
        else if targetSpec.protocol == "tls-terminated-tcp" then
          targetConfig // { TerminateTLS = tlsName; }
        else
          throw "Unsupported Tailscale Service target protocol for ${service}: ${targetSpec.protocol}";
    };

  rawService = service: definition: {
    TCP = builtins.listToAttrs (
      lib.mapAttrsToList (endpoint: target: rawEndpoint service endpoint target) definition.endpoints
    );
  };

  # Tailscale 1.102.x can represent TLS-terminated TCP in its raw Serve
  # state, but set-config cannot apply the equivalent versioned endpoint
  # directly. Generate the raw shape for the CLI while keeping the checked-in
  # huJSON file as the source of truth.
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

    ${lib.concatMapStringsSep "\n" (service: ''
      "$tailscale" serve advertise '${service}'
    '') serviceNames}
  '';
in
{
  home.file."${serviceConfigPath}".source = serviceConfigFile;

  systemd.user.services.tailscale-services = {
    Unit = {
      Description = "Tailscale Services host configuration for the NUC home lab";
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
}
