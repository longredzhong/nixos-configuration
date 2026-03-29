# Standalone Home Manager config for Fedora ThinkBook
{ ... }:
{
  imports = [
    ./common.nix
    ../../modules/home-manager/desktop/default.nix
  ];

  desktop.plasma = {
    preset = "laptop";
    virtualDesktopCount = 6;
    virtualDesktopImmutable = false;
    lockTimeout = 5;
  };
}
