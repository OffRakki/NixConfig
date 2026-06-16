{
  config,
  pkgs,
  osConfig,
  lib,
  ...
}: let
  inherit (lib) getExe;

  attachScript = pkgs.writeShellScript "opencode-attach" ''
    OPENCODE_SERVER_PASSWORD=$(cat ${osConfig.sops.secrets.opencodeServerPass.path}) \
      OPENCODE_SERVER_USERNAME=rakki \
      exec ${pkgs.opencode}/bin/opencode attach http://localhost:4096
  '';

  ciel-notify = pkgs.writeShellScriptBin "ciel-notify" (builtins.readFile ./bin/notify.sh);
  ciel-restart-server = pkgs.writeShellScriptBin "ciel-restart-server" (builtins.readFile ./bin/restart-server.sh);

  heartbeatScript = "${config.home.homeDirectory}/sync/geral/Ciel/bin/heartbeat.sh";
in {
  home.persistence."/persist".directories = [
    ".local/share/opencode"
    ".config/opencode"
  ];

  xdg.desktopEntries.opencode = {
    name = "Opencode";
    genericName = "AI CLI Assistant";
    comment = "Terminal-based AI coding assistant";
    exec = "${attachScript}";
    icon = "terminal";
    terminal = true;
    categories = [
      "Development"
      "ConsoleOnly"
    ];
    mimeType = ["x-scheme-handler/opencode"];
    type = "Application";
  };
  xdg.mimeApps.defaultApplications."x-scheme-handler/opencode" = "opencode.desktop";

  systemd.user.services.opencode-server = {
    Unit = {
      Description = "OpenCode Web Server";
      After = ["network.target"];
    };
    Service = {
      Type = "simple";
      Environment = "OPENCODE_SERVER_USERNAME=rakki";
      ExecStart = "${pkgs.bash}/bin/bash -c 'OPENCODE_SERVER_PASSWORD=$(cat ${osConfig.sops.secrets.opencodeServerPass.path}) exec ${pkgs.opencode}/bin/opencode serve --hostname 0.0.0.0 --port 4096'";
      Restart = "on-failure";
      RestartSec = "5";
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };

  programs.opencode = {
    enable = true;
    context = ./context.md;
    skills = {
      context-curation = ./skills/context-curation;
      invest = ./skills/invest;
      jujutsu = ./skills/jujutsu;
      linux = ./skills/linux;
      nix = ./skills/nix;
      nix-refactor = ./skills/nix-refactor;
      opencode-session = ./skills/opencode-session;
      personal-tools = ./skills/personal-tools;
      seo = ./skills/seo;
    };
    agents = {
      image-analyzer = ./agents/image-analyzer/image-analyzer.md;
      audio-analyzer = ./agents/audio-analyzer/audio-analyzer.md;
      nix-auditor = ./agents/nix-auditor/nix-auditor.md;
    };
    tui = {
      theme = "cursor";
      keybinds = {
        editor_open = "alt+e";
      };
    };
    settings = {
      permission = "allow";
      autoupdate = false;
      model = "deepseek/deepseek-v4-flash";
      provider = {
        deepseek = {
          name = "DeepSeek";
          npm = "@ai-sdk/openai-compatible";
          options = {
            apiKey = "{file:${osConfig.sops.secrets.deepseekApiKey.path}}";
            baseURL = "https://api.deepseek.com/v1";
          };
          models = {
            "deepseek-v4-flash" = {
              name = "DeepSeek V4 Flash";
              variant = "max";
              supportsTools = true;
            };
            "deepseek-v4-pro" = {
              name = "DeepSeek V4 Pro";
              supportsTools = true;
            };
          };
        };
        openai = {
          name = "OpenAI";
          npm = "@ai-sdk/openai";
          options = {
            apiKey = "{file:${osConfig.sops.secrets.openaiApiKey.path}}";
          };
          models = {
            "gpt-4o-mini" = {
              name = "GPT-4o Mini";
              supportsTools = true;
            };
            "gpt-5.4-mini" = {
              name = "GPT-5.4 Mini";
              supportsTools = true;
            };
          };
        };
      };
      command = {
        archive = {
          description = "Quick-save summary to Obsidian";
          agent = "vault-archivist";
          template = "Summarize this entire chat session into a beautiful markdown note and save it to the /home/rakki/sync/Obsidian/Summaries folder.";
        };
      };
    };
  };

  home.packages = [ciel-notify ciel-restart-server];

  systemd.user.services.ciel-heartbeat = {
    Unit = {
      Description = "Ciel's heartbeat — room maintenance and autonomous summoning";
    };
    Service = {
      Type = "oneshot";
      ExecStart = heartbeatScript;
      Environment = ["DISPLAY=:0" "WAYLAND_DISPLAY=wayland-1"];
    };
  };

  systemd.user.timers.ciel-heartbeat = {
    Unit.Description = "Ciel's periodic heartbeat";
    Timer = {
      OnCalendar = "*:0/2";
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
