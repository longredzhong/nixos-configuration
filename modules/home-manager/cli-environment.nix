{ pkgs, ... }: {
  imports = [
    ./shell/fish.nix
    ./shell/starship.nix
    ./shell/atuin.nix
    ./shell/git.nix
    ./shell/tmux.nix
  ];
  home.packages = let
    stablePackages = with pkgs; [
      # --- 文件管理 & 导航 ---
      broot # 树状文件浏览器
      ranger # 终端文件管理器
      eza # 更好的 ls
      ncdu # 磁盘使用分析
      duf # 更好的 df

      # --- 搜索 & 过滤 ---
      fd # 更好的 find
      ripgrep # 更好的 grep
      silver-searcher # ag 搜索工具
      fzf # 模糊搜索
      jq # JSON 处理
      yq # YAML/XML 处理

      # --- 查看 & 编辑 ---
      bat # 更好的 cat，带语法高亮
      delta # git 美化差异查看
      difftastic # 结构化差异比较
      tldr # 简化版 man 页面

      # --- 开发工具 ---
      lazygit # git TUI 界面
      wezterm # 终端模拟器
      ffmpeg # 多媒体处理

      # --- 系统监控 ---
      fastfetch # 系统信息
      btop # 终端系统监控
      glances # 系统监控
      dstat # 资源统计
      iotop # 磁盘IO监控
      nvitop # NVIDIA GPU 监控

      # --- 网络工具 ---
      httpie # 友好的 HTTP 客户端
      dogdns # 更好的 dig
      bandwhich # 终端带宽使用监控
      iftop # 网络带宽监控
      mtr # 网络诊断

      # --- 日志工具 ---
      lnav # 日志文件导航器
    ];
    unstablePackages = with pkgs.unstable;
      [
        # 添加不稳定的包（如果需要）
      ];
  in stablePackages ++ unstablePackages;

  # 配置 bat (更好的 cat)
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

  # 配置 btop (更好的 top/htop)
  home.file.".config/btop/btop.conf".text = ''
    color_theme = "TTY"
    theme_background = false
    update_ms = 1000
    vim_keys = true
  '';
}
