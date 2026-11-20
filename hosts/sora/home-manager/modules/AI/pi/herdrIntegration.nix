{
  config,
  lib,
  pkgs,
  ...
}: let
  integration = pkgs.runCommand "herdr-pi-integration" {} ''
    export HOME="$TMPDIR"
    mkdir -p "$HOME/.pi/agent/extensions"
    ${lib.getExe config.programs.herdr.package} integration install pi
    cp -r "$HOME/.pi/agent/extensions" "$out"
  '';
in {
  home.file.".pi/agent/extensions".source = pkgs.symlinkJoin {
    name = "pi-extensions";
    paths = [
      ./extensions
      integration
    ];
  };
}
