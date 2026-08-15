{
  imports = [./n8n.nix];

  networking = {
    firewall.trustedInterfaces = ["podman0"];
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    oci-containers.backend = "podman";
  };
}
