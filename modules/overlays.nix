{ inputs, ... }:
let
  # Import nixpkgs-unstable with the same config (e.g., allowUnfree) as prev
  unstableOverlay = final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (prev) system;
      config = prev.config;
    };
  };

  # Pin qbittorrent from a specific nixpkgs rev via non-flake input; import to get pkgs
  qbittorrentLegacyOverlay = final: prev:
    let
      oldPkgs = import inputs.qbittorrent-legacy {
        system = prev.system;
        config = { allowUnfree = true; };
      };
    in { qbittorrent_4_1_9_1 = oldPkgs.qbittorrent; };
in { nixpkgs.overlays = [ unstableOverlay qbittorrentLegacyOverlay ]; }
