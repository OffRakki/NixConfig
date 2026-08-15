{
  pkgs,
  piPackage ? pkgs.pi-coding-agent,
}: let
  package = builtins.fromJSON (builtins.readFile ./package.json);
  activeNpmPackages = [
    "@dietrichgebert/ponytail"
    "@juicesharp/rpiv-args"
    "@juicesharp/rpiv-ask-user-question"
    "@juicesharp/rpiv-pi"
    "@juicesharp/rpiv-todo"
    "pi-agent-browser-native"
    "pi-intercom"
    "pi-invisible-continue"
    "pi-lean-ctx"
    "pi-lens"
    "pi-markdown-preview"
    "pi-namespace"
    "pi-powerline-footer"
    "pi-simplify"
    "pi-subagents"
    "pi-tally"
    "pi-web-access"
  ];
  npmClosure = pkgs.buildNpmPackage {
    pname = package.name;
    inherit (package) version;
    src = ./.;
    npmDepsHash = "sha256-jtGh4N+WY/p2FssU9cA2UZaa2fkrlzWQUhhWWnmrg10=";
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
  cavemanRev = "0d4c639d672b0b80afaa035f582152dcab9c6a8f";
  _caveman = pkgs.fetchFromGitHub {
    owner = "jonjonrankin";
    repo = "pi-caveman";
    rev = cavemanRev;
    hash = "sha256-DhawjQ6tZvG5go4ayPdB+Yup77MjsLF2hFmjxgu9yTQ=";
  };
  inventory = builtins.fromJSON (builtins.readFile ./inventory.json);
  inventoryNpmPackages = builtins.filter (entry: entry.source == "npm") inventory.packages;
  inventoryCaveman = builtins.filter (entry: entry.name == "pi-caveman") inventory.packages;
  sort = builtins.sort builtins.lessThan;
in
  assert sort activeNpmPackages == sort (map (entry: entry.name) inventoryNpmPackages);
  assert builtins.all (
    entry:
      builtins.hasAttr entry.name package.dependencies
      && package.dependencies.${entry.name} == entry.version
  )
  inventoryNpmPackages;
  assert builtins.length inventoryCaveman == 1;
  assert (builtins.head inventoryCaveman).source == "github:jonjonrankin/pi-caveman";
  assert (builtins.head inventoryCaveman).version == cavemanRev; {
    inherit inventory npmClosure;
    paths =
      map (name: "${npmClosure}/node_modules/${name}") activeNpmPackages
      # ++ [_caveman]
      ;
  }
