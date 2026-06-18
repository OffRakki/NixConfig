{
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    inputs.kopuz.packages.${pkgs.stdenv.hostPlatform.system}.default
    # NH
    nh
    nix-output-monitor
    nvd

    whisper-cpp

    # Secrets
    sops
    age

    pwvucontrol
    vulkan-tools
    floorp-bin
    lmstudio
    gollama
    gparted
    i2c-tools
    _7zip-zstd
    catppuccin-kvantum
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
    (prismlauncher.override {
      jdks = [
        pkgs.temurin-bin-8
        pkgs.temurin-bin-17
        pkgs.temurin-bin-21
        pkgs.temurin-bin-25
      ];
    })
    pomodoro-gtk
    qbittorrent-nox
    passmark-performancetest
    s-tui
    qdiskinfo
    kdiskmark
    (pkgs.nemo-with-extensions.override {
      extensions = [
        pkgs.nemo-python
        pkgs.folder-color-switcher
        pkgs.nemo-fileroller
        pkgs.nemo-emblems
        pkgs.nemo-preview
      ];
    })
    glib
    gsettings-desktop-schemas
    inputs.nuls.packages.${pkgs.stdenv.hostPlatform.system}.default
    mangohud
    mangojuice
    qt6.qtwayland
    qt5.qtwayland
    parallel-full
    qgnomeplatform-qt6
    lprint
    android-tools
    marksman
    bitwarden-cli
    libreoffice-fresh
    rclone
    rclone-browser
    gpu-screen-recorder
    gpu-screen-recorder-gtk
    dotool
    sddm-astronaut
    sddm-sugar-dark
    appimage-run
    grc
    xwayland-satellite
    xwayland
    xwayland-run
    localsend
    netplan
    kdePackages.kde-cli-tools
    dialog
    freerdp
    iproute2
    tailscale
    nyxt
    sudo-rs
    mprime
    diffutils
    matugen
    pass
    msmtp
    uutils-coreutils-noprefix
    ueberzug
    direnv
    dragon-drop
    refind
    os-prober
    nixd
    evil-helix
    curl
    wireplumber
    wl-clipboard-rs
    wl-clip-persist
    clipse
    fishPlugins.done
    fishPlugins.fzf-fish
    fishPlugins.forgit
    # fishPlugins.hydro  # disabled — conflicts with tide fish_prompt
    fishPlugins.grc
    #gaming
    lutris
    wine
    winetricks
    protontricks
    osu-lazer-bin
    heroic

    # Containers
    podman-compose
    podman-tui
    podman-desktop

    rust-paddle-ocr
    dgop
    vial
    dnd-tools
    waypaper
    ttyper
    rusty-man
    wiki-tui
    mpd
    nvidia-container-toolkit
    docker
    docker-client
    libvirt
    qemu
    baobab
    btrfs-progs
    clang
    cpufrequtils
    gsettings-qt
    killall
    libappindicator
    openssl
    pciutils
    vim
    xdg-user-dirs
    xdg-utils
    # oh-my-fish  # disabled — conflicts with tide
    spicetify-cli

    # WM Stuff
    hyprpaper
    ags_1
    wl-color-picker
    cava
    eog
    gnome-system-monitor
    grim
    gtk-engine-murrine
    inxi
    jq
    nwg-look
    nvitop
    pamixer
    libsForQt5.qtstyleplugins
    slurp
    swappy
    awww
    xarchiver
    yad
    hyprshot
  ];

  programs.nm-applet.indicator = true;
  programs.virt-manager.enable = true;
  programs.seahorse.enable = true;
  programs.fuse.userAllowOther = true;
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Extra Portal Configuration
}
