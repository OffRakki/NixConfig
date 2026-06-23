{
  pkgs,
  lib,
  ...
}: {
  programs.kitty = {
    themeFile = "vague";
    enable = true;
    shellIntegration.enableFishIntegration = true;
    enableGitIntegration = true;
    font.name = "JetBrainsMono Nerd Font Mono";
    font.size = 10;
    settings = {
      cursor_shape = "block";
      cursor_shape_unfocused = "hollow";
      cursor_trail = 1;
      cursor_trail_decay = "0.1 0.4";
      cursor_trail_color = "#f0d489";
      url_style = "straight";
      shell = "${lib.getExe pkgs.fish}";
      confirm_os_window_close = 0;
      dynamic_background_opacity = false;
      enable_audio_bell = false;
      mouse_hide_wait = 3.0;
      window_padding_width = 4;
      # background = "#212226";
      # background_opacity = "0.9";
      background_blur = 2;
    };
  };
}
