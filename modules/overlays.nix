{ inputs, ... }:
let
  # Import nixpkgs-unstable with the same config (e.g., allowUnfree) as prev
  unstableOverlay = final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = prev.stdenv.hostPlatform.system;
      config = prev.config;
    };
  };
in
{
  nixpkgs.overlays = [
    unstableOverlay
    # Custom local packages
    (final: prev: {
      pixi = prev.callPackage ../pkgs/pixi { };
      anytype-cli = prev.callPackage ../pkgs/anytype-cli { };
      mamba-cpp = prev.callPackage ../pkgs/mamba-cpp { };
      micromamba = prev.micromamba.override { mamba-cpp = final.mamba-cpp; };
    })
  ];
}
