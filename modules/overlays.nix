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
      deepseek-harness-opencode-session = prev.callPackage ../pkgs/deepseek-harness-opencode-session { };
      deepseek-harness-observability = prev.callPackage ../pkgs/deepseek-harness-observability { };
      dsh-acp-enhanced = prev.callPackage ../pkgs/dsh-acp-enhanced { };
      dsh-otel = prev.callPackage ../pkgs/dsh-otel { };
      nodejs-official = prev.callPackage ../pkgs/nodejs-official { };
      opentelemetry-collector-contrib = prev.callPackage ../pkgs/opentelemetry-collector-contrib { };
      opencode-plugin-otel = prev.callPackage ../pkgs/opencode-plugin-otel { };
    })
  ];
}
