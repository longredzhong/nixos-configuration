{
  lib,
  fetchurl,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "opencode-plugin-otel";
  version = "1.5.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@devtheops/opencode-plugin-otel/-/opencode-plugin-otel-1.5.1.tgz";
    hash = "sha256-bjkYmD+kdjbo1uAxD+oL1XrdZ+qdKuP8JXidckYkW2E=";
  };

  dontUnpack = true;

  installPhase = ''
    plugin_dir="$out/lib/node_modules/@devtheops/opencode-plugin-otel"
    mkdir -p "$plugin_dir"
    tar --extract --gzip --file "$src" --strip-components=1 --directory "$plugin_dir"
  '';

  meta = {
    description = "OpenTelemetry telemetry plugin for OpenCode";
    homepage = "https://github.com/DEVtheOPS/opencode-plugin-otel";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
