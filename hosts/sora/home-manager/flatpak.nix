{
  lib,
  osConfig,
  pkgs,
  ...
}: let
  airiVersion = "0.11.3";
  airiHash = "sha256-9hENJIx5Vgnpm0Cxwx5g2GNb1jKrymwaPA20je9Ix2M=";
  airiBundle = pkgs.fetchurl {
    url = "https://github.com/moeru-ai/airi/releases/download/v${airiVersion}/AIRI-${airiVersion}-linux-x64.flatpak";
    hash = airiHash;
  };
  nvidiaVersion = lib.replaceStrings ["."] ["-"] osConfig.hardware.nvidia.package.version;
in {
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = true;
    packages = [
      {
        appId = "ai.moeru.airi";
        bundle = "${airiBundle}";
        sha256 = airiHash;
      }
      "com.bambulab.BambuStudio"
      "com.orcaslicer.OrcaSlicer"
      "org.vinegarhq.Sober"
      "org.freedesktop.Platform.GL.nvidia-${nvidiaVersion}//1.4"
    ];
  };
}
