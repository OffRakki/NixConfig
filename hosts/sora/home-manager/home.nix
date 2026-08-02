{
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}: {
  imports = [
    ../../home-manager/profiles/base.nix
    inputs.catppuccin.homeModules.catppuccin
    inputs.noctalia.homeModules.default
    inputs.spicetify-nix.homeManagerModules.spicetify
    ./modules
    ./home-packages.nix
    ./gtk.nix
    ./darkman.nix
    ./qt.nix
    ./xdg-portals.nix
    ./persistence.nix
    ./onedrive.nix
  ];

  home.activation.installBambuFlatpaks = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}"
    export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}"

    chmod u+w "$XDG_DATA_HOME/flatpak/exports/share/icons/hicolor/index.theme" 2>/dev/null || true

    ${pkgs.flatpak}/bin/flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    ${pkgs.flatpak}/bin/flatpak install --user --noninteractive -y flathub \
      com.bambulab.BambuStudio \
      com.orcaslicer.OrcaSlicer \
      "org.freedesktop.Platform.GL.nvidia-${lib.replaceStrings ["."] ["-"] osConfig.hardware.nvidia.package.version}//1.4"
  '';

  home = {
    username = "rakki";
    homeDirectory = "/home/rakki";
    sessionVariables = {
      OPENCODE_SERVER_PASSWORD = "$(cat ${osConfig.sops.secrets.opencodeServerPass.path})";
      OPENCODE_SERVER_USERNAME = "rakki";
      SOPS_AGE_KEY_FILE = "$HOME/sync/sops/age/keys.txt";
    };
  };

  xdg = {
    userDirs = {
      enable = true;
      createDirectories = true;
      setSessionVariables = true;
    };
    mimeApps = {
      enable = true;
      defaultApplications = lib.mkBefore {
        "image/jpeg" = ["imv.desktop"];
        "image/jpg" = ["imv.desktop"];
        "image/png" = ["imv.desktop"];
        "image/gif" = ["imv.desktop"];
        "image/webp" = ["imv.desktop"];
        "image/bmp" = ["imv.desktop"];
        "image/svg" = ["imv.desktop"];
        "image/x-tga" = ["imv.desktop"];
        "text/plain" = ["helix.desktop"];
        "text/x-ini" = ["helix.desktop"];
        "application/x-ini" = ["helix.desktop"];
        "text/markdown" = ["helix.desktop"];
        "text/html" = ["firefox.desktop"];
        "text/xml" = ["firefox.desktop"];
        "x-scheme-handler/http" = ["firefox.desktop"];
        "x-scheme-handler/https" = ["firefox.desktop"];
        "application/pdf" = ["org.gnome.Evince.desktop"];
        "inode/directory" = ["nemo.desktop;pcmanfm-qt.desktop"];
      };
    };
    desktopEntries = {
      imv = {
        name = "imv";
        genericName = "Image Viewer";
        exec = "imv %F";
        terminal = false;
        categories = [
          "Graphics"
          "Viewer"
        ];
        mimeType = [
          "image/jpeg"
          "image/jpg"
          "image/png"
          "image/gif"
          "image/webp"
          "image/bmp"
          "image/svg"
        ];
      };
      helix = {
        name = "Helix";
        genericName = "Text Editor";
        exec = "kitty -e hx %F";
        terminal = false;
        categories = [
          "Utility"
          "TextEditor"
        ];
        mimeType = [
          "text/plain"
          "text/markdown"
          "text/x-ini"
          "application/x-ini"
        ];
      };
      whatsappWeb = {
        name = "Whatsapp";
        genericName = "Web Whatsapp";
        exec = "brave --app=https://web.whatsapp.com";
        terminal = false;
        categories = [
          "Network"
          "WebBrowser"
        ];
      };
    };
  };
}
