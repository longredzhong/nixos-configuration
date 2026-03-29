{ lib, config, ... }:
let
  cfg = config.desktop.plasma;
in
{
  config = lib.mkIf (cfg.enable && cfg.preset == "laptop") {
    desktop.plasma = {
      tray.showBattery = lib.mkDefault true;
      tray.showBluetooth = lib.mkDefault true;
      power.enable = lib.mkDefault true;
      virtualDesktopCount = lib.mkDefault 6;
      virtualDesktopImmutable = lib.mkDefault false;
      lockTimeout = lib.mkDefault 5;
    };
  };
}