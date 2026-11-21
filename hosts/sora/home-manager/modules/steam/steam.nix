{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.steam-config-nix.homeModules.default];

  programs.steam.config.enable = true;

  home = {
    persistence."/persist".directories = [
      ".steam"
      ".config/millennium"
      ".local/share/millennium"
      ".local/share/Steam"
      ".local/share/steam-config-nix"
    ];

    packages = [
      pkgs.protontricks
    ];
  };
}
