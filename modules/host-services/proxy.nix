# Shared proxy environment for host services.
#
# The default points at the remote metacube Tailscale proxy. A host that runs
# its own mihomo overrides hostServices.proxyUrl (see mihomo.nix) so user
# services use the local listener while local/Tailscale traffic stays direct.
{ config, lib, ... }:
let
  cfg = config.hostServices;
  noProxy = "localhost,127.0.0.1,::1,100.64.0.0/10,172.16.100.10";
in
{
  options.hostServices.proxyUrl = lib.mkOption {
    type = lib.types.str;
    default = "http://metacube:7890";
    description = "Upstream HTTP proxy URL consumed by user services on this host.";
  };

  options.hostServices.proxyEnvironment = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "http_proxy=${cfg.proxyUrl}"
      "https_proxy=${cfg.proxyUrl}"
      "HTTP_PROXY=${cfg.proxyUrl}"
      "HTTPS_PROXY=${cfg.proxyUrl}"
      "no_proxy=${noProxy}"
      "NO_PROXY=${noProxy}"
    ];
    description = "systemd Environment= entries routing outbound traffic through hostServices.proxyUrl";
  };
}
