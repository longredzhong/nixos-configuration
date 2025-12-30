# Desktop profile - Full desktop environment with GUI apps
# Use for: thinkbook, nuc (native NixOS with KDE)
{ inputs, ... }:
{
  imports = [
    ../common.nix
    ../cli-environment.nix
    ../desktop/default.nix
  ];

  # Desktop-specific defaults
  xdg.enable = true;

  # Allow unfree packages (for vscode, chrome, etc.)
  nixpkgs.config.allowUnfree = true;
}
