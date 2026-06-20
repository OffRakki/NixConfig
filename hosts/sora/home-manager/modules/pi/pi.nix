{
  config,
  pkgs,
  osConfig,
  inputs,
  ...
}: let
  cfg = config.programs.pi-coding-agent;
  piDir = cfg.configDir;
in {
  # Persist pi state directories — sessions, npm packages, git clones and sets pi to offline mode (no update/telemetry)
  home = {
    sessionVariables = {
      PI_SKIP_VERSION_CHECK = 1;
    };
    packages = [
      inputs.llm-agents.packages.${pkgs.system}.lean-ctx
    ];
    persistence."/persist".directories = [
      ".pi"
      ".local/share/pi"
      ".config/lean-ctx"
      ".local/share/lean-ctx"
      ".pi-lens"
    ];
  };

  xdg.desktopEntries.pi-coding-agent = {
    name = "Pi";
    genericName = "AI Coding Assistant";
    comment = "Terminal-based AI coding assistant";
    exec = "kitty --override background_opacity=1.0 --override background_blur=0 --directory /home/rakki/Projects/NixConfig -e pi";
    icon = "utilities-terminal";
    terminal = false;
    categories = [
      "Development"
      "ConsoleOnly"
    ];
    type = "Application";
  };

  programs.pi-coding-agent = {
    enable = true;
    context = ./context.md;

    # Node is needed for npm-based pi package installs.
    # nodejs includes npm in recent nixpkgs versions.
    extraPackages = with pkgs; [
      nodejs
      inputs.llm-agents.packages.${pkgs.system}.lean-ctx
    ];

    settings = {
      defaultProvider = "openai-codex";
      defaultModel = "gpt-5.5";
      defaultThinkingLevel = "low";
      theme = "gruvbox-dark-hard";
      enabledModels = [
        "gpt*"
        "deepseek*"
      ];

      quietStartup = false;
      collapseChangelog = true;

      compaction = {
        enabled = true;
        reserveTokens = 16384;
        keepRecentTokens = 20000;
      };

      retry = {
        enabled = true;
        maxRetries = 3;
        baseDelayMs = 2000;
        provider = {
          timeoutMs = 3600000;
          maxRetries = 0;
          maxRetryDelayMs = 60000;
        };
      };
      branchSummary = {
        skipPrompt = true;
        reserveTokens = 8192;
      };
      treeFilterMode = "no-tools";
      terminal = {
        showImages = true;
        imageWidthCells = 80;
      };
      images = {
        autoResize = true;
        blockImages = false;
      };
      warnings.anthropicExtraUsage = true;
      powerline = {
        preset = "nerd";
      };

      packages = [
        "npm:@vigolium/piolium"
        "npm:pi-drawio"
        "npm:pi-intercom"
        "npm:pi-lean-ctx"
        "npm:pi-lens"
        "npm:pi-chrome"
        "npm:pi-simplify"
        "npm:pi-namespace"
        "npm:pi-ask-user"
        "npm:pi-web-access"
        "npm:pi-mcp-adapter"
        "npm:pi-markdown-preview"
        "npm:pi-powerline-footer"
        "npm:pi-hermes-memory"
        "npm:pi-invisible-continue"
        "npm:pi-subagents"
        "npm:@ogulcancelik/pi-sketch"
        "npm:@tintinweb/pi-subagents"
        "npm:@juicesharp/rpiv-pi"
        "npm:@juicesharp/rpiv-todo"
        "npm:@juicesharp/rpiv-args"
        "npm:@juicesharp/rpiv-btw"
        "npm:@juicesharp/rpiv-i18n"
        "npm:@juicesharp/rpiv-advisor"
        "npm:@juicesharp/rpiv-workflow"
        "npm:@juicesharp/rpiv-ask-user-question"

        "git:github.com/DietrichGebert/ponytail"
      ];
    };

    models = {
      providers = {
        hyper = {
          baseUrl = "https://hyper.charm.land/v1";
          apiKey = "!cat ${osConfig.sops.secrets.hyperApiKey.path}";
          api = "openai-completions";
          compat.supportsDeveloperRole = false;
          models = [
            {
              id = "deepseek-v4-flash";
              name = "DeepSeek V4 Flash";
              reasoning = true;
              input = ["text" "image"];
              contextWindow = 1000000;
              maxTokens = 384000;
              cost = {
                input = 0;
                output = 0;
                cacheRead = 0;
                cacheWrite = 0;
              };
              thinkingLevelMap = {
                minimal = null;
                low = null;
                medium = null;
                high = "high";
                xhigh = "xhigh";
              };
            }
            {
              id = "deepseek-v4-pro";
              name = "DeepSeek V4 Pro";
              reasoning = true;
              input = ["text"];
              contextWindow = 1000000;
              maxTokens = 384000;
              cost = {
                input = 0;
                output = 0;
                cacheRead = 0;
                cacheWrite = 0;
              };
              thinkingLevelMap = {
                minimal = null;
                low = null;
                medium = null;
                high = "high";
                xhigh = "xhigh";
              };
            }
          ];
        };
      };
    };
  };

  # Place models, extensions, skills, prompts, themes, and APPEND_SYSTEM.md into ~/.pi/agent/
  home.file = {
    # Extensions (notify only)
    "${piDir}/extensions/notify.ts".source = ./extensions/notify.ts;

    "${piDir}/skills/firefly/SKILL.md".source = ./skills/firefly/SKILL.md;
    "${piDir}/skills/firefly/scripts".source = ./skills/firefly/scripts;
    "${piDir}/skills/firefly/resources/auditing.md".source = ./skills/firefly/resources/auditing.md;
    "${piDir}/skills/firefly/resources/btg.md".source = ./skills/firefly/resources/btg.md;
    "${piDir}/skills/firefly/resources/mercado-pago.md".source = ./skills/firefly/resources/mercado-pago.md;
    "${piDir}/skills/firefly/resources/nubank-ofx.md".source = ./skills/firefly/resources/nubank-ofx.md;
    "${piDir}/skills/jujutsu/SKILL.md".source = ./skills/jujutsu/SKILL.md;
    "${piDir}/skills/jujutsu/references".source = ./skills/jujutsu/references;
    "${piDir}/skills/improve/SKILL.md".source = ./skills/improve/SKILL.md;
    "${piDir}/skills/improve/references".source = ./skills/improve/references;
    "${piDir}/skills/nix/SKILL.md".source = ./skills/nix/SKILL.md;
    "${piDir}/skills/nix-refactor/SKILL.md".source = ./skills/nix-refactor/SKILL.md;
    "${piDir}/skills/linux/SKILL.md".source = ./skills/linux/SKILL.md;
    "${piDir}/skills/invest/SKILL.md".source = ./skills/invest/SKILL.md;
    "${piDir}/skills/personal-tools/SKILL.md".source = ./skills/personal-tools/SKILL.md;
    "${piDir}/skills/screenshot/SKILL.md".source = ./skills/screenshot/SKILL.md;
    "${piDir}/skills/lumis/SKILL.md".source = ./skills/lumis/SKILL.md;
    "${piDir}/skills/browser/SKILL.md".source = ./skills/browser/SKILL.md;
    "${piDir}/skills/browser/scripts".source = ./skills/browser/scripts;
    "${piDir}/skills/seo/SKILL.md".source = ./skills/seo/SKILL.md;
    "${piDir}/skills/context-curation/SKILL.md".source = ./skills/context-curation/SKILL.md;
    "${piDir}/skills/security-sweep/SKILL.md".source = ./skills/security-sweep/SKILL.md;
    "${piDir}/skills/pi-tools/SKILL.md".source = ./skills/pi-tools/SKILL.md;

    # Pi-specific skill
    "${piDir}/skills/nix-auditor/SKILL.md".source = ./skills/nix-auditor/SKILL.md;

    # Keybindings (Helix-style)
    "${piDir}/keybindings.json".text = builtins.toJSON {
      "tui.editor.cursorWordLeft" = ["alt+left" "alt+b"];
      "tui.editor.cursorWordRight" = ["alt+right" "alt+f"];
      "tui.editor.deleteWordBackward" = ["ctrl+w" "alt+backspace"];
      "tui.editor.deleteWordForward" = ["alt+d" "alt+delete"];
      "tui.input.submit" = "enter";
      "tui.input.newLine" = "shift+enter";
      "app.model.select" = "ctrl+l";
      "app.model.cycleForward" = "ctrl+p";
      "app.model.cycleBackward" = "shift+ctrl+p";
      "app.thinking.toggle" = "ctrl+t";
      "app.session.rename" = "ctrl+r";
      "app.session.deleteNoninvasive" = "ctrl+backspace";
      "app.tools.expand" = "ctrl+o";
    };

    # Prompts
    "${piDir}/prompts/archive.md".source = ./prompts/archive.md;
    "${piDir}/prompts/nix-rebuild.md".source = ./prompts/nix-rebuild.md;
    "${piDir}/prompts/nix-audit.md".source = ./prompts/nix-audit.md;
    "${piDir}/prompts/commit.md".source = ./prompts/commit.md;

    # Themes
    "${piDir}/themes/catppuccin-mocha.json".source = ./themes/catppuccin-mocha.json;
    "${piDir}/themes/ciel-cursor.json".source = ./themes/ciel-cursor.json;
    "${piDir}/themes/gruvbox-dark-hard.json".source = ./themes/gruvbox-dark-hard.json;

    # Agents (subagent definitions — auto-discovered by pi-subagents)
    "${piDir}/agents/nix-auditor.md".source = ./agents/nix-auditor.md;
    "${piDir}/agents/image-analyzer/image-analyzer.md".source = ./agents/image-analyzer/image-analyzer.md;
    "${piDir}/agents/audio-analyzer/audio-analyzer.md".source = ./agents/audio-analyzer/audio-analyzer.md;
    "${piDir}/agents/pdf-reader/pdf-reader.md".source = ./agents/pdf-reader/pdf-reader.md;

    # Lucky's personal info appended to system prompt (out-of-store symlink to SOPS secret)
    "${piDir}/APPEND_SYSTEM.md".source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.lucky-info.path;

    # SOPS-encrypted skill private data (firefly, lumis)
    "${piDir}/skills/firefly/resources/private.md".source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.skillFireflyPrivate.path;
    "${piDir}/skills/lumis/resources/private.md".source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.skillLumisPrivate.path;

    # Web search config — Gemini API key + browser cookie access
    "${piDir}/../web-search.json".source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.webSearchJson.path;
  };

  # lean-ctx config — disable shell allowlist so pi can run any command
  home.activation.ensureLeanCtxConfig = let
    configFile = pkgs.writeText "lean-ctx-config" ''
      shell_allowlist = []
    '';
  in ''
    mkdir -p "$HOME/.config/lean-ctx"
    cp -f ${configFile} "$HOME/.config/lean-ctx/config.toml"
  '';

  # Patch pi-lens to exclude Onedrive FUSE mount (prevents freeze when starting pi from ~/)
  # Onedrive is a FUSE mount via rclone; pi-lens walks into it during startup scans
  # and blocks on __fuse_simple_request, freezing the entire process.
  home.activation.patchPowerlineCostDisplay = ''
    SEG_FILE="$HOME/.pi/agent/npm/node_modules/pi-powerline-footer/segments.ts"
    if [ -f "$SEG_FILE" ]; then
      if grep -q 'cost.toFixed(2)' "$SEG_FILE"; then
        ${pkgs.gnused}/bin/sed -i 's/cost\.toFixed(2)/cost.toFixed(4)/g' "$SEG_FILE"
      fi
    fi
  '';

  # Patch pi-lens EXCLUDED_DIRS to skip Onedrive FUSE mount
  home.activation.patchLensExcludedDirs = ''
    FILE="$HOME/.pi/agent/npm/node_modules/pi-lens/dist/clients/file-utils.js"
    if [ -f "$FILE" ]; then
      if ! grep -q '"Onedrive"' "$FILE"; then
        ${pkgs.gnused}/bin/sed -i '/"vendors"/a\    "Onedrive", // FUSE mount (rclone) — blocks __fuse_simple_request on startup scan' "$FILE"
      fi
    fi
  '';
}
