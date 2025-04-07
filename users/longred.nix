{ config, pkgs, ... }:

let
  unstable-packages = with pkgs.unstable; [ nvitop ];
  stable-packages = with pkgs; [ ];
in
{

  users.users.longred = {
    openssh.authorizedKeys.keys = [
      # 这里应该填入与加密私钥对应的公钥
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJqRxH9Kk4St9Vm+5GRyeHIHOxttJj7f4jLxuNVaLgX3 longred@example.com"
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

    imports = [
      ../home/cli-environment.nix
    ];
    programs = {
      fish.enable = true;
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
      git = {
        userEmail = "longredzhong@outlook.com";
        userName = "longred";
      };
    };
  };
}
