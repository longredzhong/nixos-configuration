# Shared proxy environment for host services.
#
# The default points at the remote metacube Tailscale proxy. A host that runs
# its own mihomo overrides hostServices.proxyUrl (see mihomo.nix) so user
# services use the local listener while local/Tailscale traffic stays direct.
{ config, lib, ... }:
let
  cfg = config.hostServices;

  # The tailnet is excluded by name as well as by address range: NO_PROXY is
  # matched against the host string in the URL, so the CGNAT range alone lets a
  # short name such as `longred-vm` (the binary cache substituter) through to
  # the proxy, which cannot reach it and answers 502. The names come from
  # lib/tailnet.nix so this list cannot drift from the shell and NixOS ones.
  tailnet = import ../../lib/tailnet.nix;
  noProxy = builtins.concatStringsSep "," (
    [
      "localhost"
      "127.0.0.1"
      "::1"
      "100.64.0.0/10"
      "172.16.100.10"
    ]
    ++ tailnet.names
  );
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
