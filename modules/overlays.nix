{ inputs, ... }:
let
  # 创建一个支持多架构的 overlay
  unstableOverlay = system: final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit system;
      config = prev.config;
    };
  };
in
{
  nixpkgs.overlays = [
    (final: prev: unstableOverlay prev.system final prev)
  ];
}
