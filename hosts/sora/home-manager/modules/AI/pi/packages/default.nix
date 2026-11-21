{
  pkgs,
  piPackage ? pkgs.pi-coding-agent,
  nodejs ? pkgs.nodejs,
}: let
  package = builtins.fromJSON (builtins.readFile ./package.json);
  activeNpmPackages = [
    "@apat183/pi-buddy"
    "@jamesjfoong/pi-ollama"
    "@juicesharp/rpiv-ask-user-question"
    "billion-context"
    "pi-agent-browser-native"
    "pi-codex-image-gen"
    "pi-context-view"
    "pi-intercom"
    "pi-multi-account"
    "pi-powerline"
    "pi-subagents"
    "pi-web-access"
    "rinco-pi-sakura"
  ];
  # Retained in the shared closure for CLI/MCP/skill consumption without loading as a Pi extension.
  sharedOnlyNpmPackages = [
    "rea-agents"
  ];
  allNpmPackages = activeNpmPackages ++ sharedOnlyNpmPackages;
  npmClosure = pkgs.buildNpmPackage {
    inherit nodejs;
    pname = package.name;
    inherit (package) version;
    src = ./.;
    npmDepsHash = "sha256-WeKRlwJ32uLnf/BbeWg4j+6Iq5cNFwEyIU1z6dwp5mI=";
    npmFlags = ["--legacy-peer-deps"];
    # Use shipped native prebuilds; never download/build optional engines during install.
    npmRebuildFlags = ["--ignore-scripts"];
    nativeBuildInputs = [pkgs.autoPatchelfHook];
    buildInputs = [pkgs.stdenv.cc.cc.lib];
    dontNpmBuild = true;
    installPhase = ''
      runHook preInstall
      ${pkgs.python3}/bin/python3 ${./patch-packages.py} node_modules
      mkdir -p "$out"
      cp -r node_modules "$out/"
      cp package.json package-lock.json "$out/"
      runHook postInstall
    '';
    doInstallCheck = true;
    nativeInstallCheckInputs = [pkgs.procps];
    installCheckPhase = ''
      runHook preInstallCheck
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      args=()
      export PI_CODING_AGENT_DIR="$HOME/.pi/agent" PI_TELEMETRY=0 PI_SKIP_VERSION_CHECK=1
      ${pkgs.lib.concatMapStringsSep "\n" (name: ''args+=("$out/node_modules/${name}")'') activeNpmPackages}
      ${nodejs}/bin/node --input-type=module - "''${args[@]}" <<'JS'
      import { createAgentSession, DefaultResourceLoader, SessionManager, SettingsManager } from '${piPackage}/lib/node_modules/pi-monorepo/dist/index.js';
      const { resolveHostPeerAliases } = await import(process.argv.slice(2).find(path => path.endsWith('/pi-subagents')) + '/src/runs/background/runner-aliases.js');
      const { missing } = resolveHostPeerAliases('${piPackage}/lib/node_modules/pi-monorepo');
      if (missing.length) throw new Error('Missing async child host aliases: ' + missing.join(', '));
      const cwd = process.env.HOME;
      process.chdir(cwd);
      const agentDir = process.env.PI_CODING_AGENT_DIR;
      const settingsManager = SettingsManager.inMemory({ packages: process.argv.slice(2), enableAnalytics: false, enableInstallTelemtry: false });
      const resourceLoader = new DefaultResourceLoader({ cwd, agentDir, settingsManager, noContextFiles: true });
      await resourceLoader.reload();
      const { errors, warnings = [] } = resourceLoader.getExtensions();
      if (errors.length || warnings.length) throw new Error(JSON.stringify({ errors, warnings }));
      const { session } = await createAgentSession({ cwd, agentDir, settingsManager, resourceLoader, sessionManager: SessionManager.inMemory(cwd) });
      const runtimeErrors = [];
      await session.bindExtensions({ onError: error => runtimeErrors.push(error) });
      session.dispose();
      if (runtimeErrors.length) throw new Error(JSON.stringify(runtimeErrors));
      process.exit(0);
      JS
      test -f "$out/node_modules/rea-agents/skills/reverse-engineer-anything/SKILL.md"
      ${nodejs}/bin/node ${../tests/failover.smoke.mjs} \
        ${piPackage}/lib/node_modules/pi-monorepo "$out"
      ${nodejs}/bin/node ${../tests/rea.smoke.mjs} "$out/node_modules/rea-agents/scripts/rea.mjs"
      ${nodejs}/bin/node ${../tests/bili-thought-signature.smoke.mjs} "$out/node_modules/billion-context"
      runHook postInstallCheck
    '';
  };
  inventory = builtins.fromJSON (builtins.readFile ./inventory.json);
  inventoryNpmPackages = builtins.filter (entry: entry.source == "npm") inventory.packages;
  sort = builtins.sort builtins.lessThan;
in
  assert sort allNpmPackages == sort (map (entry: entry.name) inventoryNpmPackages);
  assert builtins.all (
    entry:
      builtins.hasAttr entry.name package.dependencies
      && package.dependencies.${entry.name} == entry.version
  )
  inventoryNpmPackages; {
    inherit inventory npmClosure;
    paths = map (name: "${npmClosure}/node_modules/${name}") activeNpmPackages;
  }
