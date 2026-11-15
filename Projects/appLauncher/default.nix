{pkgs}:
pkgs.writeShellApplication {
  name = "app-launcher";
  runtimeInputs = [pkgs.coreutils pkgs.jq pkgs.quickshell pkgs.util-linux];
  text = ''
    export QUICKSHELL_CONFIG_PATH=${./.}
    export APP_LAUNCHER_PASSWORD_HELPER=${pkgs.callPackage ./package.nix {}}/bin/app-launcher-passwords
    ${builtins.readFile ./launch}
  '';
}
