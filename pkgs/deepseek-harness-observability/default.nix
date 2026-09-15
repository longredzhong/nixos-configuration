{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "deepseek-harness-observability";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    plugin_dir="$out/lib/node_modules/@longred/deepseek-harness-observability"
    mkdir -p "$plugin_dir"
    install -Dm644 ${./package.json} "$plugin_dir/package.json"
    install -Dm644 ${./index.js} "$plugin_dir/index.js"
    install -Dm644 ${./cordis.patch.yml} "$plugin_dir/cordis.patch.yml"
    install -Dm644 ${./test/index.test.mjs} "$plugin_dir/test/index.test.mjs"
  '';

  meta = {
    description = "DeepSeek Harness session telemetry backend that exports token, tool and error telemetry to OpenObserve";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
