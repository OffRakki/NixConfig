{pkgs}:
pkgs.writeShellApplication {
  name = "bar";
  runtimeInputs = [pkgs.coreutils pkgs.jq pkgs.quickshell];
  text = ''
    export QUICKSHELL_CONFIG_PATH=${./.}
    ${builtins.readFile ./launch}
  '';
}
