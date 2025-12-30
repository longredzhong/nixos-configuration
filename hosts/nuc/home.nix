{
  config,
  pkgs,
  lib,
  username,
  inputs,
  hostname,
  channels,
  ...
}:
let
  overlayModule = import ../../modules/overlays.nix { inherit inputs; };
  hmOverlays = overlayModule.nixpkgs.overlays;
in
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];
  home-manager.backupFileExtension = "backups";
  home-manager.sharedModules = [ inputs.plasma-manager.homeModules.plasma-manager ];
  home-manager.users.${username} = {
    imports = [
      # Use desktop profile (includes common + cli-environment + desktop)
      ../../modules/home-manager/profiles/desktop.nix
    ];
    nixpkgs.overlays = hmOverlays;

    # Host-specific packages (only packages unique to this host)
    home.packages = with pkgs.unstable; [
      sparkle
      vivaldi
      navicat-premium
    ];

    # Host-specific input method configuration
    home.sessionVariables = {
      XIM = "fcitx";
      GTK_IM_MODULE = "fcitx";
      QT_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
      INPUT_METHOD = "fcitx";
      SDL_IM_MODULE = "fcitx";
    };
  };
}
