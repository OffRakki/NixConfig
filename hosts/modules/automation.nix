{nixConfigRoot, ...}: {
  # Automatic update
  system.autoUpgrade = {
    enable = true;
    flake = nixConfigRoot;
    dates = "weekly";
  };

  # Automatic cleanup (nh keeps the newest generations, unlike a plain age-based gc)
  nix = {
    settings.auto-optimise-store = false;
    optimise = {
      automatic = true;
      dates = ["Sun 04:00"];
      # Keep optimisation off-hours rather than catching up at boot.
      persistent = false;
    };
  };
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "daily";
      extraArgs = "--keep 5 --keep-since 7d";
    };
  };
}
