{ config, lib, pkgs, secrets, ... }:

{
  environment.systemPackages = [ pkgs.cloudflared ];
  users.users.cloudflared = {
    group = "cloudflared";
    isSystemUser = true;
  };
  users.groups.cloudflared = { };
  systemd.services.cloudflared_tunnel = {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-resolved.service" "network-online.target" "tailscaled.service" "docker.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token=${secrets.cloudflare_tunnelToken}";
      Restart = "always";
      User = "cloudflared";
      Group = "cloudflared";
    };
  };

}
