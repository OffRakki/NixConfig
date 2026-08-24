{pkgs, ...}: {
  programs.steam = {
    enable = true;
    package = pkgs.millennium-steam;
    gamescopeSession.enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    extraCompatPackages = with pkgs; [
      catppuccin-cursors.mochaPeach
      proton-ge-bin
      dwproton-bin
    ];
  };
  programs.gamescope = {
    enable = true;
    capSysNice = false;
    args = [
      "-r"
      "162"
    ];
  };
}
