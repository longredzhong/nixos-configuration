{ config, pkgs, ... }: {
  # 命令行工具
  home.packages = let
    stablePackages = with pkgs; [
      # 文件管理
      broot # 树状文件浏览器
      ranger # 终端文件管理器

      # 搜索工具
      fd # 更好的 find
      ripgrep # 更好的 grep
      silver-searcher # ag 搜索工具

      # 功能增强
      bat # 更好的 cat，带语法高亮
      eza # 更好的 ls
      duf # 更好的 df
      bottom # 更好的 top/htop
      ncdu # 磁盘使用分析
      tldr # 简化版 man 页面
      jq # JSON 处理
      yq # YAML/XML 处理
      fzf # 模糊搜索

      # 网络工具
      httpie # 友好的 HTTP 客户端
      dogdns # 更好的 dig

      # 开发工具
      delta # git 美化差异查看
      lazygit # git TUI 界面
      difftastic # 结构化差异比较
      wezterm # 终端模拟器
      ffmpeg
    ];
    unstablePackages = with pkgs.unstable; [
    ];
  in stablePackages ++ unstablePackages;

  # 配置 bat
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
      style = "plain";
    };
  };

  # 配置 zoxide (cd 增强)
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    options = [ "--cmd cd" ];
  };
}
