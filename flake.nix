{
  description = "A NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , nixpkgs-unstable
    , home-manager
    , nixos-wsl
    , agenix
    , nix-index-database
    , ...
    }: {
      nixosConfigurations = {
        metacube-wsl =
          let
            username = "longred";
            hostName = "metacube-wsl";
            specialArgs = {
              inherit username hostName;
              channels = { inherit nixpkgs nixpkgs-unstable; };
              inherit inputs;
            };
          in
          nixpkgs.lib.nixosSystem {
            inherit specialArgs;
            system = "x86_64-linux";
            modules = [
              ./modules/overlays.nix
              ./modules/common.nix
              ./hosts/${hostName}
              ./users/${username}.nix
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;

                home-manager.extraSpecialArgs = inputs // specialArgs;
                home-manager.users.${username} = import ./home/wsl.nix;
              }
              nixos-wsl.nixosModules.wsl
              {
                # Enable WSL2
                wsl.enable = true;
                # Set the default user for WSL
                wsl.defaultUser = username;
              }
              agenix.nixosModules.default
              nix-index-database.nixosModules.nix-index
            ];
          };
        thinkbook-wsl =
          let
            username = "longred";
            hostName = "thinkbook-wsl";
            specialArgs = {
              inherit username hostName;
              channels = { inherit nixpkgs nixpkgs-unstable; };
              inherit inputs;
            };
          in
          nixpkgs.lib.nixosSystem {
            inherit specialArgs;
            system = "x86_64-linux";
            modules = [
              ./modules/overlays.nix
              ./modules/common.nix
              ./hosts/${hostName}
              ./users/${username}.nix
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;

                home-manager.extraSpecialArgs = inputs // specialArgs;
                home-manager.users.${username} = import ./home/wsl.nix;
              }
              nixos-wsl.nixosModules.wsl
              {
                # Enable WSL2
                wsl.enable = true;
                # Set the default user for WSL
                wsl.defaultUser = username;
              }
              agenix.nixosModules.default
              nix-index-database.nixosModules.nix-index
            ];
          };
        nuc =
          let
            username = "longred";
            hostName = "nuc";
            specialArgs = {
              inherit username hostName;
              channels = { inherit nixpkgs nixpkgs-unstable; };
              inherit inputs;
            };
          in
          nixpkgs.lib.nixosSystem {
            inherit specialArgs;
            system = "x86_64-linux";
            modules = [
              ./modules/overlays.nix
              ./modules/common.nix
              ./hosts/${hostName}
              ./users/${username}.nix
              ./modules/services/deeplx.nix
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;

                home-manager.extraSpecialArgs = inputs // specialArgs;
                # home-manager.users.${username} = import ./home/home.nix;
              }
              agenix.nixosModules.default
              nix-index-database.nixosModules.nix-index
            ];
          };
      };
    };
}
