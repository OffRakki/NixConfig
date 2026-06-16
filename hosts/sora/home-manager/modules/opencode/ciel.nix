{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib) getExe;
  script = "${config.home.homeDirectory}/sync/geral/Ciel/bin/heartbeat.sh";
in {
  systemd.user.services.ciel-heartbeat = {
    Unit = {
      Description = "Ciel's heartbeat — room maintenance and autonomous summoning";
    };
    Service = {
      Type = "oneshot";
      ExecStart = script;
      Environment = ["DISPLAY=:0" "WAYLAND_DISPLAY=wayland-1"];
    };
  };

  systemd.user.timers.ciel-heartbeat = {
    Unit.Description = "Ciel's periodic heartbeat";
    Timer = {
      OnCalendar = "*:0/2";
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
