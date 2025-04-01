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
}