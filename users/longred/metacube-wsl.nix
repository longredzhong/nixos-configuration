# Standalone Home Manager config for metacube-wsl
{ ... }:
{
  imports = [
    ./common.nix
    ../../modules/home-manager/wsl.nix
  ];
}
