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
      ../../modules/home-manager/common.nix
      ../../modules/home-manager/desktop/default.nix
      ../../modules/home-manager/cli-environment.nix
    ];
    nixpkgs.overlays = hmOverlays;
    home.packages =
      let
        stable-packages = with pkgs; [
          # 稳定版本的软件包 (仅保留此主机特有的)
          noto-fonts-cjk-sans
          nerd-fonts.fira-code
          fontconfig
        ];

        unstable-packages = with pkgs.unstable; [
          # 不稳定版本的软件包 (仅保留此主机特有的)
          sparkle
          vscode
          vivaldi
          google-chrome
          bitwarden-desktop
          cherry-studio
          obsidian
          navicat-premium
        ];
      in
      stable-packages ++ unstable-packages;

    programs = {
      kitty.enable = true;
    };
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
