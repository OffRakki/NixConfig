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
      PI_TELEMETRY = 0;
      PI_CACHE_RETENTION = "long";
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
        # Optional/disabled: browser skill currently uses local Playwright helper instead.
        # "npm:pi-chrome"
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
        # Optional/disabled: rarely used extras; left here for easy re-enable.
        # "npm:@ogulcancelik/pi-sketch"
        "npm:@juicesharp/rpiv-pi"
        "npm:@juicesharp/rpiv-todo"
        "npm:@juicesharp/rpiv-args"
        # "npm:@juicesharp/rpiv-btw"
        # "npm:@juicesharp/rpiv-i18n"
        "npm:@juicesharp/rpiv-advisor"
        # "npm:@juicesharp/rpiv-workflow"
        "npm:@juicesharp/rpiv-ask-user-question"

        # May not be that useful (will substitute for a line in context.md)
        #"git:github.com/DietrichGebert/ponytail"
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
              input = [
                "text"
                "image"
              ];
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
    "${piDir}/skills/firefly/resources/mercado-pago.md".source =
      ./skills/firefly/resources/mercado-pago.md;
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

    # MCP servers (Pi-owned global override)
    "${piDir}/mcp.json".text = builtins.toJSON {
      mcpServers = {
        obsidian = {
          command = "npx";
          args = [
            "-y"
            "obsidian-mcp"
            "/home/rakki/sync/geral/Obsidian/Main"
            "/home/rakki/sync/geral/Obsidian/Summaries"
          ];
          lifecycle = "lazy";
        };
      };
    };

    # Keybindings (Helix-style)
    "${piDir}/keybindings.json".text = builtins.toJSON {
      "tui.editor.cursorWordLeft" = [
        "alt+left"
        "alt+b"
      ];
      "tui.editor.cursorWordRight" = [
        "alt+right"
        "alt+f"
      ];
      "tui.editor.deleteWordBackward" = [
        "ctrl+w"
        "alt+backspace"
      ];
      "tui.editor.deleteWordForward" = [
        "alt+d"
        "alt+delete"
      ];
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
    "${piDir}/agents/image-analyzer/image-analyzer.md".source =
      ./agents/image-analyzer/image-analyzer.md;
    "${piDir}/agents/audio-analyzer/audio-analyzer.md".source =
      ./agents/audio-analyzer/audio-analyzer.md;
    "${piDir}/agents/pdf-reader/pdf-reader.md".source = ./agents/pdf-reader/pdf-reader.md;

    # Lucky's personal info appended to system prompt (out-of-store symlink to SOPS secret)
    "${piDir}/APPEND_SYSTEM.md".source =
      config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.lucky-info.path;

    # SOPS-encrypted skill private data (firefly, lumis)
    "${piDir}/skills/firefly/resources/private.md".source =
      config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.skillFireflyPrivate.path;
    "${piDir}/skills/lumis/resources/private.md".source =
      config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.skillLumisPrivate.path;

    # Web search config — Gemini API key + browser cookie access
    "${piDir}/../web-search.json".source =
      config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.webSearchJson.path;
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

  # rpiv-advisor config — declarative advisor model selection.
  home.activation.ensureRpivAdvisorConfig = let
    configFile = pkgs.writeText "rpiv-advisor-config" (builtins.toJSON {
      modelKey = "openai-codex/gpt-5.5";
      effort = "high";
    });
  in ''
    mkdir -p "$HOME/.config/rpiv-advisor"
    cp -f ${configFile} "$HOME/.config/rpiv-advisor/advisor.json"
    chmod 600 "$HOME/.config/rpiv-advisor/advisor.json"
  '';

  # Patch pi-lens to exclude Onedrive FUSE mount (prevents freeze when starting pi from ~/)
  # Onedrive is a FUSE mount via rclone; pi-lens walks into it during startup scans
  # and blocks on __fuse_simple_request, freezing the entire process.
  home.activation.patchPowerlineCostDisplay = ''
    FOOTER_DIR="$HOME/.pi/agent/npm/node_modules/pi-powerline-footer"
    SEG_FILE="$FOOTER_DIR/segments.ts"
    TYPES_FILE="$FOOTER_DIR/types.ts"
    PRESETS_FILE="$FOOTER_DIR/presets.ts"

    if [ -f "$SEG_FILE" ]; then
      ${pkgs.gnused}/bin/sed -i '/^import { readFileSync, statSync } from "node:fs";$/d' "$SEG_FILE"

      if grep -q 'cost.toFixed(2)' "$SEG_FILE"; then
        ${pkgs.gnused}/bin/sed -i 's/cost\.toFixed(2)/cost.toFixed(4)/g' "$SEG_FILE"
      fi

      if false && ! grep -q 'codexLimitsSegment' "$SEG_FILE"; then
        ${pkgs.perl}/bin/perl -0pi -e 's#import \{ hostname as osHostname \} from "node:os";#import { readFileSync, statSync } from "node:fs";\nimport { hostname as osHostname } from "node:os";#' "$SEG_FILE"
        ${pkgs.perl}/bin/perl -0pi -e 's#function formatDuration\(ms: number\): string \{.*?\n\}#function formatDuration(ms: number): string {\n  const seconds = Math.floor(ms / 1000);\n  const minutes = Math.floor(seconds / 60);\n  const hours = Math.floor(minutes / 60);\n\n  if (hours > 0) return `''${hours}h''${minutes % 60}m`;\n  if (minutes > 0) return `''${minutes}m''${seconds % 60}s`;\n  return `''${seconds}s`;\n}\n\ntype CodexLimitWindow = { usedPercent?: number; resetsAt?: number | null; windowDurationMins?: number | null };\ntype CodexRateLimitCache = {\n  updatedAt?: number;\n  fiveHour?: CodexLimitWindow | null;\n  weekly?: CodexLimitWindow | null;\n  rateLimits?: { primary?: CodexLimitWindow | null; secondary?: CodexLimitWindow | null } | null;\n  rateLimitsByLimitId?: Record<string, { primary?: CodexLimitWindow | null; secondary?: CodexLimitWindow | null } | null> | null;\n};\n\nfunction normalizeCodexTimestamp(value: number | null | undefined): number | null {\n  if (!Number.isFinite(value ?? NaN)) return null;\n  return (value as number) < 100000000000 ? (value as number) * 1000 : (value as number);\n}\n\nfunction readCodexRateLimitCache(): CodexRateLimitCache | null {\n  const home = process.env.HOME || process.env.USERPROFILE;\n  if (!home) return null;\n\n  const files = [\n    `''${home}/.cache/codex-rate-limits.json`,\n    `''${home}/.codex/rate-limits.json`,\n    `''${home}/.codex/rate_limits.json`,\n  ];\n\n  for (const file of files) {\n    try {\n      const stat = statSync(file);\n      if (Date.now() - stat.mtimeMs > 15 * 60 * 1000) continue;\n      return JSON.parse(readFileSync(file, "utf8")) as CodexRateLimitCache;\n    } catch {\n      // Missing or malformed cache: hide the segment. The footer render path must stay cheap.\n    }\n  }\n\n  return null;\n}\n\nfunction findCodexWindow(cache: CodexRateLimitCache, minutes: number): CodexLimitWindow | null {\n  const candidates: Array<CodexLimitWindow | null | undefined> = [\n    minutes === 300 ? cache.fiveHour : cache.weekly,\n    cache.rateLimits?.primary,\n    cache.rateLimits?.secondary,\n  ];\n\n  for (const limits of Object.values(cache.rateLimitsByLimitId ?? {})) {\n    candidates.push(limits?.primary, limits?.secondary);\n  }\n\n  return candidates.find((window) => window?.windowDurationMins === minutes && Number.isFinite(window.usedPercent ?? NaN)) ?? null;\n}\n\nfunction formatCodexWindow(label: string, window: CodexLimitWindow | null): string | null {\n  if (!window || !Number.isFinite(window.usedPercent ?? NaN)) return null;\n\n  const used = Math.max(0, Math.min(999, window.usedPercent as number));\n  const resetAt = normalizeCodexTimestamp(window.resetsAt);\n  const reset = resetAt && resetAt > Date.now() ? `/''${formatDuration(resetAt - Date.now())}` : "";\n  return `''${label}''${used.toFixed(0)}%''${reset}`;\n}\n#s' "$SEG_FILE"
        ${pkgs.perl}/bin/perl -0pi -e 's#const costSegment: StatusLineSegment = \{.*?\n\};#const costSegment: StatusLineSegment = {\n  id: "cost",\n  render(ctx) {\n    const { cost } = ctx.usageStats;\n    const usingSubscription = ctx.usingSubscription;\n\n    if (!cost && !usingSubscription) {\n      return { content: "", visible: false };\n    }\n\n    const costDisplay = usingSubscription ? "(sub)" : `$''${cost.toFixed(4)}`;\n    return { content: color(ctx, "cost", costDisplay), visible: true };\n  },\n};\n\nconst codexLimitsSegment: StatusLineSegment = {\n  id: "codex_limits",\n  render(ctx) {\n    if (ctx.model?.id && !ctx.model.id.startsWith("gpt")) {\n      return { content: "", visible: false };\n    }\n\n    const cache = readCodexRateLimitCache();\n    if (!cache) return { content: "", visible: false };\n\n    const fiveHour = findCodexWindow(cache, 300) ?? cache.fiveHour ?? null;\n    const weekly = findCodexWindow(cache, 10080) ?? cache.weekly ?? null;\n    const parts = [formatCodexWindow("5h ", fiveHour), formatCodexWindow("7d ", weekly)].filter(Boolean);\n    if (parts.length === 0) return { content: "", visible: false };\n\n    return { content: color(ctx, "quota", `codex ''${parts.join(" ")}`), visible: true };\n  },\n};#s' "$SEG_FILE"
        ${pkgs.perl}/bin/perl -0pi -e 's#  cost: costSegment,\n#  cost: costSegment,\n  codex_limits: codexLimitsSegment,\n#' "$SEG_FILE"
      fi
    fi

    if [ -f "$TYPES_FILE" ] && ! grep -q '"codex_limits"' "$TYPES_FILE"; then
      ${pkgs.perl}/bin/perl -0pi -e 's#  \| "tokens"\n#  | "tokens"\n  | "quota"\n#' "$TYPES_FILE"
      ${pkgs.perl}/bin/perl -0pi -e 's#  \| "cost"\n#  | "cost"\n  | "codex_limits"\n#' "$TYPES_FILE"
    fi

    if [ -f "$PRESETS_FILE" ]; then
      if ! grep -q 'quota: "warning"' "$PRESETS_FILE"; then
        ${pkgs.perl}/bin/perl -0pi -e 's#  cost: "warning",\n#  cost: "warning",\n  quota: "warning",\n#' "$PRESETS_FILE"
      fi
      if ! grep -q '"codex_limits"' "$PRESETS_FILE"; then
        ${pkgs.perl}/bin/perl -0pi -e 's#"cache_write", "cost", "context_pct"#"cache_write", "cost", "codex_limits", "context_pct"#' "$PRESETS_FILE"
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
