{pkgs, ...}: {
  home.packages = [pkgs.ds4u];

  systemd.user.services.ds4u = {
    Unit = {
      Description = "DS4U DualSense daemon";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.ds4u}/bin/ds4u --daemon";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
