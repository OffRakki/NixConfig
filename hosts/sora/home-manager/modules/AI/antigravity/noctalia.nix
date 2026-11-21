{
  config,
  lib,
  pkgs,
  ...
}: let
  palettePath = "${config.xdg.configHome}/antigravity/palette.json";
  color = token: "{{colors.${token}.default.hex}}";
  template = {
    name = "noctalia";
    appearance = "{{mode}}";
    vars = lib.mapAttrs (_: color) {
      panel = "surface_container";
      panelAlt = "surface_container_low";
      accent = "primary";
      purple = "secondary";
      orange = "tertiary";
      cyan = "terminal_normal_cyan";
      green = "terminal_normal_green";
      yellow = "terminal_normal_yellow";
      red = "terminal_normal_red";
      text = "on_surface";
      muted = "on_surface_variant";
      dim = "outline";
    };
  };
  fallback = pkgs.writeText "antigravity-noctalia-fallback.json" (builtins.toJSON {
    name = "noctalia";
    appearance = "dark";
    vars = {
      panel = "#313244";
      panelAlt = "#1e1e2e";
      accent = "#89b4fa";
      purple = "#cba6f7";
      orange = "#fab387";
      cyan = "#94e2d5";
      green = "#a6e3a1";
      yellow = "#f9e2af";
      red = "#f38ba8";
      text = "#cdd6f4";
      muted = "#a6adc8";
      dim = "#6c7086";
    };
  });
in {
  xdg.configFile."noctalia/templates/antigravity.json".text = builtins.toJSON template;
  programs.noctalia.settings.theme.templates.user.antigravity = {
    input_path = "${config.xdg.configHome}/noctalia/templates/antigravity.json";
    output_path = palettePath;
  };

  home.activation.seedAntigravityNoctaliaPalette = lib.hm.dag.entryAfter ["linkGeneration"] ''
    $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg (builtins.dirOf palettePath)}
    if [ ! -e ${lib.escapeShellArg palettePath} ]; then
      $DRY_RUN_CMD cp ${fallback} ${lib.escapeShellArg palettePath}
    fi
  '';
}
