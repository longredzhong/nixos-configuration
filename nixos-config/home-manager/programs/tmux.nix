{ config, lib, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    shell = "/run/current-system/sw/bin/bash";
    prefix = "C-a";
    mouse = true;
    keyMode = "vi";
    
    extraConfig = ''
      # 键绑定设置
      bind c new-window
      bind n next-window
      bind p previous-window
    '';
  };
}