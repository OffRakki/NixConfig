{pkgs, ...}: {
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
    wine64
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
