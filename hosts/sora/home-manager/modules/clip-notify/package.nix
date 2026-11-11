{
  lib,
  rustPlatform,
  makeWrapper,
  python3,
  file,
  coreutils,
  libnotify,
  wl-clipboard,
}:
rustPlatform.buildRustPackage {
  pname = "clip-notify";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./Cargo.toml ./Cargo.lock ./src ./tests];
  };
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [makeWrapper];
  nativeCheckInputs = [python3];
  doCheck = true;

  # Test the actual installed binary before wrapping; helpers are stubbed so the
  # build cannot touch the live clipboard or send desktop notifications.
  postInstall = ''
    ${lib.getExe python3} tests/smoke.py "$out/bin/clip-notify"
  '';
  postFixup = ''
    wrapProgram "$out/bin/clip-notify" \
      --prefix PATH : ${lib.makeBinPath [file coreutils libnotify wl-clipboard]}
  '';

  meta = {
    description = "Bounded, privacy-aware clipboard copy notifications";
    mainProgram = "clip-notify";
    platforms = lib.platforms.linux;
  };
}
