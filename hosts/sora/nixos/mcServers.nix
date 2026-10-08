{pkgs, ...}: let
  # FTB Evolution 2 1.0.2: Minecraft 26.1.2 / NeoForge 26.1.2.109.
  installer = pkgs.fetchurl {
    url = "https://api.feed-the-beast.com/v1/modpacks/public/modpack/135/100552/server/linux";
    hash = "sha256-eHK1OVIP0u8mEOeBUlalWLyLkUl8Tlc/ZeDafxMtjnM=";
    executable = true;
  };
  thaumaturge = pkgs.fetchurl {
    url = "https://edge.forgecdn.net/files/9095/192/thaumaturge-26.1.2-NeoForge-1.0.2.jar";
    hash = "sha256-dKfOSZW99Zoj0aX3ARXsqGjxVF/eCqIx5+KhwcCYnao=";
  };
  server = pkgs.writeShellScriptBin "ftb-evolution-2-server" ''
    exec ${pkgs.jdk25_headless}/bin/java "$@" \
      @libraries/net/neoforged/neoforge/26.1.2.109/unix_args.txt nogui
  '';
in {
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;

    servers.FTBEvolution2 = {
      enable = true;
      autoStart = false;
      package = server;
      extraStartPre = ''
        if [ "$(cat .ftb-version 2>/dev/null || true)" != "100552" ]; then
          export PATH="${pkgs.jdk25_headless}/bin:$PATH"
          ${installer} -pack 135 -version 100552 -auto -no-java -validate
          ln -sfn ${thaumaturge} mods/thaumaturge.jar
          echo 100552 > .ftb-version
        fi
      '';
      jvmOpts = "-Xms8G -Xmx8G";
      serverProperties.level-name = "world";
      symlinks."mods/thaumaturge.jar" = thaumaturge;
    };
  };

  systemd.services.minecraft-server-FTBEvolution2.serviceConfig.TimeoutStartSec = "30min";
}
