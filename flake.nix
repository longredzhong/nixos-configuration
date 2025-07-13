{
  description = "A NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };
  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, nixos-wsl
    , agenix, nix-index-database, ... }: {
      nixosConfigurations = {
        metacube-wsl = let
          username = "longred";
          hostname = "metacube-wsl";
          specialArgs = {
            inherit username hostname;
            channels = { inherit nixpkgs nixpkgs-unstable; };
            inherit inputs;
          };
        in nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "x86_64-linux";
          modules = [
            ./modules/overlays.nix
            ./hosts/${hostname}/nixos.nix
            ./hosts/${hostname}/home.nix
            ./users/${username}
          ];
        };
        thinkbook-wsl = let
          username = "longred";
          hostname = "thinkbook-wsl";
          specialArgs = {
            inherit username hostname;
            channels = { inherit nixpkgs nixpkgs-unstable; };
            inherit inputs;
          };
        in nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "x86_64-linux";
          modules = [
            ./modules/overlays.nix
            ./hosts/${hostname}/nixos.nix
            ./hosts/${hostname}/home.nix
            ./users/${username}
          ];
        };
        nuc = let
          username = "longred";
          hostname = "nuc";
          specialArgs = {
            inherit username hostname;
            channels = { inherit nixpkgs nixpkgs-unstable; };
            inherit inputs;
          };
        in nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "x86_64-linux";
          modules = [
            ./modules/overlays.nix
            ./hosts/${hostname}/nixos.nix
            ./hosts/${hostname}/home.nix
            ./users/${username}
          ];
        };
        thinkbook = let
          username = "longred";
          hostname = "thinkbook";
          specialArgs = {
            inherit username hostname;
            channels = { inherit nixpkgs nixpkgs-unstable; };
            inherit inputs;
          };
        in nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "x86_64-linux";
          modules = [
            ./modules/overlays.nix
            ./hosts/${hostname}/nixos.nix
            ./hosts/${hostname}/home.nix
            ./users/${username}
          ];
        };
      };

    };
}
