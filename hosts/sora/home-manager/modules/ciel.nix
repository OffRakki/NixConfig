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
      Description = "Ciel's heartbeat — room maintenance and pulse";
    };
    Service = {
      Type = "oneshot";
      ExecStart = script;
      Environment = ["DISPLAY=:0" "WAYLAND_DISPLAY=wayland-1"];
    };
  };

  systemd.user.timers.ciel-heartbeat = {
    Unit.Description = "Ciel's hourly heartbeat";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
