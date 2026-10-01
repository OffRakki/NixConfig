{
  pkgs,
  piPackage ? pkgs.pi-coding-agent,
}: let
  package = builtins.fromJSON (builtins.readFile ./package.json);
  activeNpmPackages = [
    "@apat183/pi-buddy"
    "@juanibiapina/pi-extension-settings"
    "@juanibiapina/pi-powerbar"
    "@juicesharp/rpiv-ask-user-question"
    "@wishx127/pi-tokyo-night"
    "pi-agent-browser-native"
    "pi-codex-image-gen"
    "pi-intercom"
    "pi-invisible-continue"
    "pi-subagents"
    "pi-web-access"
    "rinco-pi-sakura"
  ];
  npmClosure = pkgs.buildNpmPackage {
    pname = package.name;
    inherit (package) version;
    src = ./.;
    npmDepsHash = "sha256-QqKNswZCLJjMbnyByhHMgHws3akUIQ5pkCoPdQQrGv0=";
    npmFlags = ["--legacy-peer-deps"];
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
    installCheckPhase = ''
      runHook preInstallCheck
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      args=()
      export PI_CODING_AGENT_DIR="$HOME/.pi/agent" PI_TELEMETRY=0 PI_SKIP_VERSION_CHECK=1
      ${pkgs.lib.concatMapStringsSep "\n" (name: ''args+=("$out/node_modules/${name}")'') activeNpmPackages}
      ${pkgs.nodejs}/bin/node --input-type=module - "''${args[@]}" <<'JS'
      import { createAgentSession, DefaultResourceLoader, SessionManager, SettingsManager } from '${piPackage}/lib/node_modules/pi-monorepo/dist/index.js';
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
      runHook postInstallCheck
    '';
  };
  inventory = builtins.fromJSON (builtins.readFile ./inventory.json);
  inventoryNpmPackages = builtins.filter (entry: entry.source == "npm") inventory.packages;
  sort = builtins.sort builtins.lessThan;
in
  assert sort activeNpmPackages == sort (map (entry: entry.name) inventoryNpmPackages);
  assert builtins.all (
    entry:
      builtins.hasAttr entry.name package.dependencies
      && package.dependencies.${entry.name} == entry.version
  )
  inventoryNpmPackages; {
    inherit inventory npmClosure;
    paths = map (name: "${npmClosure}/node_modules/${name}") activeNpmPackages;
  }
