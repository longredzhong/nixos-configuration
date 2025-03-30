{ config, lib, pkgs, ... }:

{
  imports = [
    ./programs/fish.nix
    ./programs/git.nix
    ./programs/starship.nix
    ./programs/tools.nix
    ./programs/neovim.nix
  ];
}