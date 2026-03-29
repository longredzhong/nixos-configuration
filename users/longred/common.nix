# Shared configuration for standalone Home Manager targets (non-NixOS hosts)
{ username, pkgs, ... }:
{
  home.username = username;

  imports = [
    ../../modules/home-manager/common.nix
    ../../modules/home-manager/cli-environment.nix
    ../../modules/home-manager/desktop/ghostty.nix
  ];

  programs.git = {
    settings.user = {
      name = "longred";
      email = "longredzhong@outlook.com";
    };
    includes = [
      {
        path = "~/.gitconfig-adtiger";
        condition = "gitdir:/home/longred/adtiger-project/";
      }
    ];
  };

  home.file.".gitconfig-adtiger".text = ''
    [user]
      name = zhongchanghong
      email = zhongchanghong@adtiger.hk
  '';

  # Development packages shared across all standalone HM targets
  home.packages =
    let
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
      unstable = with pkgs.unstable; [
        gh
      ];
    in
    stable ++ unstable;

  home.sessionVariables.EDITOR = "nvim";
}
