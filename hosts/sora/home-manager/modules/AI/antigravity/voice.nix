{
  lib,
  rustPlatform,
  makeWrapper,
  sherpa-onnx,
  whisper-cpp,
  pipewire,
  curl,
  gnutar,
  bzip2,
}:
rustPlatform.buildRustPackage {
  pname = "agy-voice";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./voice;
    fileset = lib.fileset.unions [
      ./voice/Cargo.toml
      ./voice/Cargo.lock
      ./voice/build.rs
      ./voice/src
    ];
  };
  cargoLock.lockFile = ./voice/Cargo.lock;
  doCheck = true;

  nativeBuildInputs = [makeWrapper];
  buildInputs = [sherpa-onnx];

  env.SHERPA_ONNX_LIB_DIR = "${sherpa-onnx}/lib";

  postFixup = ''
    wrapProgram $out/bin/agy-voice \
      --prefix PATH : ${lib.makeBinPath [whisper-cpp pipewire curl gnutar bzip2]}
  '';

  meta = {
    mainProgram = "agy-voice";
    description = "Local CPU-pinned Rust voice TUI for Antigravity CLI (Silero VAD + Whisper.cpp + Kokoro-82M over agy acp)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
