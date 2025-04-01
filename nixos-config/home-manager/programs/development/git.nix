{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    package = pkgs.unstable.git;
    lfs.enable = true;
    delta.enable = true;
    delta.options = {
      line-numbers = true;
      side-by-side = true;
      navigate = true;
    };
    userEmail = "longredzhong@outlook.com";
    userName = "longred";
    extraConfig = {
      push = {
        default = "current";
        autoSetupRemote = true;
      };
      merge = {
        conflictstyle = "diff3";
      };
      diff = {
        colorMoved = "default";
      };
    };
  };
}
