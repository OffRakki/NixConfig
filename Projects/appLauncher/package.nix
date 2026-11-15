{
  lib,
  rustPlatform,
  makeWrapper,
  python3,
  rbw,
  wl-clipboard,
  hyprland,
  ydotool,
  qutebrowser,
}:
rustPlatform.buildRustPackage {
  pname = "app-launcher-passwords";
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
    ${lib.getExe python3} tests/integration.py "$out/bin/app-launcher-passwords"
    ${lib.getExe python3} tests/lifecycle.py "$out/bin/app-launcher"
  '';
  postFixup = ''
    wrapProgram "$out/bin/app-launcher-passwords" \
      --prefix PATH : ${lib.makeBinPath [rbw wl-clipboard hyprland ydotool qutebrowser]}
  '';
  meta = {
    description = "Metadata-only password launcher bridge with guarded side effects";
    mainProgram = "app-launcher-passwords";
    platforms = lib.platforms.linux;
  };
}
