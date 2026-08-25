# Standalone Home Manager config for NUC (Fedora 44 host)
{
  pkgs,
  ...
}:
{
  imports = [
    ./common.nix
    # Full desktop profile: shell toolchain + desktop apps/fonts/input method
    ../../modules/home-manager/profiles/desktop.nix
    # Services running as HM user-level systemd units
    ../../modules/host-services/garage.nix
    ../../modules/host-services/dufs-webdav.nix
  ];

  # Host-specific packages (parity with old NixOS hosts/nuc/home.nix)
  home.packages = with pkgs.unstable; [
    vivaldi
    navicat-premium
  ];

  # Input method environment (system-side fcitx5 installed via dnf)
  home.sessionVariables = {
    XIM = "fcitx";
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    INPUT_METHOD = "fcitx";
    SDL_IM_MODULE = "fcitx";
  };
}
