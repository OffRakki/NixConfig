{
  config,
  pkgs,
  ...
}: let
  inherit (pkgs) dconf gnused systemd hyprland;

  darkGtk = "catppuccin-mocha-lavender-standard+normal";
  lightGtk = "catppuccin-latte-lavender-standard+normal";
  darkIcon = "Gruvbox-Plus-Dark";
  lightIcon = "Gruvbox-Plus-Light";
  darkCursor = "catppuccin-mocha-peach-cursors";
  lightCursor = "catppuccin-latte-lavender-cursors";
  cursorSize = "24";

  xsettingsd = "${config.xdg.configHome}/xsettingsd/xsettingsd.conf";

  common = scheme: gtk: icon: cursor: preferDark: ''
    ${dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'${scheme}'"
    ${dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'${gtk}'"
    ${dconf}/bin/dconf write /org/gnome/desktop/interface/icon-theme "'${icon}'"
    ${dconf}/bin/dconf write /org/gnome/desktop/interface/cursor-theme "'${cursor}'"

    ${gnused}/bin/sed -i "s/Net\/ThemeName.*/Net\/ThemeName \"${gtk}\"/" "${xsettingsd}"
    ${gnused}/bin/sed -i "s/Net\/IconThemeName.*/Net\/IconThemeName \"${icon}\"/" "${xsettingsd}"
    ${gnused}/bin/sed -i "s/Gtk\/CursorThemeName.*/Gtk\/CursorThemeName \"${cursor}\"/" "${xsettingsd}"
    ${gnused}/bin/sed -i "s/Gtk\/PreferDarkTheme.*/Gtk\/PreferDarkTheme ${preferDark}/" "${xsettingsd}"
    ${systemd}/bin/systemctl --user restart xsettingsd

    ${systemd}/bin/systemctl --user set-environment GTK_THEME="${gtk}"
    ${systemd}/bin/systemctl --user set-environment HYPRCURSOR_THEME="${cursor}"

    ${hyprland}/bin/hyprctl setcursor "${cursor}" "${cursorSize}" 2>/dev/null || true
  '';
in {
  services.darkman = {
    enable = true;
    settings = {
      usegeoclue = true;
      lat = -22.72;
      lng = -47.64;
    };
    lightModeScripts = {
      light = common "prefer-light" lightGtk lightIcon lightCursor "0";
    };
    darkModeScripts = {
      dark = common "prefer-dark" darkGtk darkIcon darkCursor "1";
    };
  };
}
