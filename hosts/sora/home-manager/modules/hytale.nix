{pkgs, ...}: {
  home.packages = [
    (pkgs.inputs.hytale.default.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.makeWrapper];
      buildCommand =
        old.buildCommand
        + ''
          wrapProgram "$out/bin/hytale-launcher" \
            --run 'export TMPDIR="$HOME/.local/share/Hytale/.tmp"; mkdir -p "$TMPDIR"' \
            --run ${pkgs.writeShellScript "hytale-launcher-install" ''
            set -eu
            launcher="$HOME/.local/share/hytale-launcher/hytale-launcher"
            if [ ! -f "$launcher" ]; then
              temp=$(mktemp -d)
              trap 'rm -rf "$temp"' EXIT
              ${pkgs.curl}/bin/curl -fL -o "$temp/launcher.zip" \
                https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.zip
              # unzip returns 1 for harmless extra bytes in Hytale's ZIP.
              ${pkgs.unzip}/bin/unzip -o "$temp/launcher.zip" -d "$temp" || { status=$?; [ "$status" -eq 1 ] || exit "$status"; }
              mkdir -p "$(dirname "$launcher")"
              install -m755 "$temp/hytale-launcher" "$launcher"
            fi
          ''}
        '';
    }))
  ];
}
