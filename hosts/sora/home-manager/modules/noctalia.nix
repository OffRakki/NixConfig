{
  config,
  pkgs,
  lib,
  inputs,
  nixConfigRoot,
  ...
}: let
  noctalia = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    # Darkman owns application color-scheme; Noctalia only themes its own shell.
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace src/app/application_services.cpp \
          --replace-fail 'syncGSettingsColorScheme(appliedMode);' '(void)appliedMode;' \
          --replace-fail 'syncGSettingsColorScheme(m_themeService.resolvedMode());' '(void)0;'
      '';
  });
  communityPlugins = pkgs.fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "community-plugins";
    rev = "98ee5154f1b0b6b92d9f41c2ba207b5da9bc9b83";
    hash = "sha256-rpjrOikOR6HYra2XsQFWnOROA92Nap1sci/Li/+GL8I=";
  };
  sysmon = stat: {
    type = "sysmon";
    inherit stat;
    visualization = "none";
    actions.left = "exec ${lib.getExe pkgs.resources}";
  };
  sessionAction = action: shortcut: {
    inherit action shortcut;
    countdown_seconds = 10;
  };
in {
  home.packages = [pkgs.ddcutil];

  home.persistence."/persist".directories = [
    ".config/noctalia"
    ".cache/noctalia"
    ".cache/noctalia-qs"
    ".local/state/noctalia"
    ".local/share/noctalia"
  ];

  # Calendar day right-click uses the text/calendar default application.
  xdg.desktopEntries.khal-calendar = {
    name = "Calendar";
    exec = "${lib.getExe pkgs.kitty} -e ${pkgs.khal}/bin/khal interactive";
    terminal = false;
    categories = ["Office" "Calendar"];
    mimeType = ["text/calendar"];
  };
  xdg.mimeApps.defaultApplications."text/calendar" = ["khal-calendar.desktop"];

  programs.noctalia = {
    enable = true;
    package = noctalia;
    settings = {
      shell = {
        corner_radius_scale = 0.75;
        avatar_path = "${../../../../assets/svgs/pelucio.jpg}";
        time_format = "{:%H:%M}";
        date_format = "%d/%m/%Y";
        polkit_agent = false;
        telemetry_enabled = false;
        shadow.direction = "down_right";
        panel = {
          transparency_mode = "soft";
          launcher_position = "top_left";
          session_placement = "floating";
          open_near_click_control_center = true;
          open_near_click_wallpaper = true;
        };
        launcher = {
          app_grid = true;
          pinned = ["pi-coding-agent" "firefox" "thunderbird"];
          providers.session.global = true;
          providers.windows.global = true;
        };
        session = {
          grid = true;
          actions = [
            ((sessionAction "command" "1")
              // {
                label = "Lock";
                glyph = "lock";
                command = lib.getExe pkgs.hyprlock;
              })
            (sessionAction "suspend" "2")
            (sessionAction "reboot" "3")
            (sessionAction "logout" "4")
            (sessionAction "shutdown" "5")
            ((sessionAction "command" "6")
              // {
                label = "Reboot to UEFI";
                glyph = "restart";
                command = "${pkgs.systemd}/bin/systemctl reboot --firmware-setup";
              })
          ];
        };
      };
      # Hyprlock and Hypridle remain the session lock/idle owners.
      lockscreen = {
        enabled = false;
        lock_before_suspend = false;
      };
      idle.behavior = {
        lock.enabled = false;
        screen-off.enabled = false;
      };
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Kanagawa";
        templates = {
          enable_builtin_templates = false;
          enable_community_templates = false;
        };
      };
      wallpaper = {
        directory = "${nixConfigRoot}/assets/wallpapers";
        default.path = "${nixConfigRoot}/assets/wallpapers/6eaZOze.jpeg";
        fill_mode = "crop";
        edge_smoothness = 0.05;
      };
      dock.enabled = false;
      backdrop.enabled = false;
      bar.main = {
        position = "top";
        thickness = 30;
        background_opacity = 0.93;
        margin_ends = 3;
        margin_edge = 3;
        padding = 2;
        widget_spacing = 6;
        font_scale = 1.3;
        capsule = true;
        start = ["control-center" "cpu" "temp" "ram" "swap" "rx" "tx" "media" "active_window"];
        center = ["workspaces"];
        end = ["privacy" "davemhammer/tailscale:status" "tray" "battery" "volume" "brightness" "notifications" "todos" "dotnetrob/cat:cat" "clock"];
        monitor.dp2 = {
          match = "DP-2";
          position = "bottom";
        };
        dead_zone.actions = {
          right = "panel-toggle control-center";
          middle = "none";
          scroll_up = "none";
          scroll_down = "none";
        };
      };
      widget = {
        control-center = {
          custom_image = "${../../../../assets/svgs/nix-snowflake-white.svg}";
          custom_image_colorize = true;
        };
        cpu = sysmon "cpu_usage";
        temp = sysmon "cpu_temp";
        ram = sysmon "ram_used";
        swap = sysmon "swap_pct";
        rx = sysmon "net_rx";
        tx = sysmon "net_tx";
        media = {
          artist_first = true;
          max_length = 150;
          title_scroll = "on_hover";
        };
        active_window.max_length = 200;
        tray.drawer = true;
        workspaces = {
          label_source = "name";
          max_label_chars = 7;
          labels_only_when_occupied = true;
          hide_when_empty = true;
          pill_scale = 1.0;
          empty_color = "tertiary";
          font_weight = 600;
          actions = {
            scroll_up = "none";
            scroll_down = "none";
          };
        };
        battery = {
          device = "hid-24ae:185a-battery-0";
          display_mode = "graphic";
        };
        todos = {
          type = "custom_button";
          glyph = "list-check";
          tooltip = "Tasks";
          actions.left = "exec ${lib.getExe pkgs.kitty} -e ${lib.getExe config.programs.todoman.package} repl";
        };
      };
      control_center.shortcuts = map (type: {inherit type;}) ["bluetooth" "wallpaper" "system" "notification" "caffeine" "nightlight"];
      notification = {
        position = "top_center";
        monitors = ["DP-1"];
        layer = "overlay";
        background_opacity = 1.0;
      };
      osd = {
        position = "top_right";
        monitors = ["DP-1"];
        background_opacity = 1.0;
        kinds.caffeine = false;
      };
      audio = {
        enable_overdrive = true;
        enable_sounds = false;
      };
      brightness = {
        enable_ddcutil = true;
        minimum_brightness = 0.01;
      };
      nightlight.enabled = false;
      location.address = "Piracicaba, Brazil";
      weather = {
        enabled = true;
        unit = "celsius";
      };
      system.monitor = {
        cpu_usage_activity_threshold = 80;
        cpu_usage_critical_threshold = 90;
        cpu_temp_activity_threshold = 80;
        cpu_temp_critical_threshold = 90;
        ram_pct_activity_threshold = 80;
        ram_pct_critical_threshold = 90;
        swap_pct_activity_threshold = 80;
        swap_pct_critical_threshold = 90;
      };
      calendar = {
        enabled = true;
        event_date_format = "%d/%m/%Y";
        event_time_format = "%H:%M";
        account = {
          events = {
            type = "vdir";
            name = "Events";
            path = "${config.home.homeDirectory}/Calendars/events";
            color = "#87CEEB";
          };
          feriados = {
            type = "vdir";
            name = "Feriados";
            path = "${config.home.homeDirectory}/Calendars/feriados";
            color = "#006400";
          };
        };
      };
      plugins = {
        enabled = ["davemhammer/tailscale" "dotnetrob/cat"];
        auto_update = "none";
        source = [
          {
            name = "community";
            kind = "path";
            location = "${communityPlugins}";
            enabled = true;
          }
        ];
      };
    };
  };
}
