# Desktop packages - common GUI applications for desktop environments
{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    # 字体
    noto-fonts-cjk-sans
    nerd-fonts.fira-code
    fontconfig

    # 开发工具 (from unstable via overlay)
    unstable.vscode

    # 浏览器
    unstable.google-chrome

    # 生产力工具
    unstable.bitwarden-desktop
    unstable.obsidian

    # AI 工具
    unstable.cherry-studio
  ];

  # 终端模拟器
  programs.kitty.enable = lib.mkDefault true;
}
