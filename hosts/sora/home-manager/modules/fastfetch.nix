{
  programs.fastfetch = {
    enable = true;
    settings = {
      schema = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
      logo = {
        type = "small";
        padding = {
          top = 2;
          left = 3;
        };
      };
      display = {
        separator = "  ";
      };
      modules = [
        # System — Catppuccin Mocha Blue (#89b4fa)
        {
          type = "os";
          key = "▸ OS";
          keyColor = "#89b4fa";
        }
        {
          type = "kernel";
          key = " ├ ";
          keyColor = "#89b4fa";
        }
        {
          type = "packages";
          format = "{nix-system} system, {nix-user} user";
          key = " ├ 󰏖";
          keyColor = "#89b4fa";
        }
        {
          type = "shell";
          key = " └ ";
          keyColor = "#89b4fa";
        }
        "break"
        # Desktop — Catppuccin Mocha Mauve (#cba6f7)
        {
          type = "wm";
          key = "▸ WM";
          keyColor = "#cba6f7";
        }
        {
          type = "icons";
          key = " ├ 󰀻";
          keyColor = "#cba6f7";
        }
        {
          type = "cursor";
          key = " ├ ";
          keyColor = "#cba6f7";
        }
        {
          type = "terminal";
          format = "{pretty-name}";
          key = " └ ";
          keyColor = "#cba6f7";
        }
        "break"
        # Hardware — Catppuccin Mocha Peach (#fab387)
        {
          type = "cpu";
          format = "{1} ({3}) @ {7}";
          key = "▸ HW";
          keyColor = "#f9e2af";
        }
        {
          type = "gpu";
          key = " ├ 󰢮";
          keyColor = "#fab387";
        }
        {
          type = "memory";
          key = " ├ ";
          keyColor = "#fab387";
        }
        {
          type = "disk";
          key = " ├ 󰋊";
          keyColor = "#fab387";
        }
        {
          type = "display";
          key = " └ ";
          keyColor = "#fab387";
        }
        "break"
        # Status — Catppuccin Mocha Green (#a6e3a1)
        {
          type = "uptime";
          key = "▸ UP";
          keyColor = "#a6e3a1";
        }
        {
          type = "localip";
          key = " └ ";
          keyColor = "#a6e3a1";
        }
      ];
    };
  };
}
