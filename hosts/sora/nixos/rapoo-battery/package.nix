{
  lib,
  rustPlatform,
  python3,
  makeWrapper,
  libnotify,
}:
rustPlatform.buildRustPackage {
  pname = "rapoo-battery";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./Cargo.toml ./Cargo.lock ./src ./tests];
  };
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [makeWrapper];
  nativeCheckInputs = [python3];
  doCheck = true;
  postInstall = ''
    python3 tests/smoke.py "$out/bin/rapoo-battery"
    python3 tests/notify.py "$out/bin/rapoo-battery"
  '';
  postFixup = ''
    wrapProgram "$out/bin/rapoo-battery" --prefix PATH : ${lib.makeBinPath [libnotify]}
  '';
  meta = {
    description = "Rapoo VT9 Pro HID battery reporter and low battery notifier";
    mainProgram = "rapoo-battery";
    platforms = lib.platforms.linux;
  };
}
