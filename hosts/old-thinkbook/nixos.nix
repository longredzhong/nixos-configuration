{ username, hostname, pkgs, lib, inputs, config, options, nixpkgs, ... }: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-index-database.nixosModules.nix-index
    inputs.agenix.nixosModules.default
    # Import the new agenix config module, not the secrets data file
    # ../../secrets/agenix-config.nix
    ../../modules/kde.nix
    ../../modules/flatpak.nix
    ../../modules/pipewire.nix
    ../../modules/flatpak.nix
    ../../modules/intel.nix
    ../../modules/wayland.nix
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
    enabled = "fcitx5";
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

  environment.sessionVariables = {

  };

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
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

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

  # Customize the package set
  environment.systemPackages = let
    stable-packages = with pkgs;
      [
        # 稳定版本的软件包 (仅保留此主机特有的)
        vlc
      ];

    unstable-packages = with pkgs.unstable;
      [
        # 不稳定版本的软件包 (仅保留此主机特有的)
      ];
  in stable-packages ++ unstable-packages;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

}
