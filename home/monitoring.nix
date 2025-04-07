{ pkgs, ... }: {
  home.packages = with pkgs; [
    # 系统监控
    btop # 终端系统监控
    glances # 系统监控
    dstat # 资源统计
    iotop # 磁盘IO监控
    bottom # 终端系统监控

    # 网络监控
    bandwhich # 终端带宽使用监控
    iftop # 网络带宽监控
    mtr # 网络诊断

    # 日志工具
    lnav # 日志文件导航器
  ];

  # 为监控工具创建默认配置
  home.file.".config/btop/btop.conf".text = ''
    color_theme = "TTY"
    theme_background = false
    update_ms = 1000
    vim_keys = true
  '';
}
