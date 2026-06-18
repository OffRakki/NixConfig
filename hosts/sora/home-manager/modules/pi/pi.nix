{
  config,
  pkgs,
  osConfig,
  lib,
  ...
}: let
  cfg = config.programs.pi-coding-agent;
  piDir = cfg.configDir;
  opendir = ../opencode;
in {
  # Persist pi state directories — sessions, npm packages, git clones
  home.persistence."/persist".directories = [
    ".pi"
    ".local/share/pi"
  ];

  xdg.desktopEntries.pi-coding-agent = {
    name = "Pi";
    genericName = "AI Coding Assistant";
    comment = "Terminal-based AI coding assistant";
    exec = "pi";
    icon = "utilities-terminal";
    terminal = true;
    categories = [
      "Development"
      "ConsoleOnly"
    ];
    type = "Application";
  };

  programs.pi-coding-agent = {
    enable = true;
    context = ./AGENTS.md;

    # Node is needed for npm-based pi package installs.
    # nodejs includes npm in recent nixpkgs versions.
    extraPackages = with pkgs; [
      nodejs
    ];

    settings = {
      defaultProvider = "deepseek";
      defaultModel = "deepseek-v4-flash";
      defaultThinkingLevel = "medium";
      theme = "ciel-cursor";

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

      enabledModels = [
        "deepseek-v4-*"
        "gpt-4o*"
        "gpt-5*"
      ];

      warnings.anthropicExtraUsage = true;

      packages = [
        "npm:pi-web-access"
        "npm:pi-mcp-adapter"
        "npm:pi-subagents"
        "npm:pi-intercom"
      ];
    };

    models = {
      providers = {
        deepseek = {
          baseUrl = "https://api.deepseek.com/v1";
          api = "openai-completions";
          apiKey = "!cat ${osConfig.sops.secrets.deepseekApiKey.path}";
          models = [
            {
              id = "deepseek-v4-flash";
              name = "DeepSeek V4 Flash";
              reasoning = true;
              input = ["text"];
              # cost = {
              #   input = 0.14;
              #   output = 0.28;
              #   cacheRead = 0.014;
              #   cacheWrite = 0.14;
              # };
              contextWindow = 128000;
              maxTokens = 16384;
            }
            {
              id = "deepseek-v4-pro";
              name = "DeepSeek V4 Pro";
              reasoning = true;
              input = ["text"];
              # cost = {
              #   input = 0.55;
              #   output = 2.19;
              #   cacheRead = 0.055;
              #   cacheWrite = 0.55;
              # };
              contextWindow = 128000;
              maxTokens = 32768;
            }
          ];
        };
        openai = {
          baseUrl = "https://api.openai.com/v1";
          api = "openai-completions";
          apiKey = "!cat ${osConfig.sops.secrets.openaiApiKey.path}";
          models = [
            {
              id = "gpt-4o-mini";
              name = "GPT-4o Mini";
              input = ["text"];
              contextWindow = 128000;
              maxTokens = 16384;
            }
            {
              id = "gpt-5.4-mini";
              name = "GPT-5.4 Mini";
              input = ["text"];
              contextWindow = 128000;
              maxTokens = 16384;
            }
          ];
        };
      };
    };
  };

  # Place extensions, skills, prompts, themes, and APPEND_SYSTEM.md into ~/.pi/agent/
  home.file = {
    # Extensions (notify only — providers are defined declaratively in models.json)
    "${piDir}/extensions/notify.ts".source = ./extensions/notify.ts;

    "${piDir}/skills/jujutsu/SKILL.md".source = ./skills/jujutsu/SKILL.md;
    "${piDir}/skills/jujutsu/references".source = ./skills/jujutsu/references;
    "${piDir}/skills/nix/SKILL.md".source = ./skills/nix/SKILL.md;
    "${piDir}/skills/nix-refactor/SKILL.md".source = ./skills/nix-refactor/SKILL.md;
    "${piDir}/skills/linux/SKILL.md".source = ./skills/linux/SKILL.md;
    "${piDir}/skills/invest/SKILL.md".source = ./skills/invest/SKILL.md;
    "${piDir}/skills/personal-tools/SKILL.md".source = ./skills/personal-tools/SKILL.md;
    "${piDir}/skills/screenshot/SKILL.md".source = ./skills/screenshot/SKILL.md;
    "${piDir}/skills/firefly/SKILL.md".source = ./skills/firefly/SKILL.md;
    "${piDir}/skills/firefly/scripts".source = ./skills/firefly/scripts;
    "${piDir}/skills/firefly/resources/auditing.md".source = ./skills/firefly/resources/auditing.md;
    "${piDir}/skills/firefly/resources/btg.md".source = ./skills/firefly/resources/btg.md;
    "${piDir}/skills/firefly/resources/mercado-pago.md".source = ./skills/firefly/resources/mercado-pago.md;
    "${piDir}/skills/firefly/resources/nubank-ofx.md".source = ./skills/firefly/resources/nubank-ofx.md;
    "${piDir}/skills/lumis/SKILL.md".source = ./skills/lumis/SKILL.md;
    "${piDir}/skills/browser/SKILL.md".source = ./skills/browser/SKILL.md;
    "${piDir}/skills/browser/scripts".source = ./skills/browser/scripts;
    "${piDir}/skills/seo/SKILL.md".source = ./skills/seo/SKILL.md;
    "${piDir}/skills/context-curation/SKILL.md".source = ./skills/context-curation/SKILL.md;

    # Pi-specific skill
    "${piDir}/skills/nix-auditor/SKILL.md".source = ./skills/nix-auditor/SKILL.md;

    # Prompts
    "${piDir}/prompts/archive.md".source = ./prompts/archive.md;
    "${piDir}/prompts/free-roam.md".source = ./prompts/free-roam.md;
    "${piDir}/prompts/nix-rebuild.md".source = ./prompts/nix-rebuild.md;

    # Theme
    "${piDir}/themes/ciel-cursor.json".source = ./themes/ciel-cursor.json;

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
}
