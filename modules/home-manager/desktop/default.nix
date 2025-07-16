{ inputs, ... }:
{
  imports = [
    ./cava.nix # audio visualizer
    ./fcitx5.nix # input method
    ./fonts.nix # fonts settings
    ./xorg.nix # xorg configuration
    ./plasma-manager.nix
    ./xdg-mimes.nix # xdg config
  ];
}
