{
  config,
  lib,
  pkgs,
  ...
}: {
  boot.kernelModules = ["rndis_host" "cdc_ether"];

  systemd.services.usb-tether-watchdog = {
    description = "USB Tether Failover — remove dead ethernet route when phone is tethered";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = with pkgs;
        writeShellScript "usb-tether-check" ''
          set -euo pipefail
          ETH=enp6s0
          TARGET="1.1.1.1"
          TIMEOUT="3"

          PROBE_METRIC=4294967295
          probe_route=false
          cleanup_probe() {
            if "$probe_route"; then
              ${iproute2}/bin/ip -4 route del default via "$GW" dev "$ETH" metric "$PROBE_METRIC"
              probe_route=false
            fi
          }
          trap cleanup_probe EXIT

          # Keep USB preferred while giving the interface-bound recovery probe a route.
          if [ -z "$(${iproute2}/bin/ip -4 route show default dev "$ETH")" ]; then
            GW=$(${dhcpcd}/bin/dhcpcd -4 -U "$ETH" | ${gnused}/bin/sed -n 's/^routers=\([^ ]*\).*$/\1/p' || true)
            if [ -n "$GW" ] && ${iproute2}/bin/ip -j -4 route show default \
              | ${jq}/bin/jq -e --argjson metric "$PROBE_METRIC" 'all(.[]; (.metric // 0) < $metric)' >/dev/null; then
              ${iproute2}/bin/ip -4 route add default via "$GW" dev "$ETH" metric "$PROBE_METRIC"
              probe_route=true
            fi
          fi

          if ${iputils}/bin/ping -I "$ETH" -c 1 -W "$TIMEOUT" "$TARGET" >/dev/null 2>&1; then
            if "$probe_route"; then
              cleanup_probe
              # Restore the lease's routing policy instead of hardcoding its metric.
              ${dhcpcd}/bin/dhcpcd -g "$ETH"
            fi
            exit 0
          fi
          cleanup_probe

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
    wantedBy = ["timers.target"];
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
