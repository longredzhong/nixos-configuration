{ config, pkgs, lib, username, inputs, hostname, channels, ... }:

let
  # 导入 overlays 模块并获取 overlay 列表
  overlayModule = import ../../modules/overlays.nix { inherit inputs; };
  hmOverlays = overlayModule.nixpkgs.overlays;
in {
  home-manager.backupFileExtension = "backup";
  home-manager.users.${username} = {
    imports = [
      ../../modules/home-manager/common.nix
      ../../modules/home-manager/cli-environment.nix
    ];
    nixpkgs.overlays = hmOverlays;

    home.packages = let
      stable-packages = with pkgs; [
        # 稳定版本的软件包 (仅保留此主机特有的)
        noto-fonts-cjk-sans
        fira-code-nerdfont
        fontconfig

      ];

      unstable-packages = with pkgs.unstable; [
        # 不稳定版本的软件包 (仅保留此主机特有的)
        mihomo-party
        vscode
        google-chrome
        bitwarden-desktop
        cherry-studio
        obsidian
        navicat-premium
      ];
    in stable-packages ++ unstable-packages;

    programs = {
      firefox.enable = true;
      kitty.enable = true;
    };
    i18n.inputMethod = {
      enabled = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-gtk
        fcitx5-chinese-addons
        fcitx5-nord
        fcitx5-rime
        rime-data
      ];
    };
  };
}
