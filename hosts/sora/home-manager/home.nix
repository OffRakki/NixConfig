{
  inputs,
  lib,
  osConfig,
  ...
}: {
  imports = [
    ../../home-manager/profiles/base.nix
    inputs.catppuccin.homeModules.catppuccin
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
    inputs.noctalia.homeModules.default
    inputs.spicetify-nix.homeManagerModules.spicetify
    ./modules
    ./flatpak.nix
    ./ds4u.nix
    ./home-packages.nix
    ./gtk.nix
    ./darkman.nix
    ./qt.nix
    ./xdg-portals.nix
    ./persistence.nix
    ./onedrive.nix
  ];

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
    };
  };
}
