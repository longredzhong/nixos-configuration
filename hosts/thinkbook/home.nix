{
  pkgs,
  username,
  inputs,
  ...
}:
let
  hmOverlays = (import ../../modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
in
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];
  home-manager.backupFileExtension = "backups";
  home-manager.users.${username} = {
    imports = [
      # Use desktop profile (includes common + cli-environment + desktop)
      ../../modules/home-manager/profiles/desktop.nix
    ];
    nixpkgs.overlays = hmOverlays;
  };
}
