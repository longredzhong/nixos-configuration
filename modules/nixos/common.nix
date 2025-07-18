{ pkgs, config, lib, username, hostname, channels, options, ... }:
let
  stable-packages = with pkgs; [
    coreutils
    curl
    wget
    git
    vim
    htop
    ripgrep
    fd
    tree
    unzip
    zip
    jq
    fzf
    btop
    nvme-cli
    nmap
    inetutils
    dig
    nixpkgs-fmt
    watchman
    nixfmt-classic
    nixfmt-rfc-style
    age
    just
    direnv
    ssh-to-age
    go
  ];
  unstable-packages = with pkgs.unstable; [ ];
in {
  # 系统状态版本（不要轻易改变）
  system.stateVersion = "25.05";
  networking.hostName = "${hostname}";
  networking.networkmanager.enable = true;
  nixpkgs.config.allowUnfree = true;
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
    daemon.settings = { "features" = { "buildkit" = true; }; };

  };
  programs.fish.enable = true;
  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.unstable.fish;
    extraGroups = [ "networkmanager" "wheel" "docker" ];
  };
  i18n = {
    defaultLocale = "en_US.UTF-8";
    supportedLocales = [ "en_US.UTF-8/UTF-8" "zh_CN.UTF-8/UTF-8" ];
    extraLocaleSettings = {
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
  };
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      warn-dirty = false;

      # 设置可信用户
      trusted-users = [ "root" "@wheel" ];
      substituters = [
        # cache mirror located in China
        # status: https://mirror.sjtu.edu.cn/
        # "https://mirror.sjtu.edu.cn/nix-channels/store"
        # status: https://mirrors.ustc.edu.cn/status/
        "https://mirrors.ustc.edu.cn/nix-channels/store"

        "https://cache.nixos.org"

        "https://cosmic.cachix.org"
      ];

      trusted-public-keys = [
        # the default public key of cache.nixos.org, it's built-in, no need to add it here
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
      ];
    };

    # 自动垃圾回收
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
  # 系统安全设置
  security.sudo.wheelNeedsPassword = false;

  # 常用服务
  services = {
    # SSH服务
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };
    # tailscale 服务
    tailscale = {
      enable = true;
      package = pkgs.unstable.tailscale;
      extraUpFlags = "--ssh";
    };
    # 时间同步
    timesyncd.enable = true;
  };
  # 常用软件包
  # 这里的包会被安装到系统中
  environment.systemPackages = stable-packages ++ unstable-packages ++ [ ];

  # 确保 .ssh 目录存在并有正确权限
  system.activationScripts.sshUserDir = ''
    mkdir -p /home/${username}/.ssh
    chown ${username}:users /home/${username}/.ssh
    chmod 700 /home/${username}/.ssh
  '';
  programs.nix-ld = {
    enable = true;
    package = pkgs.nix-ld-rs;
    libraries = options.programs.nix-ld.libraries.default
      ++ (with pkgs; [ glib ]);
  };

}
