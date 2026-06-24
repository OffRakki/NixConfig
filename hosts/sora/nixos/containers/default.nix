{
  imports = [
    # Glance moved to home-manager/modules/glance.nix.
    # ./containers.nix
  ];

  sops.secrets = {
    piholePass.owner = "rakki";
    gitToken.owner = "rakki";
  };

  systemd.tmpfiles.rules = [
    # Old podman+sops Glance template created this as root.
    "d /home/rakki/.config/glance 0755 rakki users - -"
  ];

  hardware.nvidia-container-toolkit.enable = true;

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Glance moved to home-manager/modules/glance.nix.
  # systemd.services.podman-glance = {
  #   serviceConfig = {
  #     restart = "on-failure";
  #     RestartSec = 5;
  #   };
  # };
}
