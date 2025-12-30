{ pkgs, config, lib, ... }:
{
  home = {
    homeDirectory = "/home/${config.home.username}";
    stateVersion = "25.11";
  };

  # 启用 XDG 目录规范
  xdg.enable = lib.mkDefault true;

  # 通用程序配置
  programs = {
    # 启用 home-manager 自身管理
    home-manager.enable = true;

    # direnv - 目录级环境变量
    direnv = {
      enable = lib.mkDefault true;
      nix-direnv.enable = true;
    };
  };
}
