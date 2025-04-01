{ config, lib, pkgs, ... }:

{
  imports = [
    ./atuin.nix
    ./direnv.nix
    ./fzf.nix
    ./shell-utils.nix
  ];
}
