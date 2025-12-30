# WSL profile - Windows Subsystem for Linux environment
# Use for: thinkbook-wsl, metacube-wsl
{ inputs, ... }:
{
  imports = [
    ../common.nix
    ../cli-environment.nix
    ../wsl.nix
  ];
}
