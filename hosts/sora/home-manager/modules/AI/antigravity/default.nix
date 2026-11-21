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
    inherit (sharedTools) reaSkill piIntercomInboxHook;
  };

  launcher = pkgs.writeShellScriptBin "agy" ''
    export AGY_CLI_DISABLE_AUTO_UPDATE=true
    show_banner=true
    use_bili=true
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      show_banner=false
    fi
    if [ -n "''${BILI_AGY_WRAPPED:-}" ] || [ -n "''${CLOUD_CODE_URL:-}" ] || [ -n "''${AGY_DISABLE_BILI:-}" ]; then
      use_bili=false
    fi
    if [ -n "''${BILI_AGY_WRAPPED:-}" ]; then
      show_banner=false
    fi
    for arg in "$@"; do
      case "$arg" in
        -p|--print|--prompt)
          show_banner=false
          ;;
        --output-format|--output-format=*|--input-format|--input-format=*|--json-schema|--json-schema=*)
          show_banner=false
          use_bili=false
          ;;
        -h|--help|acp|agent|agents|changelog|help|install|mcp|mic-serve|models|plugin|plugins|remote-control|update)
          show_banner=false
          use_bili=false
          break
          ;;
      esac
    done
    if [ "$show_banner" = true ]; then
      cols="''${COLUMNS:-$(${pkgs.ncurses}/bin/tput cols 2>/dev/null || echo 132)}"
      COLUMNS="$cols" ${lib.getExe agyStatusline} --banner || true
    fi
    if [ "$use_bili" = true ]; then
      exec env BILI_AGY_WRAPPED=1 ${lib.getExe sharedTools.bili} antigravity -- "$@"
    fi
    exec ${lib.getExe antigravity} --settings ${settings} "$@"
  '';

  seedRemoteControlToken = pkgs.writeShellScript "agy-seed-remote-control-token" ''
    token_file="$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
    if [ ! -s "$token_file" ]; then
      # Interactive agy removes the file token after refreshing via keyring;
      # remote-control start re-seeds it before hitting the read-only Nix unit.
      ${lib.getExe launcher} remote-control start >/dev/null 2>&1 || true
    fi
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
              pi-intercom = {
                command = "${sharedTools.piIntercomMcp}/bin/pi-intercom-mcp";
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
          ExecStartPre = "${seedRemoteControlToken}";
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
