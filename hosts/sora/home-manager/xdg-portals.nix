{pkgs, ...}: {
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      # pkgs.xdg-desktop-portal-hyprland
    ];
    config = {
      hyprland.default = [
        "gtk"
        "hyprland"
      ];
      hyprland."org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
      common = {
        default = ["gtk"];
        "org.freedesktop.impl.portal.FileChooser" = ["gtk"];
      };
    };
  };
}
