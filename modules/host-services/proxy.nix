# Shared proxy environment for host services.
# Mirrors the `set_proxy metacube:7890` shell function in ~/.bashrc so that
# user-level systemd services can reach the outside network through the
# metacube Tailscale proxy while local/Tailscale traffic stays direct.
{ lib, ... }:
let
  proxyUrl = "http://metacube:7890";
  noProxy = "localhost,127.0.0.1,::1,100.64.0.0/10,172.16.100.10";
in
{
  options.hostServices.proxyEnvironment = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "http_proxy=${proxyUrl}"
      "https_proxy=${proxyUrl}"
      "HTTP_PROXY=${proxyUrl}"
      "HTTPS_PROXY=${proxyUrl}"
      "no_proxy=${noProxy}"
      "NO_PROXY=${noProxy}"
    ];
    description = "systemd Environment= entries routing outbound traffic via metacube:7890";
  };
}
