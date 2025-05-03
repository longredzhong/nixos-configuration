{ username, hostName, pkgs, lib, inputs, config, options, nixpkgs, ... }: {
  system.stateVersion = "24.11";
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
    daemon.settings = { "features" = { "buildkit" = true; }; };
  };
  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.unstable.fish;
    extraGroups = [ "wheel" "docker" ];
  };

  networking.hostName = "${hostName}";
  networking.networkmanager.enable = true;
  nixpkgs.config.allowUnfree = true;
  environment.sessionVariables = {
    CUDA_PATH = "${pkgs.cudatoolkit}";
    EXTRA_LDFLAGS = "-L/lib -L${pkgs.linuxPackages.nvidia_x11}/lib";
    EXTRA_CCFLAGS = "-I/usr/include";
    LD_LIBRARY_PATH = [
      "/usr/lib/wsl/lib"
      "${pkgs.linuxPackages.nvidia_x11}/lib"
      "${pkgs.ncurses5}/lib"
    ];
    MESA_D3D12_DEFAULT_ADAPTER_NAME = "Nvidia";
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ libGL mesa libglvnd ];
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
  };

  # Removed Xserver/Plasma settings for consistency with metacube-wsl
  # services.xserver.enable = true;
  #
  # services.xserver.displayManager.sddm.enable = true;
  # services.xserver.desktopManager.plasma6.enable = true;
  # services.xserver.displayManager.defaultSession = "plasmax11";

}
