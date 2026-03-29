# Desktop packages - common GUI applications for desktop environments
{ pkgs, lib, config, ... }:
let
  cfg = config.desktop.packages;

  stablePackages = with pkgs; [
    # 字体
    noto-fonts-cjk-sans
    nerd-fonts.fira-code
    fontconfig
  ];

  optionalPackages =
    (lib.optionals cfg.optional.bitwarden.enable [ pkgs.unstable.bitwarden-desktop ])
    ++ (lib.optionals cfg.optional.obsidian.enable [ pkgs.unstable.obsidian ])
    ++ (lib.optionals cfg.optional.cherryStudio.enable [ pkgs.unstable.cherry-studio ]);
in
{
  options.desktop.packages = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install the shared desktop package set.";
    };

    optional.bitwarden.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Bitwarden Desktop as part of the optional desktop package set.";
    };

    optional.obsidian.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Obsidian as part of the optional desktop package set.";
    };

    optional.cherryStudio.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install Cherry Studio as an opt-in package because it currently pulls an insecure Electron runtime.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = stablePackages ++ optionalPackages;
  };
}
