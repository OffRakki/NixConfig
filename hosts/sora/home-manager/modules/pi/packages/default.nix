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
    # "pi-powerline-footer"
    "pi-subagents"
    "pi-web-access"
    "rinco-pi-sakura"
  ];
  npmClosure = pkgs.buildNpmPackage {
    pname = package.name;
    inherit (package) version;
    src = ./.;
    npmDepsHash = "sha256-hnxsYll+822IBTKEKh5uawzxyqPogkkRzU/YvOvXjyU=";
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
      ${pkgs.lib.concatMapStringsSep "\n" (name: ''args+=(--extension "$out/node_modules/${name}")'') activeNpmPackages}
      ${piPackage}/bin/pi --no-session "''${args[@]}" --list-models >/dev/null
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
