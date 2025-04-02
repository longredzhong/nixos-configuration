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
            nur.overlays.default
            jeezyvim.overlays.default
            (final: prev: {
              unstable = import nixpkgs-unstable {
                inherit (prev) system;
                config.allowUnfree = true;
              };
            })
            (final: prev: import ./overlays { inherit inputs final prev; })
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
          isWsl ? false,
          isHeadless ? false,
          developmentLanguages ? [ "nix" ],
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
                users.${username} =
                  { ... }:
                  {
                    imports = [ ./home-manager/default.nix ];
                    custom = {
                      inherit isWsl isHeadless;
                      development = {
                        enable = true;
                        languages = developmentLanguages;
                      };
                    };
                  };
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
          isWsl = false;
          isHeadless = false;
          developmentLanguages = [
            "nix"
            "python"
            "rust"
            "go"
          ];
          extraModules = [
            ./hosts/nuc
          ];
        };

        # WSL configurations
        thinkbook-wsl = mkHost {
          hostname = "thinkbook-wsl";
          username = "longred";
          isWsl = true;
          isHeadless = true;
          developmentLanguages = [
            "nix"
            "python"
            "node"
            "cpp"
            "go"
            "rust"
          ];
          extraModules = [
            nixos-wsl.nixosModules.wsl
            ./hosts/wsl
          ];
        };

        metacube-wsl = mkHost {
          hostname = "metacube-wsl";
          username = "longred";
          isWsl = true;
          isHeadless = true;
          developmentLanguages = [
            "nix"
            "python"
            "node"
            "cpp"
          ];
          extraModules = [
            nixos-wsl.nixosModules.wsl
            ./hosts/wsl
          ];
        };

        vm-test = mkHost {
          hostname = "vm-test";
          username = "longred";
          isHeadless = true;
          extraModules = [
            ./hosts/vm
          ];
        };
      };
    };
}
