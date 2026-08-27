{
  lib,
  pkgs,
  ...
}: let
  manualStopMarker = "/home/rakki/Games/.MineServer-manually-stopped";
in {
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;
    dataDir = "/home/rakki/Games";
    user = "rakki";
    group = "users";

    servers.MineServer = {
      enable = true;
      package = pkgs.minecraftServers.neoforge-1_21_1-21_1_235;
      jvmOpts = "-Xms8G -Xmx8G";
      extraStartPre = ''
        rm -f ${manualStopMarker}
      '';
      extraStopPost = ''
        systemState="$(${lib.getExe' pkgs.systemd "systemctl"} is-system-running 2>/dev/null || true)"
        case "$systemState" in
          running | degraded | maintenance)
            touch ${manualStopMarker}
            ;;
        esac
      '';
    };
  };

  systemd.services = {
    minecraft-server-MineServer = {
      wantedBy = lib.mkForce [];
      serviceConfig.ProtectHome = lib.mkForce false;
    };

    minecraft-server-MineServer-autostart = {
      description = "Start MineServer unless it was manually stopped";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if [[ ! -e ${manualStopMarker} ]]; then
          ${lib.getExe' pkgs.systemd "systemctl"} start minecraft-server-MineServer.service
        fi
      '';
    };
  };
}
