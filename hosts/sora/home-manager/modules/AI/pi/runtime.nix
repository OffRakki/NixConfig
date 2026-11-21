{
  pkgs,
  inputs,
}: let
  # Keep Pi/REA and shared Node CLIs on one Node 24 without rebuilding unrelated consumers.
  nodejs = inputs.nixpkgs-node.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nodejs_24;
  piBasePackage = pkgs.pi-coding-agent.override {
    buildNpmPackage = pkgs.buildNpmPackage.override {inherit nodejs;};
  };
  piPackage = piBasePackage.overrideAttrs (finalAttrs: _: {
    version = "1.6.0";
    src = pkgs.fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${finalAttrs.version}/pi-${finalAttrs.version}-source.tar.gz";
      hash = "sha256-FFGeKI6E5xNimyILtq3mgY4y1P8j8gX9gKfMSd7cQT4=";
    };
    npmDeps = pkgs.fetchNpmDeps {
      name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
      inherit (finalAttrs) src;
      hash = "sha256-V7fRy44X50tqfFewWQ/k5UjvUt+AoMOZkTw/v0bib6o=";
    };
    modelData = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${finalAttrs.version}.tgz";
      hash = "sha256-1oMS7FdLyVnLf+4m2k9IdtBnrtm7vnbodjWeYNIpR0c=";
    };
    buildPhase = ''
      runHook preBuild
      npm run build:offline
      runHook postBuild
    '';
    postInstall = ''
      local nm="$out/lib/node_modules/pi-monorepo/node_modules"
      for ws in @earendil-works/chord:packages/chord \
                @earendil-works/pi-ai:packages/ai \
                @earendil-works/pi-agent-core:packages/agent \
                @earendil-works/pi-codemode:packages/codemode \
                @earendil-works/pi-durable:packages/durable \
                @earendil-works/pi-env:packages/env \
                @earendil-works/pi-mcp:packages/mcp \
                @earendil-works/pi-schema:packages/schema \
                @earendil-works/pi-telemetry:packages/telemetry \
                @earendil-works/pi-tui:packages/tui; do
        IFS=: read -r pkg src <<< "$ws"
        rm "$nm/$pkg"
        cp -r "$src" "$nm/$pkg"
      done
      # Unshipped workspaces include apps/p2 as well as packages/*.
      find "$nm" -xtype l -delete
    '';
  });
  piPackages = import ./packages {inherit piPackage pkgs nodejs;};
in {
  inherit nodejs piPackage piPackages;
}
