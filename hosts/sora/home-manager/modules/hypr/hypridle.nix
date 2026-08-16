{...}: {
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        on_lock_cmd = "pid=$(pidof hyprlock) && sleep 60 && kill -0 \"$pid\" && hyprctl dispatch \"hl.dsp.dpms({ action = 'disable' })\"";
        on_unlock_cmd = "hyprctl dispatch \"hl.dsp.dpms({ action = 'enable' })\"";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch \"hl.dsp.dpms({ action = 'enable' })\"";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "loginctl lock-session";
        }
      ];
    };
  };
}
