{pkgs}: let
  tools = pkgs.callPackage ./package.nix {};
in
  pkgs.runCommand "app-launcher" {
    nativeBuildInputs = [pkgs.makeWrapper];
    meta.mainProgram = "app-launcher";
  } ''
    makeWrapper ${tools}/bin/app-launcher "$out/bin/app-launcher" \
      --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.quickshell]} \
      --set-default QUICKSHELL_CONFIG_PATH ${./.} \
      --set-default APP_LAUNCHER_PASSWORD_HELPER ${tools}/bin/app-launcher-passwords
  ''
