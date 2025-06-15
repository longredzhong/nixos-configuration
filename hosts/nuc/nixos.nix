{ username, hostname, pkgs, lib, inputs, config, options, nixpkgs, ... }: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-index-database.nixosModules.nix-index
    inputs.agenix.nixosModules.default
    # Import the new agenix config module, not the secrets data file
    ../../modules/services/deeplx.nix
    ../../modules/services/dufs.nix
    ../../secrets/agenix-config.nix

  ];
  # customize the system services  
  services.plex = {
    enable = true;
    openFirewall = true;
    user = "${username}";
  };
  services.deeplx.enable = true;
  services.dufs = {
    enable = true;
    servePath = "/data/dufs";
    allowAll = true;
    auth = [{
      credentials =
        "admin:$(cat ${config.age.secrets."dufs-admin-credentials".path})";
      path = "/";
      permissions = "rw";
    }];
  };
  services.minio = {
    enable = true;
    listenAddress = ":9000";
    consoleAddress = ":9001";
    dataDir = [ "/data/minio" ];
    rootCredentialsFile = "${config.age.secrets."minio-credentials".path}";
  };
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = true;
    ensureDatabases = [ "postgres" ];
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
      # ipv4
      host  all      all     127.0.0.1/32   trust
    '';
    extensions = ps: with ps; [ postgis pgvector ];
    settings.port = 5432;
  };
  services.postgresqlBackup = {
    enable = true;
    startAt = "*-*-* 01:15:00";
    backupAll = true;
    location = "/data/backup/postgresql";
  };
  # use cloudflared as a DNS over HTTPS proxy
  services.cloudflared = {
    enable = true;
    package = pkgs.unstable.cloudflared;
    tunnels = {
      "25fc2bee-86de-4b26-ab23-c7c25d2fd9f8" = {
        credentialsFile = "${config.age.secrets."cloudflare-tunnel-nuc".path}";
        default = "http_status:404";
        # ingress = {
        #   "nuc-webdav.longred.work" = { service = "http://localhost:5000"; };
        #   "nuc-minio.longred.work" = { service = "http://localhost:9000"; };
        # };
      };
    };
  };
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
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

  # desktopManager
  # Enable the login manager
  services.displayManager.cosmic-greeter.enable = true;
  # Enable the COSMIC DE itself
  services.desktopManager.cosmic.enable = true;
  # Enable XWayland support in COSMIC
  services.desktopManager.cosmic.xwayland.enable = true;

  services.flatpak.enable = true;
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      fcitx5-chinese-addons
      fcitx5-nord
      fcitx5-rime
      rime-data
    ];
    fcitx5.waylandFrontend = true;
  };
  environment.sessionVariables = {
    COSMIC_DATA_CONTROL_ENABLED = 1;
    NIXOS_OZONE_WL = "1";
  };
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
    stable-packages = with pkgs; [
      # 稳定版本的软件包 (仅保留此主机特有的)
      qbittorrent
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
