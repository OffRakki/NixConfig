{config, ...}: {
  # QUIC only, on Sora's LAN interface; mDNS is already opened by Avahi.
  networking.firewall.interfaces.enp6s0.allowedUDPPorts = [7718];

  boot = {
    kernelModules = ["v4l2loopback"];
    extraModulePackages = [config.boot.kernelPackages.v4l2loopback];
    extraModprobeConfig = ''
      options v4l2loopback exclusive_caps=1 card_label="NectarLink Webcam"
    '';
  };
  users.users.rakki.extraGroups = ["video"];
}
