{ pkgs, config, lib, ... }:
{
  # 允许不安全的包（EOL 版本但仍需使用）
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
    "minio-2025-10-15T17-29-55Z"
  ];

  home = {
    homeDirectory = "/home/${config.home.username}";
    stateVersion = "26.05";
    sessionVariables = {
      EDITOR = lib.mkDefault "nano";
      VISUAL = lib.mkDefault "nano";
    };
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
      enableBashIntegration = false;
      nix-direnv.enable = true;
    };
  };
}
