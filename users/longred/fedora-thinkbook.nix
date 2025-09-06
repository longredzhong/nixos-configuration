{ config, pkgs, inputs, username, hostname, channels, ... }: {
  # pkgs (with overlays/allowUnfree) is injected by flake via pkgsFor; don't redefine here

  home = {
    username = "${username}";
    # homeDirectory/stateVersion are defined in modules/home-manager/common.nix
  };

  # Reuse curated HM modules
  imports = [
    ../../modules/home-manager/common.nix
    ../../modules/home-manager/cli-environment.nix
  ];

  # User/host specific additions for dev environment (avoid duplicating shared modules)
  programs = {
    # Provide identity and per-directory include; enable/delta come from shared git module
    git = {
      userName = "longred";
      userEmail = "longredzhong@outlook.com";
      includes = [{
        path = "~/.gitconfig-adtiger";
        condition = "gitdir:/home/longred/adtiger-project/";
      }];
    };

    # direnv is not enabled in shared modules
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  # Packages for development — keep host-specific tools; basics come from cli-environment
  home.packages = let
    stable = with pkgs; [
      gcc
      gnumake
      pkg-config
      curl
      wget
      unzip
      zip
      openssl
      neovim
      nodejs_22
      python3
      go
      rustup
      docker-compose
    ];
    unstable = with pkgs.unstable; [ uv bun gh ];
  in stable ++ unstable;

  # Basic editor variable
  home.sessionVariables.EDITOR = "nvim";

  # The included Git config file providing the adtiger identity
  home.file.".gitconfig-adtiger".text = ''
    [user]
      name = zhongchanghong
      email = zhongchanghong@adtiger.hk
  '';
}
