{ pkgs, ... }: {

  home.packages = with pkgs; [
    noto-fonts-cjk-sans
    fira-code-nerdfont
    fontconfig

    mihomo-party
    pkgs.unstable.vscode
    pkgs.unstable.google-chrome
    pkgs.unstable.bitwarden-desktop
    pkgs.unstable.cherry-studio
    pkgs.unstable.obsidian

    fcitx5-gtk
    fcitx5-chinese-addons
    fcitx5-nord
    fcitx5-rime
    rime-data
  ];
  fonts.fontconfig.enable = true;

  programs = {

    firefox.enable = true;

    home-manager.enable = true;
  };

}
