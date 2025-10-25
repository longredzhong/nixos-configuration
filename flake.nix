{
  description = "A NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
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
            ./hosts/${hostname}/configuration.nix
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
            ./hosts/${hostname}/configuration.nix
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
            ./hosts/${hostname}/configuration.nix
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
            ./hosts/${hostname}/configuration.nix
            ./hosts/${hostname}/home.nix
            ./users/${username}
          ];
        };
      };

      # Standalone Home Manager configs (for non-NixOS hosts)
      homeConfigurations = let
        system = "x86_64-linux";
        pkgsFor = nixpkgs: overlays:
          import nixpkgs {
            inherit system;
            config = { allowUnfree = true; };
            overlays = overlays;
          };
        overlays =
          (import ./modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
      in {
        # Current machine detected as `fedora-thinkbook`
        "longred@fedora-thinkbook" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor nixpkgs overlays;
          extraSpecialArgs = {
            username = "longred";
            hostname = "fedora-thinkbook";
            channels = { inherit nixpkgs nixpkgs-unstable; };
            inherit inputs;
          };
          modules = [ ./users/longred/fedora-thinkbook.nix ];
        };
        "longred@nuc" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor nixpkgs overlays;
          extraSpecialArgs = {
            username = "longred";
            hostname = "nuc";
            channels = { inherit nixpkgs nixpkgs-unstable; };
            inherit inputs;
          };
          modules = [ ./users/longred/nuc.nix ];
        };
      };

      # Expose custom packages for convenience (nix build .#pixi)
      packages.x86_64-linux = let
        overlays =
          (import ./modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = overlays;
          config.allowUnfree = true;
        };
      in { inherit (pkgs) pixi; };

    };
}
