{ lib, config, ... }:
let
  cfg = config.desktop.plasma;
in
{
  config = lib.mkIf (cfg.enable && cfg.preset == "desktop") {
    desktop.plasma = {
      tray.showBattery = lib.mkDefault false;
      tray.showBluetooth = lib.mkDefault false;
      power.enable = lib.mkDefault false;
      virtualDesktopCount = lib.mkDefault 9;
      virtualDesktopImmutable = lib.mkDefault true;
      lockTimeout = lib.mkDefault 10;
    };
  };
}