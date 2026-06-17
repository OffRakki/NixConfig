{ config, pkgs, lib, ... }:

let
  stateFile = "/tmp/player-idle-inhibit";
  playerIdleInhibit = pkgs.writeShellScriptBin "player-idle-inhibit" ''
    set -o pipefail

    update() {
      if ${lib.getExe pkgs.playerctl} status --all-players 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "Playing"; then
        noctalia-shell ipc call idleInhibitor enable && touch ${stateFile}
      else
        noctalia-shell ipc call idleInhibitor disable && rm -f ${stateFile}
      fi
    }

    while true; do
      update
      ${lib.getExe pkgs.playerctl} --follow --all-players 2>/dev/null | while read -r _; do
        update
      done
      sleep 2
    done
  '';
in {
  systemd.user.services.player-idle-inhibit = {
    Unit = {
      Description = "Inhibit idle during media playback";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${lib.getExe playerIdleInhibit}";
      Restart = "on-failure";
    };
    Install.WantedBy = [ config.wayland.systemd.target ];
  };
}
