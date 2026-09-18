# Official nodejs.org Linux binary for the DeepSeek Harness runtime.
#
# Why not nixpkgs' `nodejs_22`: from dsh 0.1.6-alpha.2 on, booting any profile
# goes through `node-addon-require-builtin`, whose shipped linux-x64-gnu native
# prebuild finds Node's internal ESM/CJS loader by pattern-matching the V8
# isolate layout. That heuristic recognizes the official nodejs.org build but
# not nixpkgs' source build (both 22 and 24 fail closed with
# `Unsupported/no-getter`), so the harness dies during host preparation before
# it can listen. The official tarball is the supported target of that addon.
{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

stdenvNoCC.mkDerivation rec {
  pname = "nodejs-official";
  version = "22.23.2";

  src = fetchurl {
    url = "https://nodejs.org/dist/v${version}/node-v${version}-linux-x64.tar.xz";
    hash = "sha256-1grP4AopMiVLsK0g4BsNdDl6CHVZXecZZUshT0sD8wc=";
  };

  # The tarball targets the system glibc and libstdc++; rewrite those to the
  # Nix store so the same derivation runs on NixOS as well as Fedora. Only
  # bin/node is ELF; npm/npx are scripts and are left alone.
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r . "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Official nodejs.org Linux x64 build, required by the dsh profile-resolution native addon";
    homepage = "https://nodejs.org";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "node";
  };
}
