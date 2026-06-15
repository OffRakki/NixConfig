{ config, lib, pkgs, ... }:

{
  boot.kernelModules = [ "rndis_host" "cdc_ether" ];

  systemd.services.usb-tether-watchdog = {
    description = "USB Tether Failover — remove dead ethernet route when phone is tethered";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = with pkgs; writeShellScript "usb-tether-check" ''
        ETH=enp6s0
        TARGET="1.1.1.1"
        TIMEOUT="3"

        if ${iputils}/bin/ping -I "$ETH" -c 1 -W "$TIMEOUT" "$TARGET" >/dev/null 2>&1; then
          GW=$(${gnugrep}/bin/grep -oP 'new_routers=\K\S+' /var/lib/dhcpcd/"$ETH".lease 2>/dev/null || true)
          if [ -n "$GW" ]; then
            ${iproute2}/bin/ip route show default dev "$ETH" >/dev/null 2>&1 || \
              ${iproute2}/bin/ip route add default via "$GW" dev "$ETH" metric 1002
          fi
          exit 0
        fi

        for p in /sys/class/net/enp*u*/; do
          [ -d "$p" ] || continue
          n=$(basename "$p")
          ${iputils}/bin/ping -I "$n" -c 1 -W "$TIMEOUT" "$TARGET" >/dev/null 2>&1 || continue
          ${iproute2}/bin/ip route del default dev "$ETH" 2>/dev/null || true
          exit 0
        done
      '';
    };
  };

  systemd.timers.usb-tether-watchdog = {
    description = "Periodic USB Tether Failover Check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "15s";
      Unit = "usb-tether-watchdog.service";
    };
  };

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="enp*s*u*", \
      RUN+="${pkgs.systemd}/bin/systemctl start --no-block usb-tether-watchdog.service"
  '';
}
