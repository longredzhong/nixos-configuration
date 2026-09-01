{
  lib,
  stdenv,
}:

# anytype-cli: headless Anytype server (embeds anytype-heart)
# Upstream ships prebuilt binaries; installed via install.sh which just copies
# the tarball's single `anytype` binary.
stdenv.mkDerivation (finalAttrs: {
  pname = "anytype-cli";
  version = "0.3.6";

  src = builtins.fetchTarball {
    url = "https://github.com/anyproto/anytype-cli/releases/download/v${finalAttrs.version}/anytype-cli-v${finalAttrs.version}-linux-amd64.tar.gz";
    sha256 = "sha256-W+2Hb4uNYPsWG227fs2guPjiF3gHte/8GM1NpYKxuFU=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 ${finalAttrs.src}/anytype $out/bin/anytype
    runHook postInstall
  '';

  meta = {
    description = "Command-line interface and headless server for Anytype";
    homepage = "https://github.com/anyproto/anytype-cli";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
