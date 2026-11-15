{
  config,
  lib,
  pkgs,
  ...
}: let
  themePath = "${config.xdg.stateHome}/noctalia/hyprlock-theme.conf";
  font = "JetBrainsMono Nerd Font";
  mainMonitor = "DP-1";
  label = text: font_size: position: color: {
    monitor = mainMonitor;
    inherit text font_size position color;
    font_family = font;
    halign = "left";
    valign = "center";
    zindex = 2;
  };
in {
  xdg.configFile."noctalia/templates/hyprlock.conf".text = ''
    $lockWallpaper = {{image}}
    $lockPrimary = rgba({{colors.primary.default.hex_stripped}}ff)
    $lockText = rgba({{colors.on_surface.default.hex_stripped}}ff)
    $lockMuted = rgba({{colors.on_surface.default.hex_stripped}}bf)
    $lockPanel = rgba({{colors.surface.default.hex_stripped}}c0)
    $lockPill = rgba({{colors.on_surface.default.hex_stripped}}20)
    $lockInput = rgba({{colors.on_surface.default.hex_stripped}}14)
    $lockError = rgba({{colors.error.default.hex_stripped}}ff)
  '';

  programs.noctalia.settings.theme.templates.user.hyprlock = {
    input_path = "${config.xdg.configHome}/noctalia/templates/hyprlock.conf";
    output_path = themePath;
  };

  # A first lock must work even before Noctalia has rendered its first palette.
  home.activation.hyprlockTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg (builtins.dirOf themePath)}
    $DRY_RUN_CMD touch ${lib.escapeShellArg themePath}
  '';

  programs.hyprlock = {
    enable = true;
    settings = {
      "$lockWallpaper" = "${config.home.homeDirectory}/Pictures/Wallpapers/6eaZOze.jpeg";
      "$lockPrimary" = "rgba(bfa16eff)";
      "$lockText" = "rgba(e1e1e1ff)";
      "$lockMuted" = "rgba(e1e1e1bf)";
      "$lockPanel" = "rgba(141415c0)";
      "$lockPill" = "rgba(e1e1e120)";
      "$lockInput" = "rgba(e1e1e114)";
      "$lockError" = "rgba(ffb4abff)";
      source = themePath;

      general = {
        hide_cursor = true;
        ignore_empty_input = true;
        fractional_scaling = 0;
      };

      # Outputs without widgets stay black, but remain session-locked.
      background = [
        {
          monitor = mainMonitor;
          path = "${config.home.homeDirectory}/Pictures/Wallpapers/wallhaven-lygzqq.jpg";
          blur_passes = 0;
        }
      ];

      # Layout 11: a left-side panel, with the wallpaper unobscured on the right.
      # https://github.com/mahaveergurjar/Hyprlock-Dots
      shape = [
        {
          monitor = mainMonitor;
          size = "660, 100%";
          color = "$lockPanel";
          rounding = 0;
          border_size = 0;
          position = "0, 0";
          halign = "left";
          valign = "center";
          zindex = 0;
        }
        {
          monitor = mainMonitor;
          size = "320, 55";
          color = "$lockPill";
          rounding = -1;
          border_size = 0;
          position = "170, -140";
          halign = "left";
          valign = "center";
          zindex = 1;
        }
      ];

      label = [
        (label "Welcome!" 55 "165, 320" "$lockPrimary")
        (label ''cmd[update:1000] ${pkgs.coreutils}/bin/date '+%H:%M' '' 40 "255, 240" "$lockText")
        (label ''cmd[update:60000] ${pkgs.coreutils}/bin/date '+%A, %B %d' '' 20 "180, 175" "$lockMuted")
        (label "  $USER" 16 "281, -140" "$lockText")
      ];

      input-field = [
        {
          monitor = mainMonitor;
          size = "320, 55";
          outline_thickness = 1;
          dots_size = 0.2;
          dots_spacing = 0.2;
          dots_center = true;
          outer_color = "$lockPrimary";
          inner_color = "$lockInput";
          font_color = "$lockText";
          check_color = "$lockPrimary";
          fail_color = "$lockError";
          fail_text = "$FAIL <b>($ATTEMPTS)</b>";
          fade_on_empty = false;
          font_family = font;
          placeholder_text = "<i>Enter password</i>";
          hide_input = false;
          rounding = -1;
          position = "170, -220";
          halign = "left";
          valign = "center";
          zindex = 2;
        }
      ];
    };
  };
}
