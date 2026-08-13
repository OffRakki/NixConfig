{
  lib,
  pkgs,
  ...
}: {
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
      jvmOpts = "-Xms12G -Xmx12G";
    };
  };

  systemd.services.minecraft-server-MineServer.serviceConfig.ProtectHome = lib.mkForce false;
}
