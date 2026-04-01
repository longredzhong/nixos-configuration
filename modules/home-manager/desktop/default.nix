{ inputs, ... }:
{
  imports = [
    ./packages.nix # common desktop packages
    ./ghostty.nix # ghostty terminal configuration
    ./cava.nix # audio visualizer
    ./rime.nix # rime input method configuration
    ./fonts.nix # fonts settings
    ./xorg.nix # xorg configuration
    ./xdg-mimes.nix # xdg config
  ];
}
