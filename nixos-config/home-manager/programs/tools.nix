{ config, lib, pkgs, ... }:

{
  programs = {
    nix-index.enable = true;
    nix-index.enableFishIntegration = true;
    nix-index-database.comma.enable = true;
    
    fzf.enable = true;
    fzf.enableFishIntegration = true;
    
    lsd.enable = true;
    lsd.enableAliases = true;
    
    zoxide.enable = true;
    zoxide.enableFishIntegration = true;
    zoxide.options = [ "--cmd cd" ];
    
    broot.enable = true;
    broot.enableFishIntegration = true;
    
    direnv.enable = true;
    direnv.nix-direnv.enable = true;
    
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