{
  lib,
  buildNpmPackage,
  fetchurl,
  esbuild,
  python3,
}:

buildNpmPackage rec {
  pname = "dsh-otel";
  version = "0.0.2";

  # GitHub's /archive endpoint is unreachable from the build sandbox on this
  # host, but codeload is. The tarball unpacks to one top-level directory, so
  # stdenv's unpackPhase sets sourceRoot on its own.
  src = fetchurl {
    url = "https://codeload.github.com/krimvp/dsh-otel/tar.gz/c0dd20d90c99acb8019e071f3f9ce06e0626d54a";
    hash = "sha256-8TmJSjKwIYYGZv41AHHk2IOwX9o1GMckSiUi6xvk8mk=";
    name = "dsh-otel-0.0.2.tar.gz";
  };

  npmDepsHash = "sha256-NSsrCFT91W9BE9V2pjk6SkcV4O5QvNAKI+e1qAkIziM=";
  npmBuildScript = "build";

  # Upstream ships unbundled tsc output whose runtime imports are the
  # @opentelemetry/* packages. The harness loads profile plugins from the Nix
  # store, where Node cannot see the harness install's node_modules, so bundle
  # the entrypoint and its runtime dependencies into one self-contained ESM
  # file. @deepseek-ai/cordis is a type-only import and drops out.
  postBuild = ''
    ${esbuild}/bin/esbuild dist/index.js \
      --bundle \
      --format=esm \
      --platform=node \
      --target=node20 \
      --banner:js='import { createRequire } from "node:module"; const require = createRequire(import.meta.url);' \
      --outfile=dist/index.bundle.js
  '';

  installPhase = ''
    runHook preInstall
    plugin_dir="$out/lib/node_modules/dsh-otel"
    install -d "$plugin_dir/dist"
    install -m 0644 dist/index.bundle.js "$plugin_dir/dist/index.js"
    install -m 0644 ${./cordis.patch.yml} "$plugin_dir/cordis.patch.yml"
    install -m 0644 package.json "$plugin_dir/package.json"
    ${python3}/bin/python3 - "$plugin_dir/package.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
# The bundle inlines every runtime dependency and @deepseek-ai/cordis is a
# type-only import, so nothing must resolve from a node_modules tree. Mark the
# package as a profile bundle and point it at the composed patch.
for key in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
    manifest.pop(key, None)
manifest["main"] = "./dist/index.js"
manifest["exports"] = {".": {"import": "./dist/index.js"}}
manifest["files"] = ["dist", "cordis.patch.yml"]
manifest["dsh"] = {"bundle": {"patch": "./cordis.patch.yml"}}
path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY
    runHook postInstall
  '';

  meta = {
    description = "OpenTelemetry traces and metrics plugin for DeepSeek Harness";
    homepage = "https://github.com/krimvp/dsh-otel";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
