{
  lib,
  rustPlatform,
  python3,
}:
rustPlatform.buildRustPackage {
  pname = "llm-suggest-lsp";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./llm-suggest-lsp;
    fileset = lib.fileset.unions [
      ./llm-suggest-lsp/Cargo.toml
      ./llm-suggest-lsp/Cargo.lock
      ./llm-suggest-lsp/src
      ./llm-suggest-lsp/tests
    ];
  };
  cargoLock.lockFile = ./llm-suggest-lsp/Cargo.lock;
  doCheck = true;
  nativeCheckInputs = [python3];
  postInstall = ''
    runHook prePostInstall
    python3 tests/smoke.py "$out/bin/llm-suggest-lsp"
    runHook postPostInstall
  '';

  meta = {
    mainProgram = "llm-suggest-lsp";
    description = "LSP server for LLM suggested edits (diagnostics + code actions)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
