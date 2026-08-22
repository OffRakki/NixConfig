{pkgs, ...}: {
  home.persistence."/persist".directories = [
    ".steam"
    ".config/millennium"
    ".local/share/millennium"
    ".local/share/Steam"
  ];

  home.packages = [
    pkgs.protontricks
  ];
}
