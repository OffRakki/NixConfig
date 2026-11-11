{pkgs, ...}: let
  rapooBattery = pkgs.callPackage ./rapoo-battery/package.nix {};

  batteryWatcher = pkgs.writeShellScript "rapoo-battery-watcher" ''
    for capacity in /sys/class/power_supply/hid-24ae:185a-battery-*/capacity; do
      [[ -r "$capacity" ]] || exit 0
      percentage=$(<"$capacity")
      break
    done

    stateDirectory="''${XDG_STATE_HOME:-$HOME/.local/state}/rapoo-battery-watcher"
    stateFile="$stateDirectory/last-threshold"
    ${pkgs.coreutils}/bin/mkdir -p "$stateDirectory"
    previous=101
    [[ -r "$stateFile" ]] && previous=$(<"$stateFile")

    if ((percentage > 10)); then
      printf '101\n' >"$stateFile"
      exit 0
    fi

    for threshold in 10 5 1; do
      if ((percentage <= threshold && previous > threshold)); then
        urgency=normal
        icon=battery-caution-symbolic
        if ((threshold <= 5)); then
          urgency=critical
          icon=battery-empty-symbolic
        fi
        if ${pkgs.libnotify}/bin/notify-send \
          --app-name="Rapoo Battery" \
          --urgency="$urgency" \
          --icon="$icon" \
          "Rapoo VT9 Pro battery low" \
          "$percentage% remaining (reached $threshold% warning)"; then
          previous=$threshold
          printf '%s\n' "$previous" >"$stateFile"
        fi
      fi
    done
  '';
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
          ExecStart = batteryWatcher;
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
