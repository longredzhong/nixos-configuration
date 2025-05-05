{ config, pkgs, lib, username, inputs, hostname, channels, ... }:

let
  # 导入 overlays 模块并获取 overlay 列表
  overlayModule = import ../../modules/overlays.nix { inherit inputs; };
  hmOverlays = overlayModule.nixpkgs.overlays;
in {
  nixpkgs.config.permittedInsecurePackages = [ "mihomo-party-1.7.2" ];
  home-manager.backupFileExtension = "backup";
  home-manager.users.${username} = {
    imports = [
      ../../modules/home-manager/common.nix
      ../../modules/home-manager/cli-environment.nix
    ];
    nixpkgs.overlays = hmOverlays;

    home.packages = let
      stable-packages = with pkgs; [
        # 稳定版本的软件包 (仅保留此主机特有的)
        noto-fonts-cjk-sans
        fira-code-nerdfont
        fontconfig
      ];

      unstable-packages = with pkgs.unstable; [
        # 不稳定版本的软件包 (仅保留此主机特有的)
        mihomo-party
        vscode
        google-chrome
        bitwarden-desktop
        cherry-studio
        obsidian
        navicat-premium
      ];
    in stable-packages ++ unstable-packages;

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
    wayland.windowManager.hyprland = {
      # Whether to enable Hyprland wayland compositor
      enable = true;
      # The hyprland package to use
      package = pkgs.hyprland;
      # Whether to enable XWayland
      xwayland.enable = true;

      # Optional
      # Whether to enable hyprland-session.target on hyprland startup
      systemd.enable = true;
      # Add this extraConfig section
      extraConfig = ''
        # Monitor configuration
        monitor=eDP-1,preferred,auto,1

        # Input configuration
        input {
            kb_layout = us
            follow_mouse = 1
            touchpad {
                natural_scroll = yes
            }
            sensitivity = 0.0 # -1.0 - 1.0, 0 means no modification.
        }

        # FCitx5 environment variables
        env = XCURSOR_SIZE,24
        env = QT_IM_MODULE,fcitx
        env = XMODIFIERS,@im=fcitx
        env = SDL_IM_MODULE,fcitx
        env = GTK_IM_MODULE,fcitx
        env = GLFW_IM_MODULE,ibus

        # Your Hyprland config continues...
        # ... add more configuration here

        # Start fcitx5 with Hyprland
        exec-once = fcitx5 -d
      '';
    };
  };
}
