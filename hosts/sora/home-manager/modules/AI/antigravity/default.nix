{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.programs.agy;
  sharedTools = import ../shared/tools.nix {inherit pkgs inputs;};
  inherit (sharedTools) nodejs;

  antigravity = pkgs.antigravity-cli.overrideAttrs {
    version = "1.5.13";
    src = pkgs.fetchurl {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13-5999302598852608/linux-x64/cli_linux_x64.tar.gz";
      hash = "sha512-AUs3OHcDrKsfR81TLIu2AWemo1N7D5iR3gPxsf+pYUMHvIPEsvdVEnOwh31yJxawzZ4meC9rKlBwXbTwXhjGjw==";
    };
    meta = pkgs.antigravity-cli.meta // {platforms = ["x86_64-linux"];};
    passthru = {};
  };

  agyStatusline = pkgs.callPackage ./statusline.nix {};
  agyVoice = pkgs.callPackage ./voice.nix {};

  settings = pkgs.writeText "antigravity-settings.json" (builtins.toJSON {
    editor = "hx";
    model = "Gemini 4 Neon (Medium)";
    agentMode = "";
    toolPermission = "always-proceed";
    enableTerminalSandbox = false;
    allowNonWorkspaceAccess = false;
    colorScheme = "terminal";
    statusLine = {
      type = "command";
      command = "${lib.getExe agyStatusline}";
    };
    title = {
      type = "command";
      command = "${lib.getExe agyStatusline} --title";
    };
    voice = {
      fullDuplex = true;
    };
  });

  resources = import ../pi/resources.nix {inherit pkgs;};
  workflows = import ./workflows.nix {
    inherit lib pkgs;
    inherit (sharedTools) reaSkill;
  };

  launcher = pkgs.writeShellScriptBin "agy" ''
    export AGY_CLI_DISABLE_AUTO_UPDATE=true
    show_banner=true
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      show_banner=false
    fi
    for arg in "$@"; do
      case "$arg" in
        -p|--print|--prompt|-h|--help|acp|agent|agents|changelog|help|install|mcp|mic-serve|models|plugin|plugins|remote-control|update)
          show_banner=false
          break
          ;;
      esac
    done
    if [ "$show_banner" = true ]; then
      cols="''${COLUMNS:-$(${pkgs.ncurses}/bin/tput cols 2>/dev/null || echo 132)}"
      COLUMNS="$cols" ${lib.getExe agyStatusline} --banner || true
    fi
    exec ${lib.getExe antigravity} --settings ${settings} "$@"
  '';
in {
  imports = [
    ./noctalia.nix
  ];

  options.programs.agy = {
    enable = lib.mkEnableOption "the Antigravity CLI";
    remoteControl.enable = lib.mkEnableOption "the Antigravity remote-control daemon";
  };

  config = lib.mkMerge [
    {
      programs.agy = {
        enable = true;
        remoteControl.enable = true;
      };
    }
    (lib.mkIf cfg.enable (lib.mkMerge [
      {
        home.packages = [launcher agyVoice];
        xdg.desktopEntries = {
          agy = {
            name = "Antigravity";
            genericName = "AI Coding Assistant";
            comment = "Antigravity terminal-based AI coding assistant";
            exec = "kitty --directory /home/rakki/Projects/NixConfig -e agy";
            icon = "utilities-terminal";
            terminal = false;
            categories = [
              "Development"
              "ConsoleOnly"
            ];
            type = "Application";
          };
          agy-voice = {
            name = "Antigravity Voice";
            genericName = "Voice AI Coding Assistant";
            comment = "Local voice TUI for Antigravity CLI";
            exec = "kitty --directory /home/rakki/Projects/NixConfig -e agy-voice --duplex";
            icon = "audio-input-microphone";
            terminal = false;
            categories = [
              "Development"
              "ConsoleOnly"
            ];
            type = "Application";
          };
        };
        home.file = {
          ".gemini/config/AGENTS.md".source = resources.context;
          ".gemini/config/plugins.json".text = builtins.toJSON {
            entries = [{path = toString workflows;}];
          };
          ".gemini/config/mcp_config.json".text = builtins.toJSON {
            mcpServers = {
              pi-web-access = {
                command = "${sharedTools.piWebAccessMcp}/bin/pi-web-access-mcp";
              };
            };
          };
        };
      }
      (import ./usage {
        inherit pkgs nodejs;
        agyPackage = launcher;
      })
    ]))
    (lib.mkIf (cfg.enable && cfg.remoteControl.enable) {
      home.persistence."/persist".directories = [
        {
          directory = ".gemini/antigravity-cli";
          mode = "0700";
        }
      ];

      # Sora's linger flag is persisted under /var/lib/systemd.
      systemd.user.services.antigravity-cli-daemon = {
        Unit = {
          Description = "Antigravity CLI remote-control daemon";
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = "${lib.getExe launcher} remote-control serve";
          Restart = "on-failure";
          RestartSec = "10s";
          # Match agy's native unit: don't loop when sign-in is required.
          RestartPreventExitStatus = 3;
          TimeoutStopSec = "30s";
          UMask = "0077";
        };
        Install.WantedBy = ["default.target"];
      };
    })
  ];
}
