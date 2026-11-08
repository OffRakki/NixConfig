{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  themePath = "${config.xdg.stateHome}/noctalia/kitty.conf";
in {
  # Reuse Noctalia's shipped palette without its hook rewriting kitty.conf.
  programs.noctalia.settings.theme.templates.user.kitty = {
    input_path = "${inputs.noctalia}/assets/templates/kitty/kitty.conf";
    output_path = themePath;
    post_hook = "${pkgs.procps}/bin/pkill -USR1 -x kitty || true";
  };

  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    enableGitIntegration = true;
    font.name = "JetBrainsMono Nerd Font";
    font.size = 14;
    # Keep the glass neutral after loading Noctalia's foreground/accent palette.
    extraConfig = ''
      include ${themePath}
      background #000000
    '';
    settings = {
      cursor_shape = "block";
      cursor_shape_unfocused = "hollow";
      cursor_trail = 1;
      cursor_trail_decay = "0.1 0.4";
      url_style = "straight";
      shell = "${lib.getExe pkgs.fish}";
      confirm_os_window_close = 0;
      remember_window_size = false;
      dynamic_background_opacity = false;
      enable_audio_bell = false;
      mouse_hide_wait = 3.0;
      window_padding_width = 4;
      background_opacity = "0.60";
      background_blur = 2;
    };
  };
}
