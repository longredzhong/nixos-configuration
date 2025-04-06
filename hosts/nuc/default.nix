{
  username,
  hostName,
  pkgs,
  lib,
  inputs,
  config,
  options,
  nixpkgs,
  ...
}:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  imports = [
    ./hardware-configuration.nix
  ];

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
    daemon.settings = {
      "features" = {
        "buildkit" = true;
      };
    };
  };
  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };
  networking.hostName = "${hostName}";
  networking.networkmanager.enable = true;
  programs.fish.enable = true;
  system.stateVersion = "24.11"; # Added to avoid warnings
}
