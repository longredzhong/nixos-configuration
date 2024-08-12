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
    ];

  # FIXME: change to your tz! look it up with "timedatectl list-timezones"
  time.timeZone = "Asia/Shanghai";
  networking.hostName = "${hostname}";
  # FIXME: change your shell here if you don't want fish
  programs.fish.enable = true;
  environment.pathsToLink = [ "/share/fish" ];
  environment.shells = [ pkgs.fish ];

  environment.enableAllTerminfo = true;

  security.sudo.wheelNeedsPassword = false;

  # FIXME: uncomment the next line to enable SSH
  # services.openssh.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    # FIXME: change your shell here if you don't want fish
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      # FIXME: uncomment the next line if you want to run docker without sudo
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

  networking.firewall = {
    # enable the firewall
    enable = true;
    # always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];
    # allow the Tailscale UDP port through the firewall
    allowedUDPPorts = [ config.services.tailscale.port ];
    # let you SSH in over the public internet
    allowedTCPPorts = [
      22
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

  services.minio = {
    enable = true;
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
  system.stateVersion = "24.05";
}
