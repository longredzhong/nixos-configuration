# Minimal profile - CLI-only environment for servers or lightweight setups
# Use for: headless servers, containers, minimal installations
{ inputs, ... }:
{
  imports = [
    ../common.nix
    ../cli-environment.nix
  ];
}
