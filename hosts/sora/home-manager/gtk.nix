{pkgs, ...}: {
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
  services.xsettingsd = {
    enable = true;
    settings = {
      "Net/ThemeName" = "catppuccin-mocha-lavender-standard+normal";
      "Net/IconThemeName" = "Gruvbox-Plus-Dark";
    };
  };
}
