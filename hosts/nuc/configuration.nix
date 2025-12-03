{ username, hostname, pkgs, lib, inputs, config, options, nixpkgs, ... }: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/system/common.nix
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-index-database.nixosModules.nix-index
    inputs.agenix.nixosModules.default
    # Import the new agenix config module, not the secrets data file
    ../../modules/services/deeplx.nix
    ../../modules/services/dufs.nix
    ../../secrets/agenix-config.nix
    ../../modules/system/desktop/kde.nix
    ../../modules/system/apps/flatpak.nix
    ../../modules/system/audio/pipewire.nix
    ../../modules/system/hardware/intel.nix
    ../../modules/system/desktop/wayland.nix
  ];
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "${hostname}"; # Define your hostname.
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Shanghai";

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
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      fcitx5-rime
      qt6Packages.fcitx5-chinese-addons
      qt6Packages.fcitx5-configtool
      fcitx5-nord
      rime-data
    ];
    fcitx5.waylandFrontend = true;
  };
  environment.variables = {
    XIM = "fcitx";
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    INPUT_METHOD = "fcitx";
    SDL_IM_MODULE = "fcitx";
  };
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

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

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "${username}";

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = let
    stable-packages = with pkgs; [ qbittorrent vlc acpi powertop ];
    unstable-packages = with pkgs.unstable; [ ];
  in stable-packages ++ unstable-packages;

  services.openssh.enable = true;
  networking.firewall.enable = false;

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
  services.cloudflared = {
    enable = true;
    package = pkgs.unstable.cloudflared;
    tunnels = {
      "25fc2bee-86de-4b26-ab23-c7c25d2fd9f8" = {
        credentialsFile = "${config.age.secrets."cloudflare-tunnel-nuc".path}";
        default = "http_status:404";
      };
    };
  };
}
