{pkgs}:
pkgs.writeShellScriptBin "orca-slicer" ''
  exec ${pkgs.flatpak}/bin/flatpak run com.orcaslicer.OrcaSlicer "$@"
''
