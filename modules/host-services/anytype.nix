# anytype-cli headless server as an HM user-level systemd service (Fedora NUC)
# API is exposed on 0.0.0.0:31012 (gRPC 31010/31011 stay on localhost) so both
# localhost and Tailscale hosts can reach it.
# Outbound traffic (any-sync network, updates) goes through the metacube proxy.
{ config, pkgs, ... }:
{
  imports = [ ./proxy.nix ];

  systemd.user.services.anytype = {
    Unit = {
      Description = "Anytype headless server (API port 31012)";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.anytype-cli}/bin/anytype serve --listen-address 0.0.0.0:31012 --no-update-check";
      Environment = config.hostServices.proxyEnvironment;
      Restart = "always";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
