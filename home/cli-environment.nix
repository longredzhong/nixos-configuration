{ pkgs, ... }: {
  imports = [
    ./shell/fish.nix
    ./shell/starship.nix
    ./shell/atuin.nix
    ./shell/git.nix
    ./shell/tmux.nix
    ./cli-tools.nix
    ./monitoring.nix
  ];
}
