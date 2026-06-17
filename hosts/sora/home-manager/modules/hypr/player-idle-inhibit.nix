{ config, pkgs, lib, ... }:

let
  playerIdleInhibit = pkgs.writeShellScriptBin "player-idle-inhibit" ''
    # Initial state check on startup
    if ${lib.getExe pkgs.playerctl} status --all-players 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "Playing"; then
      noctalia-shell ipc call idleInhibitor enable
    fi

    # Watch for playback state changes
    ${lib.getExe pkgs.playerctl} --follow --all-players 2>/dev/null | while read -r _; do
      if ${lib.getExe pkgs.playerctl} status --all-players 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "Playing"; then
        noctalia-shell ipc call idleInhibitor enable
      else
        noctalia-shell ipc call idleInhibitor disable
      fi
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
