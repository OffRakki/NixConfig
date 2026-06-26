{pkgs, ...}: let
  winetricks-wrapped = pkgs.writeShellScriptBin "winetricks" ''
    # Resolve real ELF binaries from the wine wrapper's WINELOADER
    # so winetricks can detect the architecture (it reads ELF headers directly)
    wine_bin="$(command -v wine 2>/dev/null)" || wine_bin="wine"
    wineloader="$(sed -n "s/^export WINELOADER='\\(.*\\)'$/\1/p" "$wine_bin" 2>/dev/null)"
    if [ -n "$wineloader" ] && [ -x "$wineloader" ]; then
      export WINE_BIN="$wineloader"
      export WINESERVER_BIN="$(dirname "$wineloader")/wineserver"
    fi
    # Suppress harmless 64-bit prefix warnings (we know it's 64-bit)
    export W_NO_WIN64_WARNINGS=1
    exec ${pkgs.winetricks}/bin/winetricks "$@"
  '';
in {
  home.packages = with pkgs; [
    codex
    drawio
    gnome-sound-recorder
    quickshell
    kdePackages.qttools
    lm_sensors
    r2modman
    evince
    anki
    imv
    mpv
    obsidian
    pavucontrol
    teams-for-linux
    telegram-desktop
    vesktop
    qalculate-gtk
    vlc
    warp
    lxqt.pcmanfm-qt
    foot
    swaybg
    onlyoffice-desktopeditors
    onlyoffice-documentserver
    runelite
    cockatrice

    portfolio
    wealthfolio

    # Langs
    nil

    # CLI utils
    aerc
    wineWowPackages.full
    winetricks-wrapped
    satty
    flatpak
    yazi
    ranger
    libqalculate
    comma
    bc
    bottom
    brightnessctl
    cliphist
    ffmpeg
    ffmpegthumbnailer
    fzf
    git-graph
    grimblast
    htop
    ntfs3g
    mediainfo
    microfetch
    playerctl
    ripgrep
    showmethekey
    silicon
    udisks
    ueberzugpp
    unzip
    w3m
    wget
    wl-clipboard
    wtype
    yt-dlp
    zip

    # Coding stuff
    nodejs
    python311
    vscode-fhs

    # WM stuff
    libnotify
    aquamarine
    hyprlang
    hyprutils

    # Other
    bemoji
    nix-prefetch-scripts

    # Moved from system packages
    nmap
    netcat
    rofi
    firefox
    starship
    btop
    waybar-mpris
    television
    gdu
    ncdu
    glow
    gitlogue
    ripgrep-all
    fd
    zoxide
    xh
    zellij
    gitui
    dust
    dua
    hyperfine
    bacon
    cargo-info
    fselect
    ncspot
    spotify-player
    delta
    tokei
    just
    mask
    mprocs
    presenterm
    kondo
    mise
    espanso
    rmpc
    hyprpicker
    dysk
    zenith-nvidia
    tmux
    bitwarden-desktop
    pyprland
    wallust
    wlogout
  ];
}
