{pkgs, ...}: let
  rapooBattery = pkgs.callPackage ./rapoo-battery/package.nix {};
in {
  environment.systemPackages = [rapooBattery];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="hidraw", ENV{ID_VENDOR_ID}=="24ae", ENV{ID_MODEL_ID}=="185a", ENV{ID_USB_INTERFACE_NUM}=="01", GROUP="input", MODE="0660"
    ACTION=="add", SUBSYSTEM=="hidraw", ENV{ID_VENDOR_ID}=="24ae", ENV{ID_MODEL_ID}=="418a", ENV{ID_USB_INTERFACE_NUM}=="01", GROUP="input", MODE="0660"
  '';

  systemd = {
    services.rapoo-vt9pro-battery = {
      description = "Rapoo VT9 Pro battery reporter";
      wantedBy = ["multi-user.target"];
      after = ["systemd-udevd.service"];
      serviceConfig = {
        ExecStart = "${rapooBattery}/bin/rapoo-battery --daemon";
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = ["AF_UNIX"];
        RestrictSUIDSGID = true;
      };
    };

    user = {
      services.rapoo-vt9pro-battery-watcher = {
        description = "Rapoo VT9 Pro low battery notifier";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${rapooBattery}/bin/rapoo-battery --notify";
        };
      };

      timers.rapoo-vt9pro-battery-watcher = {
        description = "Check the Rapoo VT9 Pro battery level";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "1m";
          OnUnitActiveSec = "1m";
          Unit = "rapoo-vt9pro-battery-watcher.service";
        };
      };
    };
  };
}
