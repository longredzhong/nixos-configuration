# dsh-acp-enhanced as a DeepSeek Harness profile bundle.
#
# This bundle is the interactive ACP transport: unlike the automation-only
# shipped bridge it advertises the permission-preset, agent-preset and plan
# selectors that an editor can render, plus session/load and image prompts.
#
# Why this one is not a bare store symlink like the other bundles in this
# repository (see pkgs/deepseek-harness-opencode-session): it imports real
# runtime dependencies. The profile loader installs import routes only for
# importers that live inside the profile directory, and a symlinked plugin
# resolves its imports from its real Nix store path instead, so it fails with
# `Cannot find package '@deepseek-ai/schemastery'`. This package therefore ships
# a self-contained tree with the external dependencies nested in its own
# node_modules, and the provisioning script copies it into the profile.
#
# The `@deepseek-ai/dsh-*` and cordis packages the bundle declares as peers are
# deliberately not vendored: the profile loader's installation fallback serves
# them, which again only works for an importer inside the profile directory.
{
  lib,
  stdenvNoCC,
  fetchurl,
  gnutar,
  gzip,
}:

let
  version = "0.7.0";

  mkTarball =
    {
      name,
      url,
      hash,
    }:
    fetchurl {
      inherit url hash;
      name = "${name}.tgz";
    };

  plugin = mkTarball {
    name = "dsh-acp-enhanced-${version}";
    url = "https://registry.npmjs.org/dsh-acp-enhanced/-/dsh-acp-enhanced-${version}.tgz";
    hash = "sha256-XAITZzgqGHJBmGWsmaUhHWLfn0FTPqigpPQw06BslI4=";
  };

  # Pinned to what npm resolves from the ranges in the bundle's package.json
  # (sdk 1.3.0, schemastery ^3.18.1, zod ^4.4.3); @standard-schema/spec is zod's
  # own dependency. These are plain JS, so nothing is built here.
  deps = [
    {
      path = "@agentclientprotocol/sdk";
      tarball = mkTarball {
        name = "agentclientprotocol-sdk-1.3.0";
        url = "https://registry.npmjs.org/@agentclientprotocol/sdk/-/sdk-1.3.0.tgz";
        hash = "sha256-C69ba+GELQC/mJwCEbfkShX4h2nS//1QNjl7okm+zJ8=";
      };
    }
    {
      path = "@deepseek-ai/schemastery";
      tarball = mkTarball {
        name = "deepseek-ai-schemastery-3.18.2";
        url = "https://registry.npmjs.org/@deepseek-ai/schemastery/-/schemastery-3.18.2.tgz";
        hash = "sha256-oP5wC5wFXwTf7IfLRq5KEQbG+sbCcfih3wDhADjwqsE=";
      };
    }
    {
      path = "zod";
      tarball = mkTarball {
        name = "zod-4.6.5";
        url = "https://registry.npmjs.org/zod/-/zod-4.6.5.tgz";
        hash = "sha256-p4wMUz3jDcHEr8JZrEOsBuOQyw2o0uMurjVTAbULNvw=";
      };
    }
    {
      path = "@standard-schema/spec";
      tarball = mkTarball {
        name = "standard-schema-spec-1.1.0";
        url = "https://registry.npmjs.org/@standard-schema/spec/-/spec-1.1.0.tgz";
        hash = "sha256-p8tyaL4oCrUY1FD4w7B8hvI0FyJcCrU2ke1ZswZ8zq8=";
      };
    }
  ];
in
stdenvNoCC.mkDerivation {
  pname = "dsh-acp-enhanced";
  inherit version;

  dontUnpack = true;

  nativeBuildInputs = [
    gnutar
    gzip
  ];

  installPhase = ''
    runHook preInstall

    root="$out/lib/node_modules/dsh-acp-enhanced"
    scratch="$TMPDIR/unpack"
    mkdir -p "$root/node_modules"

    # npm tarballs wrap their contents in a `package/` directory.
    unpack_tgz() {
      rm -rf "$scratch"
      mkdir -p "$scratch" "$2"
      tar -xzf "$1" -C "$scratch"
      cp -r "$scratch/package/." "$2/"
    }

    unpack_tgz ${plugin} "$root"
    ${lib.concatMapStrings (dep: ''
      unpack_tgz ${dep.tarball} "$root/node_modules/${dep.path}"
    '') deps}

    rm -rf "$scratch"

    test -f "$root/package.json"
    test -f "$root/lib/index.js"
    test -f "$root/cordis.patch.yml"
    ${lib.concatMapStrings (dep: ''
      test -f "$root/node_modules/${dep.path}/package.json"
    '') deps}

    runHook postInstall
  '';

  meta = {
    description = "Interactive ACP transport bundle for DeepSeek Harness (Zed agent panel)";
    homepage = "https://github.com/grunmin/dsh-acp-enhanced";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
