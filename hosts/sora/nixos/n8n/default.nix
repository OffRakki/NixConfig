{
  lib,
  buildNpmPackage,
  cmake,
  curl,
  cyrus_sasl,
  nodejs,
  openssl,
  makeWrapper,
  pkg-config,
  python3,
  sqlite,
  stdenv,
  which,
  zlib,
  zstd,
}: buildNpmPackage {
  pname = "n8n";
  version = "2.45.7";
  src = ./.;
  npmDepsHash = "sha256-8Wo4baCOWA6GPaHScFcHC9PgSFw8YDHGKY0yeJ2trDU=";
  npmFlags = ["--legacy-peer-deps"];
  npmInstallFlags = ["--omit=dev"];
  npmRebuildFlags = ["--ignore-scripts"];
  dontNpmBuild = true;
  postConfigure = ''
    # The Kafka addon otherwise downloads libraries and launches unbounded make jobs.
    substituteInPlace node_modules/@confluentinc/kafka-javascript/deps/librdkafka.gyp \
      --replace-fail '"make", "-j",' '"make", "-j2",'
    (cd node_modules/@confluentinc/kafka-javascript && node util/configure)
    npm rebuild --offline --legacy-peer-deps
  '';

  nativeBuildInputs = [cmake makeWrapper pkg-config which];
  dontUseCmakeConfigure = true;
  buildInputs = [curl cyrus_sasl openssl sqlite stdenv.cc.cc.lib zlib zstd];
  env = {
    CKJS_LINKING = "dynamic";
    npm_config_build_from_source = "true";
    npm_config_sqlite = "${lib.getDev sqlite}";
    npm_config_jobs = "2";
    npm_config_python = "${python3.withPackages (ps: [ps.setuptools])}/bin/python3";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/n8n" "$out/bin"
    cp -r node_modules "$out/lib/n8n/"
    makeWrapper ${lib.getExe nodejs} "$out/bin/n8n" \
      --add-flags "$out/lib/n8n/node_modules/n8n/bin/n8n" \
      --set N8N_RELEASE_TYPE stable \
      --prefix PATH : ${lib.makeBinPath [nodejs]}
    makeWrapper ${lib.getExe nodejs} "$out/bin/n8n-task-runner" \
      --add-flags "$out/lib/n8n/node_modules/@n8n/task-runner/dist/start.js"
    runHook postInstall
  '';

  meta = {
    inherit (nodejs.meta) platforms;
    description = "Workflow automation, pinned to the official upstream npm release";
    homepage = "https://n8n.io";
    license = lib.licenses.sustainableUse;
    mainProgram = "n8n";
  };
}
