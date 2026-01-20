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
  };
  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nixos-wsl,
      agenix,
      nix-index-database,
      ...
    }:
    let
      # ============================================================
      # Helper function to create NixOS configurations
      # ============================================================
      mkHost =
        {
          hostname,
          username ? "longred",
          system ? "x86_64-linux",
          extraModules ? [ ],
        }:
        let
          specialArgs = {
            inherit username hostname inputs;
            channels = {
              inherit nixpkgs nixpkgs-unstable;
            };
          };
        in
        nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ./modules/overlays.nix
            ./hosts/${hostname}/configuration.nix
            ./hosts/${hostname}/home.nix
            ./users/${username}
          ] ++ extraModules;
        };

      # ============================================================
      # Helper function to create standalone Home Manager configurations
      # ============================================================
      mkHome =
        {
          username,
          hostname,
          system ? "x86_64-linux",
          modules,
        }:
        let
          overlays = (import ./modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = overlays;
          };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit username hostname inputs;
            channels = {
              inherit nixpkgs nixpkgs-unstable;
            };
          };
          modules = [
            # Enable agenix for Home Manager
            agenix.homeManagerModules.default
          ] ++ modules;
        };
    in
    {
      # ============================================================
      # NixOS System Configurations
      # ============================================================
      nixosConfigurations = {
        metacube-wsl = mkHost { hostname = "metacube-wsl"; };
        thinkbook-wsl = mkHost { hostname = "thinkbook-wsl"; };
        nuc = mkHost { hostname = "nuc"; };
        thinkbook = mkHost { hostname = "thinkbook"; };
      };

      # ============================================================
      # Standalone Home Manager Configurations (for non-NixOS hosts)
      # ============================================================
      homeConfigurations = {
        "longred@fedora-thinkbook" = mkHome {
          username = "longred";
          hostname = "fedora-thinkbook";
          modules = [ ./users/longred/fedora-thinkbook.nix ];
        };
        "longred@nuc" = mkHome {
          username = "longred";
          hostname = "nuc";
          modules = [ ./users/longred/nuc.nix ];
        };
      };

      # ============================================================
      # Custom Packages
      # ============================================================
      packages.x86_64-linux =
        let
          overlays = (import ./modules/overlays.nix { inherit inputs; }).nixpkgs.overlays;
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = overlays;
            config.allowUnfree = true;
          };
        in
        {
          inherit (pkgs) pixi;
        };

    };
}
