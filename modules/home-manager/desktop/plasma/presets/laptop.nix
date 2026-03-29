{ lib, config, ... }:
let
  cfg = config.desktop.plasma;
in
{
  config = lib.mkIf (cfg.enable && cfg.preset == "laptop") {
    desktop.plasma = {
      overrideConfig.enable = lib.mkDefault true;

      tray.showBattery = lib.mkDefault true;
      tray.showBluetooth = lib.mkDefault true;

      panels.top.height = lib.mkDefault 30;
      panels.top.opacity = lib.mkDefault "translucent";

      panels.bottom.height = lib.mkDefault 38;
      panels.bottom.minLength = lib.mkDefault 340;
      panels.bottom.maxLength = lib.mkDefault 820;
      panels.bottom.opacity = lib.mkDefault "translucent";
      panels.bottom.floating = lib.mkDefault true;
      panels.bottom.alignment = lib.mkDefault "center";

      power.enable = lib.mkDefault true;
      virtualDesktopCount = lib.mkDefault 6;
      virtualDesktopImmutable = lib.mkDefault false;
      lockTimeout = lib.mkDefault 5;
    };
  };
}