{ pkgs, lib, config, ... }:
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
      type = lib.types.enum [ "desktop" "laptop" ];
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
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      bibata-cursors
      whitesur-icon-theme
    ];

    programs.plasma = {
      enable = true;

      workspace = {
        lookAndFeel = "org.kde.breezedark.desktop";
        cursor = {
          theme = "Bibata-Modern-Ice";
          size = cfg.cursorSize;
        };
        iconTheme = "WhiteSur";
        wallpaper = cfg.wallpaper;
      };

      hotkeys.commands."launch-konsole" = {
        name = "Launch Konsole";
        key = "Meta+Alt+K";
        command = "konsole";
      };

      fonts = {
        general = {
          family = "Noto Sans";
          pointSize = cfg.fontSize;
        };
      };

      panels = [
        {
          location = "top";
          widgets = [
            {
              name = "org.kde.plasma.kickoff";
              config = {
                General = {
                  icon = "nix-snowflake-white";
                  alphaSort = true;
                };
              };
            }
            "org.kde.plasma.marginsseparator"
            {
              iconTasks = {
                launchers = [
                  "applications:org.kde.dolphin.desktop"
                  "applications:org.kde.konsole.desktop"
                ];
                behavior.showTasks = {
                  onlyInCurrentActivity = false;
                  onlyInCurrentDesktop = false;
                };
              };
            }
            "org.kde.plasma.panelspacer"
            {
              plasmusicToolbar = {
                panelIcon = {
                  albumCover = {
                    useAsIcon = false;
                    radius = 8;
                  };
                  icon = "view-media-track";
                };
                playbackSource = "auto";
                musicControls.showPlaybackControls = true;
                songText = {
                  displayInSeparateLines = true;
                  maximumWidth = 480;
                  scrolling = {
                    behavior = "alwaysScroll";
                    speed = 3;
                  };
                };
              };
            }
            "org.kde.plasma.panelspacer"
            {
              systemTray.items.shown =
                (lib.optionals cfg.tray.showBattery [ "org.kde.plasma.battery" ])
                ++ (lib.optionals cfg.tray.showBluetooth [ "org.kde.plasma.bluetooth" ])
                ++ [
                  "org.kde.plasma.networkmanagement"
                  "org.kde.plasma.volume"
                ];
            }
            {
              digitalClock = {
                calendar.firstDayOfWeek = "monday";
                time.format = "24h";
              };
            }
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
      };

      kscreenlocker = {
        lockOnResume = true;
        timeout = cfg.lockTimeout;
      };

      shortcuts = {
        ksmserver = {
          "Lock Session" = [
            "Screensaver"
            "Meta+Ctrl+Alt+L"
          ];
        };

        kwin = {
          "Expose" = "Meta+,";
          "Switch Window Down" = "Meta+J";
          "Switch Window Left" = "Meta+H";
          "Switch Window Right" = "Meta+L";
          "Switch Window Up" = "Meta+K";
          "Switch to Desktop 1" = "Meta+1";
          "Switch to Desktop 2" = "Meta+2";
          "Switch to Desktop 3" = "Meta+3";
          "Switch to Desktop 4" = "Meta+4";
          "Switch to Desktop 5" = "Meta+5";
          "Switch to Desktop 6" = "Meta+6";
          "Switch to Desktop 7" = "Meta+7";
          "Switch to Desktop 8" = "Meta+8";
          "Switch to Desktop 9" = "Meta+9";
          "Switch Window to Desktop 1" = "Meta+Shift+1";
          "Switch Window to Desktop 2" = "Meta+Shift+2";
          "Switch Window to Desktop 3" = "Meta+Shift+3";
          "Switch Window to Desktop 4" = "Meta+Shift+4";
          "Switch Window to Desktop 5" = "Meta+Shift+5";
          "Switch Window to Desktop 6" = "Meta+Shift+6";
          "Switch Window to Desktop 7" = "Meta+Shift+7";
          "Switch Window to Desktop 8" = "Meta+Shift+8";
          "Switch Window to Desktop 9" = "Meta+Shift+9";
          "Toggle Overview" = "Meta+Tab";
          "Quit" = "Meta+W";
        };
      };

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