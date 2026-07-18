{nixConfigRoot, ...}: {
  imports = [./cli.nix];

  programs.home-manager.enable = true;

  home = {
    stateVersion = "25.05";
    sessionVariables.NH_FLAKE = nixConfigRoot;
    persistence."/persist".directories = [
      "Documents"
      "Downloads"
      "Pictures"
      "Videos"
      ".local/bin"
      ".local/share/nix"
    ];
  };

  systemd.user.startServices = "sd-switch";
}
