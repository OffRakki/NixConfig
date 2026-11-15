{config, ...}: let
  wallpaper = "${config.home.homeDirectory}/Pictures/Wallpapers/solidBackground.png";
in {
  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = true;
      splash = false;
      preload = "${wallpaper}";
      wallpaper = ", ${wallpaper}";
    };
  };
}
