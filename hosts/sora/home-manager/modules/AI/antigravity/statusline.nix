{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "agy-statusline";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./statusline;
    fileset = lib.fileset.unions [
      ./statusline/Cargo.toml
      ./statusline/Cargo.lock
      ./statusline/src
    ];
  };
  cargoLock.lockFile = ./statusline/Cargo.lock;
  doCheck = true;

  meta = {
    mainProgram = "agy-statusline";
    description = "Powerline statusline, buddy indicator, window title, and Sakura CyberDeck banner for Antigravity CLI";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
