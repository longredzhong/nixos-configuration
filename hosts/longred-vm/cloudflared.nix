# Cloudflare Tunnel for longred-vm services.
#
# The tunnel is credential-managed: cloudflared receives only the tunnel token,
# and Cloudflare pushes the public hostnames from the dashboard. There is
# deliberately NO local ingress list here. In this mode a local one would look
# authoritative while being ignored, which is exactly what happened to
# modules/host-services/cloudflared.nix: its ingress never took effect, and the
# live configuration came from the dashboard instead.
#
# nixpkgs' services.cloudflared is not used because it only models
# credentials-file tunnels built around a locally declared ingress map; it has
# no token option.
#
# The tunnel is outbound-only, so this adds no inbound firewall rule. It fronts
# the ntfy listener on loopback; that service keeps its tailnet HTTPS name as a
# second path, so a Cloudflare outage does not remove local access.
{
  config,
  pkgs,
  ...
}:
{
  age.secrets.cloudflare-tunnel-longred-vm = {
    file = ../../secrets/cloudflare-tunnel-longred-vm.age;
    owner = "cloudflared";
    mode = "0400";
  };

  # cloudflared holds a credential that can publish internal services, so it
  # runs as its own unprivileged account rather than as root.
  users.groups.cloudflared = { };
  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
  };

  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel for longred-vm";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    # No agenix dependency: on NixOS agenix decrypts during activation, before
    # multi-user.target, and exports no `agenix.service` at all. The Home
    # Manager side does have such a unit, so a dependency copied from there
    # makes this service unstartable ("Unit agenix.service not found").
    after = [
      "network-online.target"
      "ntfy-sh.service"
    ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file ${config.age.secrets.cloudflare-tunnel-longred-vm.path}";
      User = "cloudflared";
      Group = "cloudflared";

      Restart = "always";
      RestartSec = "5s";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
    };
  };
}
