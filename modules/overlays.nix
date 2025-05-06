{ inputs, ... }:
let
  # 创建一个支持多架构的 overlay
  unstableOverlay = system: final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit system;
      config = prev.config;
    };
  };
  
  # 添加特定版本的 qBittorrent overlay
  qbittorrentLegacyOverlay = system: final: prev: {
    qbittorrent_4_1_9_1 = let
      oldNixpkgs = import (builtins.fetchGit {
        name = "nixpkgs-qbittorrent-4.1.9.1";
        url = "https://github.com/NixOS/nixpkgs/";
        ref = "refs/heads/nixpkgs-unstable";
        rev = "ee355d50a38e489e722fcbc7a7e6e45f7c74ce95";
      }) {
        inherit system;
        config = { allowUnfree = true; };
      };
    in oldNixpkgs.qbittorrent;
  };
in {
  nixpkgs.overlays = [
    (final: prev: unstableOverlay prev.system final prev)
    (final: prev: qbittorrentLegacyOverlay prev.system final prev)
  ];
}
