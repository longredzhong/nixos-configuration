# User-level additions for the `dev` account on the longred-vm guest.
#
# The account exists because the machine was provisioned with that login; the
# NixOS host definition in hosts/longred-vm/configuration.nix creates it and
# owns its SSH access. This module only adds user packages.
{ pkgs, ... }:
{
  home-manager.users.dev = {
    home.packages = with pkgs; [
      gh
      ripgrep
    ];
  };
}
