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
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = true;
    settings.port = 5432;
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
      # ipv4
      host  all      all     127.0.0.1/32   trust
      # ipv6
      host all       all     ::1/128        trust
    '';
    extensions = [ pkgs.postgresql17Packages.pgvector ];
  };

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

  imports = [ ];

  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };

  services = {
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = true;
      };
      openFirewall = true;
    };
    tailscale = {
      enable = true;
      package = pkgs.unstable.tailscale;
      extraUpFlags = "--ssh";
    };
  };
}
