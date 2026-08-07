{pkgs}:
pkgs.writeShellScriptBin "linoffice" ''
  export LINOFFICE_WRAPPER="$0"
  exec nix shell --impure --expr '
    let
      pkgs = (builtins.getFlake "nixpkgs").legacyPackages.''${builtins.currentSystem};
      python = pkgs.python3.withPackages (ps: [ps.pyside6 ps.python-dotenv]);
    in
    pkgs.buildEnv {
      name = "linoffice-env";
      paths = with pkgs; [
        python
        bash
        coreutils
        curl
        findutils
        freerdp
        gawk
        glib
        gnugrep
        gnused
        gnutar
        gzip
        iproute2
        iptables
        jq
        kmod
        podman
        podman-compose
        procps
        util-linux
        xdg-utils
      ];
    }
  ' -c bash -c '
    set -euo pipefail
    dir="$HOME/.local/bin/linoffice"

    if [[ ! -f "$dir/gui/linoffice.py" ]]; then
      tmp=$(mktemp -d)
      trap "rm -rf \"$tmp\"" EXIT
      curl -fsSL https://github.com/eylenburg/linoffice/archive/refs/heads/main.tar.gz |
        tar -xz --strip-components=1 -C "$tmp"
      mkdir -p "$(dirname "$dir")"
      mv "$tmp" "$dir"
      trap - EXIT
    fi

    find "$dir" -type f -name "*.sh" -exec sed -i "1s|^#!/bin/bash$|#!/usr/bin/env bash|" {} +
    bash_path=$(command -v bash)
    sed -i "s|self.process.setProgram(\"/bin/bash\")|self.process.setProgram(\"$bash_path\")|" \
      "$dir/gui/installer/installer.py"
    sed -i "s|^LINOFFICE=.*|LINOFFICE=\"$LINOFFICE_WRAPPER\"|" "$dir/setup.sh"

    if (($#)); then
      exec bash "$dir/linoffice.sh" "$@"
    else
      exec python3 "$dir/gui/linoffice.py"
    fi
  ' bash "$@"
''
