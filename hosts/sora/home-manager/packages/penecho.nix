{pkgs}: let
  unwrapped = pkgs.buildNpmPackage {
    pname = "penecho";
    version = "0.7.0";

    src = pkgs.fetchFromGitHub {
      owner = "penecho";
      repo = "penecho";
      rev = "067222311e09a1fa3dc26581efb8dbea8fd2d491";
      hash = "sha256-yDSM8+mq/8/ZGXHaZ6Had+7hEBrCOyQvNbgVHGBdSFQ=";
    };
    npmDepsHash = "sha256-t9VoxA5caqz7zNzO1AZJhOPdOQ8/KPhTKl7QYQddEK0=";
    dontNpmBuild = true;

    nativeBuildInputs = [pkgs.makeWrapper];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/node_modules/penecho" "$out/bin"
      cp -r . "$out/lib/node_modules/penecho"
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/penecho-unwrapped" \
        --add-flags "$out/lib/node_modules/penecho/cli.js"
      runHook postInstall
    '';

    meta = {
      description = "Shared AI canvas for handwriting, equations, and diagrams";
      homepage = "https://github.com/penecho/penecho";
      license = pkgs.lib.licenses.agpl3Only;
      mainProgram = "penecho-unwrapped";
    };
  };
in
  pkgs.writeShellScriptBin "penecho" ''
    # Codex refuses helper binaries when PenEcho isolates CODEX_HOME below /tmp.
    export TMPDIR="''${XDG_CACHE_HOME:-$HOME/.cache}/penecho/tmp"
    mkdir -p "$TMPDIR"
    chmod 700 "$TMPDIR"
    exec ${unwrapped}/bin/penecho-unwrapped "$@"
  ''
