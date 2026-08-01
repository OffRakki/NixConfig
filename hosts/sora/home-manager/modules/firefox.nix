{...}: {
  programs.firefox = {
    enable = true;
    configPath = ".config/mozilla/firefox";
    profiles = {
      Rakki = {
        settings = {
          "widget.content.allow-gtk-dark-theme" = true;
          "layout.css.prefers-color-scheme.content" = 2;
        };
        userChrome = ''
          #TabsToolbar { visibility: collapse !important; }
          #sidebar-panel-header { display: none; }
          #sidebar-header { display: none; }
        '';
      };
    };
  };
}
