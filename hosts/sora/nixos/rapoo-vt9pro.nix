{pkgs, ...}: let
  script = pkgs.writeText "rapoo-vt9pro-battery.py" ''
    import argparse
    import glob
    import os
    import select
    import struct
    import time

    REQUEST = bytes((0xBA, 0xB0)) + bytes(30)


    def find_device():
        for sys_path in glob.glob("/sys/class/hidraw/hidraw*"):
            try:
                descriptor = open(f"{sys_path}/device/report_descriptor", "rb").read()
                uevent = open(f"{sys_path}/device/uevent").read()
            except OSError:
                continue
            if "000024AE:0000185A" in uevent and b"\x85\xba" in descriptor and b"\x85\xbb" in descriptor:
                return f"/dev/{os.path.basename(sys_path)}"
        raise RuntimeError("Rapoo VT9 Pro receiver not found")


    def query_battery(timeout=2):
        fd = os.open(find_device(), os.O_RDWR | os.O_NONBLOCK)
        try:
            while True:
                try:
                    os.read(fd, 64)
                except BlockingIOError:
                    break
            os.write(fd, REQUEST)
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                readable, _, _ = select.select([fd], [], [], deadline - time.monotonic())
                if not readable:
                    break
                report = os.read(fd, 64)
                if len(report) >= 3 and report[:2] == b"\xbb\xb0" and report[2] <= 100:
                    return report[2]
        finally:
            os.close(fd)
        raise RuntimeError("Rapoo VT9 Pro did not answer the battery query")


    def fixed_field(value, size):
        return value.encode()[:size].ljust(size, b"\0")


    def create_virtual_battery(fd):
        descriptor = bytes.fromhex(
            "05 0c 09 01 a1 01 05 06 09 20 15 00 25 64 75 08 95 01 81 02 c0"
        )
        event = (
            struct.pack("<I", 11)
            + fixed_field("Rapoo VT9 Pro", 128)
            + fixed_field("rapoo-vt9pro", 64)
            + fixed_field("24ae:185a", 64)
            + struct.pack("<HHIIII", len(descriptor), 3, 0x24AE, 0x185A, 0x100, 0)
            + descriptor
        )
        os.write(fd, event)


    def run_daemon():
        while True:
            try:
                percentage = query_battery()
                break
            except (OSError, RuntimeError):
                time.sleep(5)

        fd = os.open("/dev/uhid", os.O_RDWR | os.O_NONBLOCK)
        create_virtual_battery(fd)
        next_query = time.monotonic() + 1
        try:
            while True:
                now = time.monotonic()
                readable, _, _ = select.select([fd], [], [], max(0, next_query - now))
                if readable:
                    event = os.read(fd, 4380)
                    event_type = struct.unpack_from("<I", event)[0]
                    if event_type == 9:
                        request_id = struct.unpack_from("<I", event, 4)[0]
                        reply = struct.pack("<IIHHBB", 10, request_id, 0, 2, 0, percentage)
                        os.write(fd, reply)

                if time.monotonic() >= next_query:
                    try:
                        percentage = query_battery()
                        os.write(fd, struct.pack("<IH", 12, 1) + bytes((percentage,)))
                        next_query = time.monotonic() + 60
                    except (OSError, RuntimeError):
                        next_query = time.monotonic() + 5
        finally:
            os.write(fd, struct.pack("<I", 1))
            os.close(fd)


    parser = argparse.ArgumentParser(description="Read a Rapoo VT9 Pro battery level")
    parser.add_argument("--daemon", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.daemon:
        run_daemon()
    else:
        try:
            print(f"{query_battery()}%")
        except (OSError, RuntimeError) as error:
            parser.error(str(error))
  '';

  rapooBattery = pkgs.writeShellScriptBin "rapoo-battery" ''
    exec ${pkgs.python3}/bin/python3 ${script} "$@"
  '';

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
