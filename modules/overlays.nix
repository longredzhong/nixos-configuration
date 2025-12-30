{ inputs, ... }:
let
  # Import nixpkgs-unstable with the same config (e.g., allowUnfree) as prev
  unstableOverlay = final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = prev.stdenv.hostPlatform.system;
      config = prev.config;
    };
  };

  # Pin qbittorrent from a specific nixpkgs rev via non-flake input; import to get pkgs
  qbittorrentLegacyOverlay =
    final: prev:
    let
      oldPkgs = import inputs.qbittorrent-legacy {
        system = prev.stdenv.hostPlatform.system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      qbittorrent_4_1_9_1 = oldPkgs.qbittorrent;
    };
in
{
  nixpkgs.overlays = [
    unstableOverlay
    qbittorrentLegacyOverlay
  ];
}
// {
  nixpkgs.overlays = [
    unstableOverlay
    qbittorrentLegacyOverlay
    # Custom local packages
    (final: prev: {
      pixi = prev.callPackage ../pkgs/pixi { };
      mamba-cpp = prev.callPackage ../pkgs/mamba-cpp { };
    })
  ];
}
