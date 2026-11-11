{
  lib,
  rustPlatform,
  python3,
  makeWrapper,
  systemd,
  libnotify,
}:
rustPlatform.buildRustPackage {
  pname = "autoclicker";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./Cargo.toml ./Cargo.lock ./src ./tests];
  };
  cargoLock.lockFile = ./Cargo.lock;
  nativeCheckInputs = [python3];
  nativeBuildInputs = [makeWrapper];
  doCheck = true;
  postInstall = ''
    python3 tests/smoke.py "$out/bin/autoclicker"
  '';
  postFixup = ''
    wrapProgram "$out/bin/autoclicker" --prefix PATH : ${lib.makeBinPath [systemd libnotify]}
  '';
  meta = {
    description = "Systemd-controlled autoclicker using the ydotoold socket";
    mainProgram = "autoclicker";
    platforms = lib.platforms.linux;
  };
}
