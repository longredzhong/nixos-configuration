{ config, lib, pkgs, ... }:

{
  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
  };
}
