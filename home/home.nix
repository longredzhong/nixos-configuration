{
  pkgs,
  config,
  lib,
  username,
  hostName,
  ...
}:
{
  programs.home-manager.enable = true;
  home = {
    username = username;
    homeDirectory = lib.mkForce "/home/${username}";
    stateVersion = "24.11";
  };

}
