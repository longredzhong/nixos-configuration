{ pkgs, ... }: {

  home.packages = with pkgs; [
    noto-fonts-cjk-sans
    fira-code-nerdfont
    fontconfig

    pkgs.unstable.mihomo-party
    pkgs.unstable.vscode
    pkgs.unstable.google-chrome
    pkgs.unstable.bitwarden-desktop
    pkgs.unstable.cherry-studio
    pkgs.unstable.obsidian

  ];
  fonts.fontconfig.enable = true;

  programs = { firefox.enable = true; };
  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      fcitx5-chinese-addons
      fcitx5-nord
      fcitx5-rime
      rime-data
    ];
  };

}
