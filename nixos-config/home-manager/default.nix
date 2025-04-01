{ config, lib, pkgs, username, nix-index-database, ... }:

{
  imports = [
    nix-index-database.hmModules.nix-index
    ./packages.nix
    ./options.nix
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
  
  # 启用 nix-index 和相关功能
  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
  };
  programs.nix-index-database.comma.enable = true;
}
