{
  pkgs,
  nodejs,
  agyPackage,
}: let
  collector = pkgs.writeShellScript "antigravity-usage" ''
    exec ${nodejs}/bin/node ${./collect.mjs} ${agyPackage}/bin/agy
  '';
in {
  systemd.user.services.antigravity-usage = {
    Unit.Description = "Refresh Google Antigravity quota usage for Noctalia";
    Service = {
      Type = "oneshot";
      ExecStart = collector;
      TimeoutStartSec = 120;
      UMask = "0077";
    };
  };
  systemd.user.timers.antigravity-usage = {
    Unit.Description = "Poll Google Antigravity quota usage independently of CLI sessions";
    Timer = {
      OnStartupSec = "20s";
      OnUnitActiveSec = "5min";
    };
    Install.WantedBy = ["timers.target"];
  };
}
