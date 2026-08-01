{pkgs, ...}: let
  ab-download-manager = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "ab-download-manager";
    version = "1.10.1";

    src = pkgs.fetchurl {
      url = "https://github.com/amir1376/ab-download-manager/releases/download/v${version}/ABDownloadManager_${version}_linux_x64.tar.gz";
      hash = "sha256-2q5TLfwHIx2uAvzjcaZrUObB70ypSnBbs7XyuZaCXuc=";
    };

    nativeBuildInputs = [pkgs.autoPatchelfHook pkgs.makeWrapper];
    buildInputs = with pkgs; [
      alsa-lib
      fontconfig
      freetype
      libGL
      libxkbcommon
      stdenv.cc.cc.lib
      wayland
      libx11
      libxext
      libxi
      libxrender
      libxtst
      zlib
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/ABDownloadManager" "$out/bin" "$out/share/applications" "$out/share/pixmaps"
      cp -r . "$out/lib/ABDownloadManager"
      makeWrapper "$out/lib/ABDownloadManager/bin/ABDownloadManager" "$out/bin/ABDownloadManager" \
        --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [pkgs.fontconfig]}
      ln -s "$out/lib/ABDownloadManager/bin/ABDownloadManagerCli" "$out/bin/ABDownloadManagerCli"
      ln -s "$out/lib/ABDownloadManager/bin/ABDownloadManagerNativeMessagingHost" "$out/bin/ABDownloadManagerNativeMessagingHost"
      ln -s "$out/lib/ABDownloadManager/lib/ABDownloadManager.png" "$out/share/pixmaps/ab-download-manager.png"
      cat > "$out/share/applications/com.abdownloadmanager.desktop" <<EOF
      [Desktop Entry]
      Name=AB Download Manager
      Comment=Manage and organize downloads
      Categories=Network;FileTransfer;
      Exec=ABDownloadManager
      Icon=ab-download-manager
      Terminal=false
      Type=Application
      StartupWMClass=com-abdownloadmanager-desktop-AppKt
      EOF
      runHook postInstall
    '';

    meta = {
      description = "Download manager with browser integration";
      homepage = "https://github.com/amir1376/ab-download-manager";
      license = pkgs.lib.licenses.asl20;
      mainProgram = "ABDownloadManager";
      platforms = ["x86_64-linux"];
    };
  };

  penecho-unwrapped = pkgs.buildNpmPackage {
    pname = "penecho";
    version = "0.7.0";

    src = pkgs.fetchFromGitHub {
      owner = "penecho";
      repo = "penecho";
      rev = "067222311e09a1fa3dc26581efb8dbea8fd2d491";
      hash = "sha256-yDSM8+mq/8/ZGXHaZ6Had+7hEBrCOyQvNbgVHGBdSFQ=";
    };
    npmDepsHash = "sha256-t9VoxA5caqz7zNzO1AZJhOPdOQ8/KPhTKl7QYQddEK0=";
    dontNpmBuild = true;

    nativeBuildInputs = [pkgs.makeWrapper];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/node_modules/penecho" "$out/bin"
      cp -r . "$out/lib/node_modules/penecho"
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/penecho-unwrapped" \
        --add-flags "$out/lib/node_modules/penecho/cli.js"
      runHook postInstall
    '';

    meta = {
      description = "Shared AI canvas for handwriting, equations, and diagrams";
      homepage = "https://github.com/penecho/penecho";
      license = pkgs.lib.licenses.agpl3Only;
      mainProgram = "penecho-unwrapped";
    };
  };

  penecho = pkgs.writeShellScriptBin "penecho" ''
    # Codex refuses helper binaries when PenEcho isolates CODEX_HOME below /tmp.
    export TMPDIR="''${XDG_CACHE_HOME:-$HOME/.cache}/penecho/tmp"
    mkdir -p "$TMPDIR"
    chmod 700 "$TMPDIR"
    exec ${penecho-unwrapped}/bin/penecho-unwrapped "$@"
  '';

  orca-slicer-flatpak = pkgs.writeShellScriptBin "orca-slicer" ''
    exec ${pkgs.flatpak}/bin/flatpak run com.orcaslicer.OrcaSlicer "$@"
  '';

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
    ab-download-manager
    viddy
    orca-slicer-flatpak
    penecho
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
    wineWow64Packages.full
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
