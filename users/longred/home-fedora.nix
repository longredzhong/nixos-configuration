{ config, pkgs, inputs, username, hostname, channels, ... }:
{
  # Use unstable as an overlay namespace
  nixpkgs = {
    overlays = (import ../../modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
    config.allowUnfree = true;
  };

  home = {
    username = "${username}";
    homeDirectory = "/home/${username}";
    stateVersion = "25.05";
  };

  # Reuse curated HM modules
  imports = [
    ../../modules/home-manager/common.nix
    ../../modules/home-manager/cli-environment.nix
  ];

  # User specific additions for dev environment
  programs = {
    # Shell & tools
    fish.enable = true;
    starship.enable = true;
    git = {
      enable = true;
      userName = "longred";
      userEmail = "longredzhong@outlook.com";
    };
    tmux.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  # Packages for development (stable + unstable)
  home.packages = let
    stable = with pkgs; [
      gcc gnumake pkg-config
      curl wget unzip zip
      openssl
      neovim
      nodejs_22 python3 go rustup
      docker-compose
      just
    ];
    unstable = with pkgs.unstable; [
      vscode
      uv
      bun
      gh
    ];
  in stable ++ unstable;

  # Basic editor variable
  home.sessionVariables.EDITOR = "nvim";

  # Git delta pretty
  programs.git.delta = {
    enable = true;
    options = {
      line-numbers = true;
      side-by-side = true;
      navigate = true;
    };
  };
}
