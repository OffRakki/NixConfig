{
  config,
  pkgs,
  ...
}: {
  # Noctalia owns the writable output; Vencord watches the themes directory.
  # Enable one local theme at a time rather than replacing GUI settings.
  xdg.configFile = {
    "noctalia/templates/vesktop.css".source = ./vesktop.theme.css;
    "noctalia/templates/vesktop-midnight.css".source = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/noctalia-dev/community-templates/7c4a2cce97479bf209198d5746714fe1b2c311b8/discord/discord-midnight.css";
      sha256 = "0kphxgpwkqhvxlwj1120i16fp90s0mxd6qnrfffgbqpp7vyfcx0s";
    };
  };
  programs.noctalia.settings.theme.templates.user = {
    vesktop = {
      input_path = "${config.xdg.configHome}/noctalia/templates/vesktop.css";
      output_path = "${config.xdg.configHome}/vesktop/themes/noctalia-minimal.theme.css";
    };
    vesktop-midnight = {
      input_path = "${config.xdg.configHome}/noctalia/templates/vesktop-midnight.css";
      output_path = "${config.xdg.configHome}/vesktop/themes/noctalia-midnight.theme.css";
    };
  };
}
