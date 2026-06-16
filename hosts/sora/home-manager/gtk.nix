{
  config,
  lib,
  pkgs,
  ...
}: {
  home.sessionVariables = {
    ADW_DEBUG_COLOR_SCHEME = "default";
    GTK_THEME = "catppuccin-mocha-lavender-standard+normal";
  };

  gtk = {
    enable = true;
    colorScheme = null;
    theme = {
      name = "catppuccin-mocha-lavender-standard+normal";
      package = pkgs.catppuccin-gtk.override {
        accents = ["lavender"];
        size = "standard";
        tweaks = ["normal"];
        variant = "mocha";
      };
    };
    iconTheme = {
      name = "Gruvbox-Plus-Dark";
      package = pkgs.gruvbox-plus-icons;
    };
    font = {
      name = "JetBrainsMono Nerd Font Mono";
      size = 12;
    };
    gtk3 = {
      enable = true;
      extraConfig.settings = "";
    };
    gtk4 = {
      enable = true;
      extraConfig.settings = "";
      theme = null;
    };
  };

  home.packages = [
    (pkgs.catppuccin-gtk.override {
      accents = ["lavender"];
      size = "standard";
      tweaks = ["normal"];
      variant = "latte";
    })
    pkgs.catppuccin-cursors.latteLavender
  ];

  home.pointerCursor = {
    gtk.enable = true;
    x11 = {
      enable = true;
      defaultCursor = "catppuccin-mocha-peach-cursors";
    };
    package = pkgs.catppuccin-cursors.mochaPeach;
    name = "catppuccin-mocha-peach-cursors";
    size = 24;
  };
  home.activation = {
    xsettingsdConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
            if [ ! -f "${config.xdg.configHome}/xsettingsd/xsettingsd.conf" ]; then
              mkdir -p "${config.xdg.configHome}/xsettingsd"
              cat > "${config.xdg.configHome}/xsettingsd/xsettingsd.conf" << 'XSETTINGSEOF'
      Net/ThemeName "catppuccin-mocha-lavender-standard+normal"
      Net/IconThemeName "Gruvbox-Plus-Dark"
      Gtk/CursorThemeName "catppuccin-mocha-peach-cursors"
      Gtk/PreferDarkTheme 1
      Net/EnableEventSounds 1
      EnableInputFeedbackSounds 0
      Xft/Antialias 1
      Xft/Hinting 1
      Xft/HintStyle "hintslight"
      Xft/RGBA "rgb"
      XSETTINGSEOF
            fi
    '';
  };

  systemd.user.services.xsettingsd = {
    Unit = {
      Description = "xsettingsd";
      After = ["graphical-session-pre.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.xsettingsd}/bin/xsettingsd -c ${config.xdg.configHome}/xsettingsd/xsettingsd.conf";
      Restart = "on-abort";
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
