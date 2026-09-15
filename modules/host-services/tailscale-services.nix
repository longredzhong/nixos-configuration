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

  applyServices = pkgs.writeShellScript "tailscale-services-apply" ''
    set -euo pipefail

    tailscale='${tailscale}'
    config='${serviceConfigPath}'

    if [ ! -x "$tailscale" ]; then
      echo "tailscale-services: expected Tailscale CLI at $tailscale" >&2
      exit 1
    fi

    if ! "$tailscale" status --json >/dev/null 2>&1; then
      echo "tailscale-services: tailscaled is not ready" >&2
      exit 1
    fi

    # The current Tailscale CLI requires --all before the positional file.
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
