{
  config,
  lib,
  pkgs,
  ...
}: let
  themePath = "${config.programs.pi-coding-agent.configDir}/themes/noctalia.json";
  baseTheme = builtins.fromJSON (builtins.readFile ./themes/catppuccin-mocha.json);
  color = token: "{{colors.${token}.default.hex}}";
  template =
    baseTheme
    // {
      "$schema" = "https://pi.dev/schemas/theme.schema.json";
      name = "noctalia";
      appearance = "{{mode}}";
      vars = lib.mapAttrs (_: color) {
        bg = "surface";
        panel = "surface_container";
        panelAlt = "surface_container_low";
        selected = "surface_container_highest";
        border = "outline";
        accent = "primary";
        cyan = "terminal_normal_cyan";
        green = "terminal_normal_green";
        red = "terminal_normal_red";
        yellow = "terminal_normal_yellow";
        orange = "tertiary";
        purple = "secondary";
        text = "on_surface";
        muted = "on_surface_variant";
        dim = "outline";
        toolSuccessBg = "surface_container_low";
        toolErrorBg = "error_container";
      };
      export = {
        pageBg = color "surface";
        cardBg = color "surface_container";
        infoBg = color "surface_container_highest";
      };
    };
  fallback = pkgs.writeText "pi-noctalia-fallback.json" (builtins.toJSON (baseTheme // {name = "noctalia";}));
in {
  # Pi watches this directory for native theme hot-reloads. Leave the directory
  # writable while keeping the existing static themes individually Nix-managed.
  home.file.".pi/agent/themes".recursive = true;

  xdg.configFile."noctalia/templates/pi.json".text = builtins.toJSON template;
  programs.noctalia.settings.theme.templates.user.pi = {
    input_path = "${config.xdg.configHome}/noctalia/templates/pi.json";
    output_path = themePath;
  };

  # Migrate the former whole-directory Home Manager link before linking files.
  # Removing only the link preserves every Nix-owned static theme at its source.
  home.activation.preparePiThemeDirectory = lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] ''
    theme_dir="$HOME/.pi/agent/themes"
    if [ -L "$theme_dir" ]; then
      case "$(readlink "$theme_dir")" in
        /nix/store/*) $DRY_RUN_CMD rm -- "$theme_dir" ;;
        *) echo "Refusing to replace an unmanaged Pi themes symlink" >&2; exit 1 ;;
      esac
    fi
    $DRY_RUN_CMD mkdir -p "$theme_dir"
  '';

  # Pi must be able to start before Noctalia's first theme render.
  home.activation.seedPiNoctaliaTheme = lib.hm.dag.entryAfter ["linkGeneration"] ''
    if [ ! -e ${lib.escapeShellArg themePath} ]; then
      $DRY_RUN_CMD cp ${fallback} ${lib.escapeShellArg themePath}
    fi
  '';
}
