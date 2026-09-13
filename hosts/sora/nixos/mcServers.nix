{pkgs, ...}: let
  cobblemon = pkgs.fetchModrinthModpack {
    pname = "cobblemon-fabric";
    version = "1.8.1";
    url = "https://cdn.modrinth.com/data/5FFgwNNP/versions/Cqimd3JM/Cobblemon%20Modpack%20%5BFabric%5D%201.8.1.mrpack";
    packHash = "sha256-bMAnApelCEeihNfvRTYUHzDPvEY8uLibCfN0j6AW5WY=";
    side = "server";
  };
in {
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;

    servers.Cobblemon = {
      enable = true;
      autoStart = false;
      package = pkgs.fabricServers.fabric-1_21_1.override {
        loaderVersion = "0.19.5";
      };
      jvmOpts = "-Xms8G -Xmx8G";
      serverProperties.level-name = "world";
      symlinks.mods = "${cobblemon}/mods";
      files.config = "${cobblemon}/config";
    };
  };
}
