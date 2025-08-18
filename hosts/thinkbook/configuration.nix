{ username, hostname, pkgs, lib, inputs, config, options, nixpkgs, ... }: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/system/common.nix
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-index-database.nixosModules.nix-index
    inputs.agenix.nixosModules.default
    # Import the new agenix config module, not the secrets data file
    # ../../secrets/agenix-config.nix
    ../../modules/system/desktop/kde.nix
    ../../modules/system/apps/flatpak.nix
    ../../modules/system/audio/pipewire.nix
    ../../modules/system/hardware/intel.nix
    ../../modules/system/desktop/wayland.nix
  ];

  # Bootloader.
  # 推荐仅启用 grub，自动检测 Windows 启动项
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    useOSProber = true; # 允许自动检测 Windows
    device = "nodev";
  };
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "${hostname}"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Shanghai";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "zh_CN.UTF-8";
    LC_IDENTIFICATION = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_MONETARY = "zh_CN.UTF-8";
    LC_NAME = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_TELEPHONE = "zh_CN.UTF-8";
    LC_TIME = "zh_CN.UTF-8";
  };

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = false;
      plasma6Support = true;
      addons = with pkgs; [
        rime-data
        fcitx5-rime
        fcitx5-gtk
        fcitx5-chinese-addons

        # ColorScheme
        fcitx5-nord
        fcitx5-rose-pine
      ];
    };
  };
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  environment.sessionVariables = { };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
    daemon.settings = { "features" = { "buildkit" = true; }; };
    storageDriver = "btrfs";
  };

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "${username}";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = let
    stable-packages = with pkgs; [ vlc ];
    unstable-packages = with pkgs.unstable; [ ];
  in stable-packages ++ unstable-packages;

  services.openssh.enable = true;
  networking.firewall.enable = false;
}
