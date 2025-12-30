{ inputs, ... }:
{
  imports = [
    ./cava.nix # audio visualizer
    ./rime.nix # rime input method configuration
    ./fonts.nix # fonts settings
    ./xorg.nix # xorg configuration
    ./plasma-manager.nix
    ./xdg-mimes.nix # xdg config
  ];
}
