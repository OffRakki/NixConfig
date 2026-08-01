{pkgs, ...}: {
  home.persistence."/persist".directories = [
    ".steam"
    ".local/share/Steam"
  ];

  home.packages = [
    pkgs.protontricks
  ];
}
