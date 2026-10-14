{
  imports = [./bambuddy.nix];

  sops.secrets.gitToken.owner = "rakki";

  hardware.nvidia-container-toolkit.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };
}
