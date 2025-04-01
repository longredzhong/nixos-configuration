{ config, lib, pkgs, ... }:

{
  imports = [
    ./git.nix
    ./languages.nix
  ];
}
