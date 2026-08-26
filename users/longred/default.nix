{ config, pkgs, ... }:
{
  home-manager.users.longred = {
    imports = [ ./git-identity.nix ];
    home.packages = with pkgs; [ gh ];
  };

}
