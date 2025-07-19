{ config, pkgs, lib, username, inputs, hostname, channels, ... }:

let
  # 导入 overlays 模块并获取 overlay 列表
  overlayModule = import ../../modules/overlays.nix { inherit inputs; };
  hmOverlays = overlayModule.nixpkgs.overlays;
in {
  imports = [ inputs.home-manager.nixosModules.home-manager ];
  home-manager.backupFileExtension = "backup";
  home-manager.sharedModules =
    [ inputs.plasma-manager.homeManagerModules.plasma-manager ];
  home-manager.users.${username} = {
    imports = [
      ../../modules/home-manager/common.nix
      ../../modules/home-manager/desktop/default.nix
      ../../modules/home-manager/cli-environment.nix
    ];
    nixpkgs.overlays = hmOverlays;
    nixpkgs.config.permittedInsecurePackages = [ "mihomo-party-1.7.3" ];
    home.packages = let
      stable-packages = with pkgs; [
        # 稳定版本的软件包 (仅保留此主机特有的)
        noto-fonts-cjk-sans
        nerd-fonts.fira-code
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

    programs = { kitty.enable = true; };
  };
}
