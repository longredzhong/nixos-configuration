# Standalone Home Manager config for Fedora ThinkBook
{ ... }:
{
  imports = [
    ./common.nix
    ../../modules/home-manager/desktop/default.nix
    ../../modules/host-services/openobserve-agent.nix
  ];
}
