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

  # Ensure state version is consistent
  system.stateVersion = "24.11";
}
