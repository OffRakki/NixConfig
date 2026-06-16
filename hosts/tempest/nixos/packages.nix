{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    firefox
    pkgs.python311
    kitty.terminfo
    ethtool
    nh
    podman-compose
    btop
    intel-gpu-tools
    nvitop
    helix
    wget
    pciutils
    usbutils
    cifs-utils
    ffmpeg
    rsync
    duf
    zoxide
    mpv
    imv
    pavucontrol
  ];
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];
}
