{
  home.persistence."/persist".directories = [
    "sync"
    "Games"
    ".nv"
    ".factorio"
    ".runelite"
    ".local/share/waydroid"
    ".local/share/flatpak"
    ".local/share/containers"
    ".local/share/TelegramDesktop"
    ".local/share/PrismLauncher"
    ".local/share/applications"
    ".local/share/keyrings"
    ".local/state/wireplumber"
    ".local/share/icons"
    ".var/app/com.bambulab.BambuStudio"
    ".config/sunshine"
    ".config/jj"
    ".config/vesktop"
    ".config/dconf"
    ".config/OpenRGB"
    ".cache/nix-index"
    {
      directory = ".ssh";
      mode = "0700";
    }
  ];
}
