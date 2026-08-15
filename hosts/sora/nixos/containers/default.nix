{
  sops.secrets.gitToken.owner = "rakki";

  hardware.nvidia-container-toolkit.enable = true;

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    oci-containers.containers.bambuddy = {
      image = "ghcr.io/maziggy/bambuddy:latest";
      autoStart = true;
      pull = "missing";
      volumes = [
        "bambuddy_data:/app/data"
        "bambuddy_logs:/app/logs"
      ];
      environment = {
        TZ = "America/Sao_Paulo";
        PUID = "1000";
        PGID = "100";
        PORT = "8000";
      };
      extraOptions = [
        "--network=host"
        "--cap-add=NET_BIND_SERVICE"
      ];
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      322
      990
      3000
      3002
      6000
      8000
      8883
      2024
      2025
      2026
    ];
    allowedTCPPortRanges = [
      {
        from = 50000;
        to = 50100;
      }
    ];
  };
}
