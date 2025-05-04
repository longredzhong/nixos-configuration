{ config, pkgs, lib, username, inputs, hostname, channels, ... }:

let
  # 导入 overlays 模块并获取 overlay 列表
  overlayModule = import ../../modules/overlays.nix { inherit inputs; };
  hmOverlays = overlayModule.nixpkgs.overlays;
in {
  home-manager.users.${username} = {
    imports = [
      ../../modules/home-manager/common.nix
      ../../modules/home-manager/wsl.nix
      ../../modules/home-manager/cli-environment.nix
    ];
    nixpkgs.overlays = hmOverlays;

    home.packages = let
      stable-packages = with pkgs; [
        # 稳定版本的软件包 (仅保留此主机特有的)
        git
        neovim
      ];

      unstable-packages = with pkgs.unstable;
        [
          # 不稳定版本的软件包 (仅保留此主机特有的)
        ];
    in stable-packages ++ unstable-packages;

  };
}
