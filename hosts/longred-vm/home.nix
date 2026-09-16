{ pkgs, inputs, username, hostname, ... }:
let
  hmOverlays = (import ../../modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
in
{
  home-manager.backupFileExtension = "backups";
  home-manager.extraSpecialArgs = { inherit hostname; };
  home-manager.users.${username} = {
    imports = [
      # CLI-only environment: this guest is a clean base, not a workstation.
      ../../modules/home-manager/profiles/minimal.nix
    ];
    nixpkgs.overlays = hmOverlays;

    home.packages = with pkgs; [
      git
      jq
    ];
  };
}
