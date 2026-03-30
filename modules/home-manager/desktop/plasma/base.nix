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

    virtualKeyboard.desktopFile = lib.mkOption {
      type = lib.types.str;
      default = "/usr/share/applications/fcitx5-wayland-launcher.desktop";
      description = "Desktop file used by Plasma Wayland as the virtual keyboard / input method entrypoint.";
    };

    krunner.position = lib.mkOption {
      type = lib.types.enum [
        "top"
        "center"
      ];
      default = "center";
      description = "KRunner position on screen.";
    };

    krunner.activateWhenTypingOnDesktop = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether typing on desktop should trigger KRunner.";
    };

    krunner.historyBehavior = lib.mkOption {
      type = lib.types.enum [
        "disabled"
        "enableSuggestions"
        "enableAutoComplete"
      ];
      default = "enableSuggestions";
      description = "How KRunner history behaves.";
    };

    krunner.shortcuts.launch = lib.mkOption {
      type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
      default = "Alt+Space";
      description = "Shortcut to launch KRunner.";
    };

    krunner.shortcuts.runCommandOnClipboard = lib.mkOption {
      type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
      default = "Alt+Shift+F2";
      description = "Shortcut to run command on clipboard contents via KRunner.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      (with pkgs; [
        bibata-cursors
        dracula-icon-theme
        dracula-theme
        fcitx5
        qt6Packages.fcitx5-configtool
      ])
      ++ (lib.optionals (builtins.hasAttr "fcitx5-rime" pkgs.qt6Packages) [ pkgs.qt6Packages."fcitx5-rime" ])
      ++ (lib.optionals (builtins.hasAttr "fcitx5-chinese-addons" pkgs.qt6Packages) [ pkgs.qt6Packages."fcitx5-chinese-addons" ])
      ++ (lib.optionals (builtins.hasAttr "fcitx5-gtk" pkgs) [ pkgs."fcitx5-gtk" ])
      ++ (lib.optionals (builtins.hasAttr "fcitx5-qt" pkgs.qt6Packages) [ pkgs.qt6Packages."fcitx5-qt" ]);

    home.sessionVariables = {
      INPUT_METHOD = "fcitx";
      GTK_IM_MODULE = "fcitx";
      QT_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
      SDL_IM_MODULE = "fcitx";
      GLFW_IM_MODULE = "fcitx";
    };

    programs.plasma = {
      enable = true;
      overrideConfig = cfg.overrideConfig.enable;
      krunner = {
        position = cfg.krunner.position;
        activateWhenTypingOnDesktop = cfg.krunner.activateWhenTypingOnDesktop;
        historyBehavior = cfg.krunner.historyBehavior;
        shortcuts = {
          launch = cfg.krunner.shortcuts.launch;
          runCommandOnClipboard = cfg.krunner.shortcuts.runCommandOnClipboard;
        };
      };

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
            # 虚拟桌面 Pager：直观切换 N 个桌面，避免只能靠快捷键盲切。
            "org.kde.plasma.pager"
            # 窗口设置切换器 Task Manager：显示当前活动窗口，支持窗口预览和快速切换。
            {
              name = "org.kde.plasma.taskmanager";
              config = {
                General = {
                  showOnlyCurrentActivity = false;
                  showOnlyCurrentDesktop = false;
                  grouping = "byProgramName"; # 相同程序的窗口合并为一个图标，状态栏更整洁。
                  sortingMethod = "byTime"; # 任务图标按最近使用排序，常用窗口更快访问。
                };
              };
            }
            "org.kde.plasma.panelspacer"  # 将托盘和时钟推向右侧
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
                # date.enable = false 可以完全去掉日期，节省顶栏宽度。
                # 若需保留日期建议去掉年份：使用 date.format = "custom" 配合 customDateFormat = "M/d"。
                date.enable = false;
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
            # kickoff 与任务栏之间的视觉分隔线，避免启动器图标和运行任务混淆。
            "org.kde.plasma.marginsseparator"
            {
              iconTasks = {
                launchers = cfg.dock.launchers;
                behavior = {
                  showTasks = {
                    onlyInCurrentActivity = false;
                    onlyInCurrentDesktop = true;
                  };
                  # byProgramName：相同程序的窗口合并为一个图标，dock 更整洁。
                  # doNotGroup = 不合并；byProgramName = 按程序名合并。
                  grouping.method = "byProgramName";
                  # manually = 按 pin 顺序排序，不自动重排。
                  sortingMethod = "manually";
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
        kwinrc.Wayland."InputMethod[$e]" = cfg.virtualKeyboard.desktopFile;
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
