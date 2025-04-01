{
  config,
  lib,
  pkgs,
  username,
  ...
}:

{
  # Common system configuration for all hosts
  time.timeZone = "Asia/Shanghai";

  # Nix settings
  nix = {
    settings = {
      trusted-users = [
        "root"
        username
      ];
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      accept-flake-config = true;
    };

    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
    };
  };

  # Common programs
  programs = {
    fish.enable = true;
    nix-ld = {
      enable = true;
      package = lib.mkDefault pkgs.nix-ld-rs;
      libraries = with pkgs; [
        glib
      ];
    };
    firefox.enable = true;
  };

  # Security settings
  security.sudo.wheelNeedsPassword = false;

  # Enable SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
    openFirewall = true;
  };

  # Basic user setup
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };

  # Docker configuration
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
    daemon.settings = {
      "registry-mirrors" = [ "https://docker.longred.work" ];
    };
  };

  # Tailscale configuration
  services.tailscale = {
    enable = true;
    package = lib.mkDefault pkgs.unstable.tailscale;
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
      6443
      2379
      2380
      10250
      7890
    ];
  };

  # Ensure state version is consistent
  system.stateVersion = "24.11";
}
