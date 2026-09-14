{
  pkgs,
  username,
  inputs,
  hostname,
  ...
}:
let
  hmOverlays = (import ../../modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
in
{
  home-manager.backupFileExtension = "backups";
  home-manager.extraSpecialArgs = { inherit hostname; };
  home-manager.users.${username} = {
    imports = [
      inputs.agenix.homeManagerModules.default
      # Use WSL profile (includes common + cli-environment + wsl)
      # Shared Git identity (longred + adtiger)
      ../../users/longred/git-identity.nix
      ../../modules/home-manager/profiles/wsl.nix
      ../../modules/host-services/openobserve-agent.nix
    ];
    nixpkgs.overlays = hmOverlays;

    # Host-specific packages
    home.packages =
      let
        stable-packages = with pkgs; [
          # 稳定版本的软件包 (仅保留此主机特有的)
          git
          neovim
        ];

        unstable-packages = with pkgs.unstable; [
          # 不稳定版本的软件包 (仅保留此主机特有的)
          nvitop
        ];
      in
      stable-packages ++ unstable-packages;
  };
}
