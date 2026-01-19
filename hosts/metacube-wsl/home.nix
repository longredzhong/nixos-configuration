{
  config,
  pkgs,
  lib,
  username,
  inputs,
  hostname,
  channels,
  ...
}:
let
  overlayModule = import ../../modules/overlays.nix { inherit inputs; };
  hmOverlays = overlayModule.nixpkgs.overlays;
in
{
  home-manager.users.${username} = {
    imports = [
      # Use WSL profile (includes common + cli-environment + wsl)
      ../../modules/home-manager/profiles/wsl.nix
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
    programs = {
      # Provide identity and per-directory include; enable/delta come from shared git module
      git = {
        settings.user = {
          name = "longred";
          email = "longredzhong@outlook.com";
        };
        includes = [
          {
            path = "~/.gitconfig-adtiger";
            condition = "gitdir:/home/longred/adtiger-project/";
          }
        ];
      };
    };
    # The included Git config file providing the adtiger identity
    home.file.".gitconfig-adtiger".text = ''
      [user]
        name = zhongchanghong
        email = zhongchanghong@adtiger.hk
    '';

  };

}
