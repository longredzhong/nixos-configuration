{ config, pkgs, ... }:

{
  users.users.longred = {
    openssh.authorizedKeys.keys = [

    ];
  };

  home-manager.users.longred = {
    programs.home-manager.enable = true;
    home = {
      username = "longred";
      homeDirectory = "/home/longred";
      stateVersion = "24.11";
    };
    imports = [
      ../home/shell/fish.nix
      ../home/shell/git.nix
    ];
    programs = {
      broot.enable = true;
      broot.enableFishIntegration = true;
      fzf.enable = true;
      fzf.enableFishIntegration = true;
      lsd.enable = true;
      lsd.enableAliases = true;
      zoxide.enable = true;
      zoxide.enableFishIntegration = true;
      zoxide.options = [ "--cmd cd" ];
    };
  };
}
