{
  description = "A NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    try.url = "github:tobi/try";
  };
  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, nixos-wsl
    , agenix, nix-index-database, ... }:
    let
      # Helper function to create NixOS system configurations
      mkNixosSystem = { username, hostname, system ? "x86_64-linux" }:
        let
          specialArgs = {
            inherit username hostname;
            channels = { inherit nixpkgs nixpkgs-unstable; };
            inherit inputs;
          };
        in nixpkgs.lib.nixosSystem {
          inherit specialArgs system;
          modules = [
            ./modules/overlays.nix
            ./hosts/${hostname}/configuration.nix
            ./hosts/${hostname}/home.nix
            ./users/${username}
          ];
        };
    in {
      nixosConfigurations = {
        metacube-wsl = mkNixosSystem {
          username = "longred";
          hostname = "metacube-wsl";
        };
        thinkbook-wsl = mkNixosSystem {
          username = "longred";
          hostname = "thinkbook-wsl";
        };
        nuc = mkNixosSystem {
          username = "longred";
          hostname = "nuc";
        };
        thinkbook = mkNixosSystem {
          username = "longred";
          hostname = "thinkbook";
        };
      };

      # Standalone Home Manager configs (for non-NixOS hosts)
      homeConfigurations = let
        system = "x86_64-linux";
        overlays =
          (import ./modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
        pkgs = import nixpkgs {
          inherit system;
          config = { allowUnfree = true; };
          overlays = overlays;
        };
        
        # Helper function to create Home Manager configurations
        mkHomeConfig = { username, hostname, module }:
          home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            extraSpecialArgs = {
              inherit username hostname;
              channels = { inherit nixpkgs nixpkgs-unstable; };
              inherit inputs;
            };
            modules = [ module ];
          };
      in {
        # Current machine detected as `fedora-thinkbook`
        "longred@fedora-thinkbook" = mkHomeConfig {
          username = "longred";
          hostname = "fedora-thinkbook";
          module = ./users/longred/fedora-thinkbook.nix;
        };
        "longred@nuc" = mkHomeConfig {
          username = "longred";
          hostname = "nuc";
          module = ./users/longred/nuc.nix;
        };
      };

      # Expose custom packages for convenience (nix build .#pixi)
      packages.x86_64-linux = let
        overlays =
          (import ./modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          inherit overlays;
          config.allowUnfree = true;
        };
      in {
        inherit (pkgs) pixi mamba-cpp;
      };

    };
}
