{pkgs, ...}: {
  home.packages = with pkgs; [
    tailcat
    chromium
    shiru
    viddy
    (import ./packages/orca-slicer.nix {inherit pkgs;})
    (import ./packages/linoffice.nix {inherit pkgs;})
    (import ./packages/penecho.nix {inherit pkgs;})
    drawio
    gnome-sound-recorder
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

    scrcpy

    # Langs
    nil

    # CLI utils
    wineWow64Packages.full
    (import ./packages/winetricks.nix {inherit pkgs;})
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
    pyprland
    wallust
    wlogout
  ];
}
