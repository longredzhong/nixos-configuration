{ lib, stdenv, rustPlatform, fetchFromGitHub, pkg-config, installShellFiles
, libgit2, openssl, buildPackages, versionCheckHook, nix-update-script }:

# Custom packaged pixi (pinned) – local override / addition
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "pixi";
  version = "0.53.0"; # Updated version

  src = fetchFromGitHub {
    owner = "prefix-dev";
    repo = "pixi";
    rev = "v${finalAttrs.version}"; # upstream tags are vX.Y.Z
    hash = "sha256-cWoepvnolVyUyDlYakxQLNkOOP9ZbBwe5EaWbYTz+Gs=";
  };

  cargoHash = "sha256-3Sd+EjpSYbexmnUAwLps/Hrj7anpyurbzZlVs2hZk4E=";

  nativeBuildInputs = [ pkg-config installShellFiles ];
  buildInputs = [ libgit2 openssl ];

  env = {
    LIBGIT2_NO_VENDOR = 1;
    OPENSSL_NO_VENDOR = 1;
  };

  doCheck = false; # upstream tests flaky currently

  postInstall =
    lib.optionalString (stdenv.hostPlatform.emulatorAvailable buildPackages)
    (let emulator = stdenv.hostPlatform.emulator buildPackages;
    in ''
      installShellCompletion --cmd pixi \
        --bash <(${emulator} $out/bin/pixi completion --shell bash) \
        --fish <(${emulator} $out/bin/pixi completion --shell fish) \
        --zsh <(${emulator} $out/bin/pixi completion --shell zsh)
    '');

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "Package management made easy";
    homepage = "https://pixi.sh/";
    changelog = "https://pixi.sh/latest/CHANGELOG";
    license = licenses.bsd3;
    maintainers = [ maintainers.edmundmiller maintainers.xiaoxiangmoe ];
    mainProgram = "pixi";
  };
})
