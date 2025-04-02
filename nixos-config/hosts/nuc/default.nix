{
  secrets,
  username,
  hostname,
  pkgs,
  inputs,
  config,
  options,
  networking,
  ...
}:
{

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/services/cloudflared.nix
    ../../modules/services/deeplx.nix
    ../../modules/services/dufs.nix
    ../../modules/services/k3s.nix
    ../../modules/services/mihomo.nix
    ../../modules/services/minio.nix
  ];
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
  networking.hostName = "${hostname}";

  users.users.${username} = {
    isNormalUser = true;

    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    packages = with pkgs; [
      kdePackages.kate
      thunderbird
    ];
  };
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
    openFirewall = true;
  };
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
  # Tailscale configuration
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
    extraUpFlags = [ "--ssh" ];
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
    ];
  };
  system.stateVersion = "24.11";
}
