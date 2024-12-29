{ secrets
, username
, hostname
, pkgs
, inputs
, config
, options
, networking
, ...
}: {

  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./k3s.nix
      ./cloudflared.nix
      ./mihomo.nix
    ];

  time.timeZone = "Asia/Shanghai";
  networking.hostName = "${hostname}";
  programs.fish.enable = true;
  environment.pathsToLink = [ "/share/fish" ];
  environment.shells = [ pkgs.fish ];

  environment.enableAllTerminfo = true;

  security.sudo.wheelNeedsPassword = false;

  users.users.${username} = {
    isNormalUser = true;

    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    # FIXME: add your own hashed password
    # hashedPassword = "";
    # FIXME: add your own ssh public key
    # openssh.authorizedKeys.keys = [
    #   "ssh-rsa ..."
    # ];
    packages = with pkgs; [
      kdePackages.kate
      thunderbird
    ];
  };

  home-manager.users.${username} = {
    imports = [
      ./home.nix
    ];
  };

  environment.variables = {
    NIXPKGS_ALLOW_UNFREE = 1;
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
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
  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # set tailscale
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
    extraUpFlags = "--ssh";
  };

  services.minio = {
    enable = true;
    accessKey = secrets.minio.accessKey;
    secretKey = secrets.minio.secretKey;
  };

  environment.systemPackages = with pkgs; [
    dufs
  ];

  systemd.services.dufs = {
    description = "DUFS Service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.dufs}/bin/dufs -A -p 5000 -a ${secrets.minio.accessKey}:${secrets.minio.secretKey}@/:rw /var/lib/dufs";
      Restart = "always";
      RestartSec = "10s";
    };
  };

  networking.firewall = {
    # enable the firewall
    enable = true;
    # always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];
    # allow the Tailscale UDP port through the firewall
    allowedUDPPorts = [
      config.services.tailscale.port
      8472
      51820
      51821
      7890
    ];
    # let you SSH in over the public internet
    allowedTCPPorts = [
      22
      6443
      2379
      2380
      10250
      7890
    ];
  };
  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
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
    daemon.settings = {
      "registry-mirrors" = [ "https://docker.longred.work" ];
    };
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      X11Forwarding = true;
      PermitRootLogin = "no"; # disable root login
      PasswordAuthentication = true; # disable password login
    };
    openFirewall = true;
  };



  programs.nix-ld = {
    enable = true;
    package = pkgs.nix-ld-rs;
    libraries = options.programs.nix-ld.libraries.default ++ (with pkgs; [
      glib
    ]);
  };
  system.stateVersion = "24.11";
}
