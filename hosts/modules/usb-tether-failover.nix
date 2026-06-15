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
        GW=$(${iproute2}/bin/ip route show default dev "$ETH" | ${gawk}/bin/awk '{print $3}')

        [ -z "$GW" ] && [ -f "/var/lib/dhcpcd/$ETH.lease" ] && \
          GW=$(${gnugrep}/bin/grep -oP 'new_routers=\K\S+' "/var/lib/dhcpcd/$ETH.lease")

        [ -n "$GW" ] || exit 0

        USB=""
        for p in /sys/class/net/enp*u*/; do
          [ -d "$p" ] || continue
          n=$(basename "$p")
          ${iproute2}/bin/ip route show default dev "$n" >/dev/null 2>&1 || continue
          USB="$n"; break
        done

        if ${iputils}/bin/ping -I "$ETH" -c 1 -W 2 "$GW" >/dev/null 2>&1; then
          ${iproute2}/bin/ip route show default dev "$ETH" >/dev/null 2>&1 || \
            ${iproute2}/bin/ip route add default via "$GW" dev "$ETH" metric 1002
        elif [ -n "$USB" ]; then
          ${iproute2}/bin/ip route del default dev "$ETH" 2>/dev/null || true
        fi
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
