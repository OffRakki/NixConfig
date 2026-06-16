{lib, ...}: {
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };
  networking.firewall.allowedUDPPorts = [41641]; # Facilitate firewall punching
}
