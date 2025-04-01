{ config, lib, pkgs, username, nix-index-database, ... }:

{
  imports = [
    ./cli.nix
    ./editors.nix
    nix-index-database.hmModules.nix-index
  ];

  home = {
    username = username;
    homeDirectory = "/home/${username}";
    stateVersion = "22.11";
    
    sessionVariables = {
      EDITOR = "nvim";
      SHELL = "/etc/profiles/per-user/${username}/bin/fish";
    };
  };

  programs.home-manager.enable = true;

  programs = {
    fzf = {
      enable = true;
      enableFishIntegration = true;
    };
    lsd = {
      enable = true;
      enableAliases = true;
    };
    zoxide = {
      enable = true;
      enableFishIntegration = true;
      options = [ "--cmd cd" ];
    };
    broot = {
      enable = true;
      enableFishIntegration = true;
    };
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    atuin = {
      enable = true;
      settings = {
        auto_sync = true;
        sync_frequency = "5m";
        dotfiles.enabled = true;
      };
    };
  };
}
