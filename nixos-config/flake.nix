{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur.url = "github:nix-community/NUR";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database.url = "github:Mic92/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    jeezyvim.url = "github:LGUG2Z/JeezyVim";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nur,
      nixos-wsl,
      nix-index-database,
      jeezyvim,
      ...
    }:
    let
      secrets = builtins.fromJSON (builtins.readFile ./secrets.json);

      # System types
      supportedSystems = [ "x86_64-linux" ];

      # Helper function for system-specific configurations
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs with overlays for each system
      nixpkgsWithOverlays = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [ ];
          };
          overlays = [
            nur.overlay
            jeezyvim.overlays.default
            (final: prev: {
              unstable = import nixpkgs-unstable {
                inherit (prev) system;
                config.allowUnfree = true;
              };
            })
            (final: prev: import ./overlays { inherit final prev; })
          ];
        }
      );

      # Common special arguments for both NixOS and home-manager modules
      commonSpecialArgs = system: {
        inherit
          secrets
          inputs
          self
          nix-index-database
          ;
        pkgs = nixpkgsWithOverlays.${system};
      };

      # NixOS configuration for a given host
      mkHost =
        {
          system ? "x86_64-linux",
          hostname,
          username,
          extraModules ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = (commonSpecialArgs system) // {
            inherit hostname username;
          };
          modules = [
            ./modules/core/default.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = (commonSpecialArgs system) // {
                  inherit hostname username;
                };
                users.${username} = ./home-manager/default.nix;
              };
            }
          ] ++ extraModules;
        };
    in
    {
      formatter = forAllSystems (system: nixpkgsWithOverlays.${system}.alejandra);

      nixosConfigurations = {
        # NUC configuration
        nuc = mkHost {
          hostname = "nuc";
          username = "longred";
          extraModules = [
            ./hosts/nuc
            ./modules/services/cloudflared.nix
            ./modules/services/deeplx.nix
            ./modules/services/dufs.nix
            ./modules/services/k3s.nix
            ./modules/services/mihomo.nix
            ./modules/services/minio.nix
          ];
        };

        # WSL configurations
        "thinkbook-wsl" = mkHost {
          hostname = "thinkbook-wsl";
          username = "longred";
          extraModules = [
            nixos-wsl.nixosModules.wsl
            ./hosts/wsl
          ];
        };

        "metacube-wsl" = mkHost {
          hostname = "metacube-wsl";
          username = "longred";
          extraModules = [
            nixos-wsl.nixosModules.wsl
            ./hosts/wsl
          ];
        };

        nixosConfigurations.vm-test = mkHost {
          hostname = "vm-test";
          username = "longred";
          modules = [
            ./hosts/wsl
          ];
        };
      };
    };
}
