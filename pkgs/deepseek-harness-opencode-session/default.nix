{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "deepseek-harness-opencode-session";
  version = "0.2.0";

  dontUnpack = true;

  installPhase = ''
    plugin_dir="$out/lib/node_modules/@longred/deepseek-harness-opencode-session"
    mkdir -p "$plugin_dir"
    install -Dm644 ${./package.json} "$plugin_dir/package.json"
    install -Dm644 ${./index.js} "$plugin_dir/index.js"
    install -Dm644 ${./cordis.patch.yml} "$plugin_dir/cordis.patch.yml"
    install -Dm644 ${./test/index.test.mjs} "$plugin_dir/test/index.test.mjs"
  '';

  meta = {
    description = "DeepSeek Harness plugin for OpenCode Go session headers and live model routes";
    homepage = "https://github.com/deepseek-ai/deepseek-harness/discussions/5681";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
