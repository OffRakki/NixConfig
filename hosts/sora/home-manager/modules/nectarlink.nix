{
  inputs,
  lib,
  pkgs,
  ...
}: let
  helpers = with pkgs; [
    xclip
    wl-clipboard
    xdg-utils
    gst_all_1.gstreamer
  ];
  gstPlugins = with pkgs; [pipewire gst_all_1.gstreamer.out gst_all_1.gst-plugins-base];
  nectarlink = inputs.nectarlink.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    # Upstream's desktop has no port option; pin QUIC to match the NixOS firewall.
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace desktop/app/src/core_host.rs \
          --replace-fail 'config.downloads_dir = Some(downloads_dir());' \
            'config.port = 7718; config.downloads_dir = Some(downloads_dir());'
      '';
    qtWrapperArgs =
      (old.qtWrapperArgs or [])
      ++ [
        "--prefix"
        "PATH"
        ":"
        (lib.makeBinPath helpers)
        "--prefix"
        "GST_PLUGIN_SYSTEM_PATH_1_0"
        ":"
        (lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins)
      ];
  });
in {
  home.packages = [nectarlink] ++ helpers;
  home.persistence."/persist".directories = [".local/share/Nectarlink"];

  wayland.windowManager.hyprland.extraConfig = ''
    hl.window_rule({
      name = "nectarlink-island",
      match = { initial_class = "^nectarlink$", initial_title = "^Nectar Island - PiP$" },
      float = true,
      pin = true,
      no_initial_focus = true,
      border_size = 0,
      -- IslandWindow.qml uses a 400x104 transparent surface around its expanding pill.
      size = "400 104",
      move = "(monitor_w-window_w)/2 40",
      monitor = "DP-1",
      no_blur = true,
      no_shadow = true,
      opacity = "1 1",
    })

    hl.on("hyprland.start", function()
      hl.exec_cmd("${lib.getExe nectarlink} --minimized")
    end)
  '';
}
