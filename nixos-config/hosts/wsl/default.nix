{
  username,
  hostname,
  pkgs,
  lib,
  inputs,
  config,
  options,
  nixpkgs,
  ...
}:
{
  imports = [
    ../../modules/core/default.nix
    # ../../modules/services/postgresql.nix
  ];
  networking.hostName = "${hostname}";
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      libGL
      mesa
      libglvnd
    ];
  };
  wsl = {
    enable = true;
    wslConf.automount.root = "/mnt";
    wslConf.interop.appendWindowsPath = false;
    wslConf.network.generateHosts = true;
    defaultUser = username;
    startMenuLaunchers = true;
    useWindowsDriver = true;
    populateBin = true;

    extraBin = with pkgs; [
      # Binaries for Docker Desktop wsl-distro-proxy
      { src = "${coreutils}/bin/mkdir"; }
      { src = "${coreutils}/bin/cat"; }
      { src = "${coreutils}/bin/whoami"; }
      { src = "${coreutils}/bin/ls"; }
      { src = "${coreutils}/bin/uname"; }
      { src = "${busybox}/bin/addgroup"; }
      { src = "${su}/bin/groupadd"; }
      { src = "${su}/bin/usermod"; }
    ];
  };

  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };
}
