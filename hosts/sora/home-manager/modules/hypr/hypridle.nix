{...}: {
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "hyprlock";
        on_lock_cmd = "systemd-run --user --collect --unit=hypridle-dpms-off --on-active=1m hyprctl dispatch \"hl.dsp.dpms({ action = 'disable' })\"";
        on_unlock_cmd = "systemctl --user stop hypridle-dpms-off.timer 2>/dev/null; hyprctl dispatch \"hl.dsp.dpms({ action = 'enable' })\"";
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
