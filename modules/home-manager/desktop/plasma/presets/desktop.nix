{ lib, config, ... }:
let
  cfg = config.desktop.plasma;
in
{
  config = lib.mkIf (cfg.enable && cfg.preset == "desktop") {
    desktop.plasma = {
      overrideConfig.enable = lib.mkDefault true;

      tray.showBattery = lib.mkDefault true;
      tray.showBluetooth = lib.mkDefault true;

      panels.top.height = lib.mkDefault 32;
      panels.top.opacity = lib.mkDefault "translucent";

      panels.bottom.height = lib.mkDefault 42;
      panels.bottom.minLength = lib.mkDefault 600;
      panels.bottom.maxLength = lib.mkDefault 1100;
      panels.bottom.opacity = lib.mkDefault "translucent";
      panels.bottom.floating = lib.mkDefault true;
      panels.bottom.alignment = lib.mkDefault "center";

      power.enable = lib.mkDefault true;
      virtualDesktopCount = lib.mkDefault 9;
      virtualDesktopImmutable = lib.mkDefault true;
      lockTimeout = lib.mkDefault 10;
    };
  };
}