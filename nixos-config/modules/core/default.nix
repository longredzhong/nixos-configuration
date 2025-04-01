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

  environment = {
    enableAllTerminfo = true;
    pathsToLink = [ "/share/fish" ];
    shells = [ pkgs.fish ];
    systemPackages = with pkgs; [
      vim
      git
      wget
      curl
      htop
    ];
  };

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
      package = pkgs.nix-ld-rs;
      libraries = with pkgs; [
        glib
      ];
    };
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
    shell = pkgs.fish;
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
    package = pkgs.unstable.tailscale;
    extraUpFlags = [ "--ssh" ];
  };

  # Ensure state version is consistent
  system.stateVersion = "24.11";
}
