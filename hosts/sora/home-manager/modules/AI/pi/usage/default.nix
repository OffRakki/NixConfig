{pkgs, nodejs, piPackage}: let
  collector = pkgs.writeShellScript "openai-usage" ''
    exec ${nodejs}/bin/node ${./collect.mjs} ${piPackage}/lib/node_modules/pi-monorepo
  '';
in {
  systemd.user.services.openai-usage = {
    Unit.Description = "Refresh OpenAI subscription usage for Noctalia";
    Service = {
      Type = "oneshot";
      ExecStart = collector;
      TimeoutStartSec = 120;
      UMask = "0077";
    };
  };
  systemd.user.timers.openai-usage = {
    Unit.Description = "Poll OpenAI subscription usage independently of Pi";
    Timer = {
      OnStartupSec = "15s";
      OnUnitActiveSec = "5min";
    };
    Install.WantedBy = ["timers.target"];
  };
}
