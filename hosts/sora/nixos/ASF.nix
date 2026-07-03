{...}: {
  services.archisteamfarm = {
    enable = true;
    web-ui.enable = true;
    bots = {
      ciel = {
        enabled = true;
      };
    };
  };
}
