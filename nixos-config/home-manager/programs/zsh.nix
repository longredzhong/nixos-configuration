{ config, lib, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    
    oh-my-zsh = {
      enable = true;
      theme = "agnoster";
      plugins = [
        "git"
        "docker"
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
      ];
    };
    
    initExtra = ''
      # Custom Zsh configurations can be added here
      export PATH=$HOME/.local/bin:$PATH
    '';
  };
}