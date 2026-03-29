{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.desktop.plasma;
in
{
  options.desktop.plasma = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to manage the Plasma desktop with Home Manager.";
    };

    preset = lib.mkOption {
      type = lib.types.enum [
        "desktop"
        "laptop"
      ];
      default = "desktop";
      description = "High-level Plasma preset to apply before host-specific overrides.";
    };

    wallpaper = lib.mkOption {
      type = lib.types.either lib.types.path lib.types.str;
      default = ../../../assets/wallpapers/nixos/nixos.png;
      description = "Wallpaper used by the Plasma workspace.";
    };

    cursorSize = lib.mkOption {
      type = lib.types.int;
      default = 32;
      description = "Cursor size for the Plasma workspace.";
    };

    fontSize = lib.mkOption {
      type = lib.types.int;
      default = 12;
      description = "Default Plasma UI font size in points.";
    };

    virtualDesktopCount = lib.mkOption {
      type = lib.types.int;
      default = 9;
      description = "Number of Plasma virtual desktops.";
    };

    virtualDesktopImmutable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Prevent Plasma settings from changing the virtual desktop count.";
    };

    lockTimeout = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Lock screen timeout in minutes.";
    };

    baloo.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable Baloo file indexing.";
    };

    tray.showBattery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show the battery widget in the Plasma system tray.";
    };

    tray.showBluetooth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show the Bluetooth widget in the Plasma system tray.";
    };

    power.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Apply the shared laptop-friendly PowerDevil settings.";
    };

    overrideConfig.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enforce declarative Plasma config (reset unmanaged KDE options on activation).";
    };

    panels.top.height = lib.mkOption {
      type = lib.types.int;
      default = 32;
      description = "Top panel height in pixels.";
    };

    panels.top.opacity = lib.mkOption {
      type = lib.types.enum [
        "translucent"
        "opaque"
        "adaptive"
      ];
      default = "translucent";
      description = "Top panel opacity mode.";
    };

    panels.bottom.height = lib.mkOption {
      type = lib.types.int;
      default = 42;
      description = "Bottom dock panel height in pixels.";
    };

    panels.bottom.minLength = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Bottom dock minimum length.";
    };

    panels.bottom.maxLength = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Bottom dock maximum length.";
    };

    panels.bottom.opacity = lib.mkOption {
      type = lib.types.enum [
        "translucent"
        "opaque"
        "adaptive"
      ];
      default = "translucent";
      description = "Bottom dock opacity mode.";
    };

    panels.bottom.floating = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether bottom dock uses floating style.";
    };

    panels.bottom.alignment = lib.mkOption {
      type = lib.types.enum [
        "left"
        "center"
        "right"
      ];
      default = "center";
      description = "Bottom dock alignment on screen edge.";
    };

    dock.launchers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "applications:org.kde.dolphin.desktop"
        "applications:org.kde.konsole.desktop"
        "applications:google-chrome.desktop"
      ];
      description = "Pinned launcher entries for icon tasks in the bottom dock.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      bibata-cursors
      dracula-icon-theme
      dracula-theme
    ];

    programs.plasma = {
      enable = true;
      overrideConfig = cfg.overrideConfig.enable;

      workspace = {
        # 全局主题：决定 Plasma 的整体外观。
        # 可选方向："Dracula"、"org.kde.breezedark.desktop"，或你系统里已安装的其他 Global Theme。
        lookAndFeel = "Dracula";
        cursor = {
          # 鼠标光标主题和大小，适合按视觉风格统一调整。
          theme = "Bibata-Modern-Ice";
          size = cfg.cursorSize;
        };
        # 桌面风格 / 配色 / 图标主题。
        # theme = Plasma 桌面样式；colorScheme = 配色方案；iconTheme = 图标主题。
        theme = "Dracula";
        colorScheme = "Dracula";
        iconTheme = "Dracula";
        wallpaper = cfg.wallpaper;
      };

      hotkeys.commands."launch-konsole" = {
        name = "Launch Konsole";
        key = "Meta+Alt+K";
        command = "konsole";
      };

      fonts = {
        general = {
          # Plasma 界面字体。需要更 macOS 风格时可以换成更圆润或更紧凑的字体。
          family = "Noto Sans";
          pointSize = cfg.fontSize;
        };
      };

      panels = [
        {
          # 顶部状态栏：保留系统托盘和时间，减少视觉干扰。
          location = "top";
          opacity = cfg.panels.top.opacity;
          height = cfg.panels.top.height;
          widgets = [
            "org.kde.plasma.panelspacer"  # 左侧留白
            {
              systemTray = {
                items = {
                  shown =
                    (lib.optionals cfg.tray.showBattery [ "org.kde.plasma.battery" ])
                    ++ (lib.optionals cfg.tray.showBluetooth [ "org.kde.plasma.bluetooth" ])
                    ++ [
                      "org.kde.plasma.networkmanagement"
                      "org.kde.plasma.volume"
                    ];
                };
              };
            }
            {
              digitalClock = {
                calendar.firstDayOfWeek = "monday";
                time.format = "24h";
              };
            }
          ];
        }
        {
          location = "bottom";
          floating = cfg.panels.bottom.floating;
          alignment = cfg.panels.bottom.alignment;
          height = cfg.panels.bottom.height;
          minLength = cfg.panels.bottom.minLength;
          maxLength = cfg.panels.bottom.maxLength;
          opacity = cfg.panels.bottom.opacity;
          widgets = [
            "org.kde.plasma.panelspacer" # 左留白
            {
              name = "org.kde.plasma.kickoff";
              config = {
                General = {
                  icon = "nix-snowflake-white";
                  alphaSort = true;
                };
              };
            }
            {
              iconTasks = {
                launchers = cfg.dock.launchers;
                behavior.showTasks = {
                  onlyInCurrentActivity = false;
                  onlyInCurrentDesktop = false;
                };
              };
            }
            "org.kde.plasma.panelspacer" # 右留白

          ];
        }
      ];

      window-rules = [
        {
          description = "Dolphin";
          match = {
            window-class = {
              value = "dolphin";
              type = "substring";
            };
            window-types = [ "normal" ];
          };
          apply = {
            noborder = {
              value = false;
              apply = "force";
            };
            maximizehoriz = true;
            maximizevert = true;
          };
        }
      ];

      powerdevil = lib.mkIf cfg.power.enable {
        AC = {
          powerButtonAction = "lockScreen";
          autoSuspend = {
            action = "nothing";
            idleTimeout = null;
          };
          turnOffDisplay = {
            idleTimeout = 1000;
            idleTimeoutWhenLocked = "immediately";
          };
        };
        battery = {
          powerButtonAction = "sleep";
          whenSleepingEnter = "standbyThenHibernate";
        };
        lowBattery = {
          whenLaptopLidClosed = "hibernate";
        };
        # 24 小时制时间显示。
      };

      kscreenlocker = {
        lockOnResume = true;
        timeout = cfg.lockTimeout;
      };

      shortcuts = import ./shortcuts.nix;

      configFile = {
        baloofilerc."Basic Settings"."Indexing-Enabled" = cfg.baloo.enable;
        kwinrc."org.kde.kdecoration2".ButtonsOnLeft = "SF";
        kwinrc.Desktops.Number = {
          value = cfg.virtualDesktopCount;
          immutable = cfg.virtualDesktopImmutable;
        };
        kscreenlockerrc = {
          Greeter.WallpaperPlugin = "org.kde.potd";
          "Greeter/Wallpaper/org.kde.potd/General".Provider = "bing";
        };
      };
    };
  };
}
