{pkgs}:
pkgs.writeShellScriptBin "winetricks" ''
  # Resolve real ELF binaries from the wine wrapper's WINELOADER
  # so winetricks can detect the architecture (it reads ELF headers directly)
  wine_bin="$(command -v wine 2>/dev/null)" || wine_bin="wine"
  wineloader="$(sed -n "s/^export WINELOADER='\\(.*\\)'$/\1/p" "$wine_bin" 2>/dev/null)"
  if [ -n "$wineloader" ] && [ -x "$wineloader" ]; then
    export WINE_BIN="$wineloader"
    export WINESERVER_BIN="$(dirname "$wineloader")/wineserver"
  fi
  # Suppress harmless 64-bit prefix warnings (we know it's 64-bit)
  export W_NO_WIN64_WARNINGS=1
  exec ${pkgs.winetricks}/bin/winetricks "$@"
''
