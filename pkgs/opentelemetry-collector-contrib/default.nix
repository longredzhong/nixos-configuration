{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "opentelemetry-collector-contrib";
  version = "0.156.0";

  # OpenObserve's Linux integration currently installs this upstream release.
  # Keep the binary pinned instead of depending on the differently packaged
  # nixpkgs collector.
  src = fetchurl {
    url = "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${finalAttrs.version}/otelcol-contrib_${finalAttrs.version}_linux_amd64.tar.gz";
    hash = "sha256-7nDXsSIb6KnMRwD0i/mFwEsauKru8kQJ/nliOEni+fI=";
  };

  dontConfigure = true;
  dontBuild = true;
  dontUnpack = true;
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    tar -xzf "$src"
    install -Dm755 otelcol-contrib $out/bin/otelcol-contrib
  '';

  meta = {
    description = "OpenTelemetry Collector distribution with contrib components";
    homepage = "https://opentelemetry.io/docs/collector/";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "otelcol-contrib";
    platforms = [ "x86_64-linux" ];
  };
})
