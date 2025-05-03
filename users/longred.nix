{ config, pkgs, ... }:

let
  unstable-packages = with pkgs.unstable; [ nvitop juicefs ffmpeg ];
  stable-packages = with pkgs; [ expat ];
in {

  users.users.longred = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJndrhj8hUnT6hKAtd2+jIzoAJV8oo0NoTjQ73rdgiOC"
    ];
  };

  home-manager.users.longred = {
    programs.home-manager.enable = true;
    home = {
      username = "longred";
      homeDirectory = "/home/longred";
      stateVersion = "24.11";
      packages = stable-packages ++ unstable-packages ++ [ ];
    };

    imports = [ ../home/cli-environment.nix ];
    programs = {
      fish.enable = true;
      fzf.enable = true;
      fzf.enableFishIntegration = true;
      lsd.enable = true;
      lsd.enableAliases = true;
      broot.enable = true;
      broot.enableFishIntegration = true;
      direnv.enable = true;
      direnv.nix-direnv.enable = true;
      git = {
        userEmail = "longredzhong@outlook.com";
        userName = "longred";
      };
    };
  };
}
