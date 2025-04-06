{ username
, hostName
, pkgs
, lib
, inputs
, config
, options
, nixpkgs
, ...
}:
{
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
  system.stateVersion = "24.11";
  wsl = {
    enable = true;
    wslConf.automount.root = "/mnt";
    wslConf.interop.appendWindowsPath = false;
    wslConf.network.generateHosts = true;
    defaultUser = username;
    startMenuLaunchers = true;
    useWindowsDriver = true;
    populateBin = true;
  };
}
