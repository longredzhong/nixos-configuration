{ pkgs, config, lib, username, hostName, channels, options, ... }:
let
  stable-packages = with pkgs; [
    # 这里的包会被安装到系统中
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
  ];
  unstable-packages = with pkgs.unstable; [ rustup micromamba pixi just ];
in {
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
      ];

      trusted-public-keys = [
        # the default public key of cache.nixos.org, it's built-in, no need to add it here
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
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
  environment.systemPackages = stable-packages ++ unstable-packages
    ++ [ pkgs.age ];  # agenix 已经通过 flake 引入，不需要添加在这里

  # 配置 SSH 密钥
  # age.secrets = {
  #   "ssh_id_ed25519" = {
  #     file = ../secrets/ssh/id_ed25519.age;
  #     path = "/home/${username}/.ssh/id_ed25519";
  #     owner = username;
  #     group = "users";
  #     mode = "0600"; # SSH 私钥需要严格的权限
  #   };

  #   "ssh_id_ed25519_pub" = {
  #     file = ../secrets/ssh/id_ed25519.pub.age;
  #     path = "/home/${username}/.ssh/id_ed25519.pub";
  #     owner = username;
  #     group = "users";
  #     mode = "0644"; # 公钥权限可以宽松一些
  #   };

  #   "ssh_config" = {
  #     file = ../secrets/ssh/config.age;
  #     path = "/home/${username}/.ssh/config";
  #     owner = username;
  #     group = "users";
  #     mode = "0600";
  #   };

  #   "ssh_known_hosts" = {
  #     file = ../secrets/ssh/known_hosts.age;
  #     path = "/home/${username}/.ssh/known_hosts";
  #     owner = username;
  #     group = "users";
  #     mode = "0644";
  #   };
  # };

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
  programs.fish.enable = true;
  programs.fish.package = pkgs.unstable.fish;
  # 系统状态版本（不要轻易改变）
  system.stateVersion = "24.11";
}
