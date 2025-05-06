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
        waybar
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

    programs = {
      firefox.enable = true;
      kitty.enable = true;
    };
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
      settings = {
        "$mod" = "SUPER";
        "$terminal" = "kitty";
        "$fileManager" = "dolphin";
        "$menu" = "wofi --show drun";
        general = {
          gaps_in = 5;
          gaps_out = 10;
          border_size = 2;
          "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
          "col.inactive_border" = "rgba(595959aa)";
          layout = "dwindle";
        };
        decoration = {
          rounding = 10;
          blur = {
            enabled = true;
            size = 3;
            passes = 1;
            new_optimizations = true;
          };
          drop_shadow = true;
          shadow_range = 4;
          shadow_render_power = 3;
          "col.shadow" = "rgba(1a1a1aee)";
        };
        animations = {
          enabled = true;
          bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
          animation = [
            "windows, 1, 7, myBezier"
            "windowsOut, 1, 7, default, popin 80%"
            "border, 1, 10, default"
            "fade, 1, 7, default"
            "workspaces, 1, 6, default"
          ];
        };
        dwindle = {
          pseudotile = true;
          preserve_split = true;
        };
        master = {
          new_is_master = true;
        };
        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
        };
        windowrule = [
          "float, ^(pavucontrol)$"
          "float, ^(nm-connection-editor)$"
          "float, ^(blueman-manager)$"
          "size 800 600, ^(pavucontrol)$"
          "center, ^(pavucontrol)$"
          "workspace 2, ^(google-chrome)$"
          "workspace 3, ^(code)$"
        ];
        exec-once = [
          "waybar"
          "fcitx5 -d"
          "nm-applet --indicator"
          "blueman-applet"
          "swww init && swww img ~/Pictures/wallpapers/default.jpg"
          "dunst"
        ];
        bind = [
          "$mod, F, exec, google-chrome"
          ", Print, exec, grimblast copy area"
          "$mod, Return, exec, $terminal"
          "$mod, Q, killactive,"
          "$mod, M, exit,"
          "$mod, E, exec, $fileManager"
          "$mod, V, togglefloating,"
          "$mod, R, exec, $menu"
          "$mod, P, pseudo,"
          "$mod, J, togglesplit,"
          "$mod, left, movefocus, l"
          "$mod, right, movefocus, r"
          "$mod, up, movefocus, u"
          "$mod, down, movefocus, d"
          "$mod SHIFT, left, movewindow, l"
          "$mod SHIFT, right, movewindow, r"
          "$mod SHIFT, up, movewindow, u"
          "$mod SHIFT, down, movewindow, d"
          "$mod ALT, left, resizeactive, -20 0"
          "$mod ALT, right, resizeactive, 20 0"
          "$mod ALT, up, resizeactive, 0 -20"
          "$mod ALT, down, resizeactive, 0 20"
          ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
          ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
          ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
          ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
        ] ++ (
          builtins.concatLists (builtins.genList (i:
            let ws = toString (i + 1);
            in [
              "$mod, code:1${toString i}, workspace, ${ws}"
              "$mod SHIFT, code:1${toString i}, movetoworkspace, ${ws}"
            ]) 9)
        );
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];
        input = {
          kb_layout = "us";
          follow_mouse = 1;
          sensitivity = 0;
          touchpad = {
            natural_scroll = true;
            tap-to-click = true;
            disable_while_typing = true;
          };
        };
        gestures = {
          workspace_swipe = true;
          workspace_swipe_fingers = 3;
        };
      };
    };
  };
}
