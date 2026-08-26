# Shared configuration for standalone Home Manager targets (non-NixOS hosts)
{ username, pkgs, ... }:
{
  home.username = username;

  imports = [
    ./git-identity.nix
    ../../modules/home-manager/common.nix
    ../../modules/home-manager/cli-environment.nix
    ../../modules/home-manager/desktop/ghostty.nix
  ];

  # Development packages shared across all standalone HM targets
  home.packages =
    let
      stable = with pkgs; [
        # gcc
        # gnumake
        # pkg-config
        # curl
        # wget
        # unzip
        # zip
        # openssl
        neovim
        # nodejs_22
        # python3
        # go
        # rustup
        docker-compose
      ];
      unstable = with pkgs.unstable; [
        gh
      ];
    in
    stable ++ unstable;
}
