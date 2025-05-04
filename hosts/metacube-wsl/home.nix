{ config, pkgs, lib, username, inputs, hostname, channels, ... }: # <--- 添加 username 和其他需要的参数

{
  home-manager.users.${username} = {
    imports = [
      ../../modules/home-manager/common.nix
      ../../modules/home-manager/wsl.nix
    ];
    home.packages = let
      stable-packages = with pkgs; [
        # 稳定版本的软件包
        git
        bottom
        btop
        neovim
        ripgrep
        fd
        bat
      ];
      unstable-packages = with pkgs.unstable; [
        fish
        micromamba
        pixi
        just
      ];
    in stable-packages ++ unstable-packages;

  };
}
