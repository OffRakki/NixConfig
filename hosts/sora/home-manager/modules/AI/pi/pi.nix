{
  config,
  pkgs,
  osConfig,
  inputs,
  ...
}: let
  sharedTools = import ../shared/tools.nix {
    inherit pkgs inputs;
    ollamaContextLength =
      osConfig.virtualisation.oci-containers.containers.ollama.environment.OLLAMA_CONTEXT_LENGTH or null;
  };
  inherit (sharedTools) nodejs piPackage piPackages rea;
  resources = import ./resources.nix {
    inherit pkgs;
    inherit (sharedTools) reaSkill;
  };
  piw = pkgs.writeShellApplication {
    name = "piw";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jujutsu
      piPackage
    ];
    text = builtins.readFile ./scripts/piw.sh;
  };
in {
  imports = [
    (import ./usage {inherit pkgs nodejs piPackage;})
    ./noctalia.nix
  ];

  home = {
    sessionVariables = {
      PI_SKIP_VERSION_CHECK = true;
      PI_TELEMETRY = 0;
      PI_CACHE_RETENTION = "long";
    };
    packages = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.lean-ctx
      piw
    ];
    persistence."/persist".directories = [
      ".pi"
      ".local/share/pi"
      ".local/share/billion-context"
      ".config/lean-ctx"
      ".local/share/lean-ctx"
      ".codex"
    ];
  };
  # Nix owns updates; retain pi-subagents rather than registering a second delegate.
  xdg.configFile."billion-context/billion-context.json".text = builtins.toJSON {
    autoUpdate = false;
    autoRestartOnUpdate = false;
    advisoryCheck = false;
    pi.subagents = false;
  };
  xdg.desktopEntries.pi-coding-agent = {
    name = "Pi";
    genericName = "AI Coding Assistant";
    comment = "Terminal-based AI coding assistant";
    exec = "kitty --directory /home/rakki/Projects/NixConfig -e pi";
    icon = "utilities-terminal";
    terminal = false;
    categories = [
      "Development"
      "ConsoleOnly"
    ];
    type = "Application";
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
  home.activation.setPiWidgetPlacement = ''
    buddy="$HOME/.pi/agent/pi-buddy/config.json"
    mkdir -p "$(dirname "$buddy")"

    update_pi_widget() (
      file="$1"
      filter="$2"
      tmp="$(mktemp "$file.XXXXXX")" || exit 1
      trap 'rm -f "$tmp"' EXIT

      if [ -e "$file" ] || [ -L "$file" ]; then
        if ! ${pkgs.jq}/bin/jq -se \
          'if length == 1 and (.[0] | type == "object") then .[0] else error("Expected one JSON object") end | '"$filter" \
          "$file" > "$tmp"; then
          printf 'Cannot update Pi settings; preserving %s\n' "$file" >&2
          exit 1
        fi
      else
        ${pkgs.jq}/bin/jq -n "$filter" > "$tmp" || exit 1
      fi
      mv -- "$tmp" "$file"
    )

    update_pi_widget "$buddy" '.placement = "belowEditor" | .header = false'
    # Writable runtime config: extension commands use atomic read-latest updates.
    # Only these two billing routes may enter automatic rotation.
    update_pi_widget "$HOME/.pi/agent/provider-failover.json" '. + ${builtins.toJSON {
      enabled = true;
      autoContinue = true;
      autoDiscover = false;
      autoDiscoverModels = false;
      childProxy = false;
      antigravitySubscription = false;
      followLastSuccessfulModel = false;
      contextGuard = false;
      recoverLargeContext = false;
      debugLog = false;
      # Avoid awaited quota-network probes at startup; manual limits refresh still works.
      showUsage = false;
      fallbacks = [
        "openai-codex/gpt-6.2-sol"
        "openai/gpt-6.2-sol"
      ];
    }}'
  '';
  # Keep custom agents Nix-sourced while leaving the runtime directory writable
  # for Pi's agent-management commands.
  home.activation.syncPiCustomAgents = ''
    src=${resources.agents}
    dst="$HOME/.pi/agent/agents"
    manifest="$dst/.nix-managed-custom-agents"

    if [ -L "$dst" ]; then
      rm -f "$dst"
    fi
    mkdir -p "$dst"

    tmp="$(${pkgs.coreutils}/bin/mktemp)"
    (cd "$src" && ${pkgs.findutils}/bin/find -L . -type f | ${pkgs.gnused}/bin/sed 's#^\./##' | ${pkgs.coreutils}/bin/sort) > "$tmp"

    if [ -f "$manifest" ]; then
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        case "$rel" in
          /*|*..*|*//*|*\\*) continue ;;
        esac
        if ! ${pkgs.gnugrep}/bin/grep -Fxq "$rel" "$tmp"; then
          rm -f "$dst/$rel"
        fi
      done < "$manifest"
    fi

    while IFS= read -r rel; do
      mkdir -p "$dst/$(${pkgs.coreutils}/bin/dirname "$rel")"
      cp -f "$src/$rel" "$dst/$rel"
    done < "$tmp"

    cp -f "$tmp" "$manifest"
    rm -f "$tmp"
  '';

  programs.pi-coding-agent = {
    enable = true;
    package = piPackage;
    context = resources.context;
    # Node provides npx for the Obsidian MCP server.
    # agent-browser is the upstream binary used by pi-agent-browser-native;
    # Chromium is the isolated automation browser it drives via CDP.
    # jujutsu backs automatic working-copy snapshots from jj-snapshot.ts.
    extraPackages =
      [nodejs rea]
      ++ (with pkgs; [
        libnotify
        jujutsu
        agent-browser
        chromium
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.lean-ctx
      ]);
    settings = {
      enableInstallTelemtry = false;
      enableAnalytics = false;
      defaultProvider = "openai-codex";
      defaultModel = "gpt-6.2-sol";
      defaultThinkingLevel = "medium";
      cacheWarming = "idle";
      showCacheMissNotices = true;
      theme = "noctalia";
      enabledModels = [
        "gpt-6*"
        "gpt-5.6*"
        "deepseek*"
        "anthropic/*"
        "ollama/*"
      ];
      quietStartup = true;
      collapseChangelog = true;
      compaction = {
        enabled = true;
        reserveTokens = 16384;
        keepRecentTokens = 20000;
        modelOverrides = {
          "ollama/qwen3.5:9b" = {
            reserveTokens = 8192;
            keepRecentTokens = 8192;
          };
          "ollama/qwen3.8:27b-q4_K_M" = {
            reserveTokens = 8192;
            keepRecentTokens = 8192;
          };
        };
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
      powerline = true;
      breadcrumb = "inner";
      footer = true;
      # Keep the existing Sakura header; Powerline owns only the editor/footer.
      header = false;
      header-info = false;
      subagents.agentOverrides = {
        oracle.thinking = "medium";
        planner.thinking = "medium";
        reviewer.thinking = "medium";
        worker.thinking = "medium";
      };
      packages = piPackages.paths;
    };
    models = {
      providers = {
        anthropic.apiKey = "!cat ${osConfig.sops.secrets.anthropicApiKey.path}";
        openai.apiKey = "!cat ${osConfig.sops.secrets.openaiApiKey.path}";
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
  home.file = {
    # Discovery extensions can atomically replace models.json with a regular file.
    # Reassert Nix ownership without failing on an existing .backup file.
    "${config.programs.pi-coding-agent.configDir}/models.json".force = true;
    ".pi/agent/package-inventory.json".source = ./packages/inventory.json;
    ".pi/agent/pi-ollama.json".text = builtins.toJSON {
      baseUrl = "http://127.0.0.1:11434";
      globalModelDefaults = {
        # Discovery reports the trained maximum, not Ollama's allocated window.
        contextWindow = builtins.fromJSON osConfig.virtualisation.oci-containers.containers.ollama.environment.OLLAMA_CONTEXT_LENGTH;
        maxTokens = 8192;
        compat = {
          supportsDeveloperRole = false;
          supportsReasoningEffort = false;
          maxTokensField = "max_tokens";
        };
      };
    };
    ".pi/agent/skills".source = resources.skills;
    ".pi/agent/prompts".source = resources.prompts;
    ".pi/agent/themes".source = ./themes;
    # Browser automation config (pi-agent-browser-native)
    ".pi/config/pi-agent-browser-native/config.json".text = builtins.toJSON {
      version = 1;
      browser.executablePath = "${pkgs.chromium}/bin/chromium";
    };

    # MCP servers (Pi-owned global override)
    ".pi/agent/mcp.json".text = builtins.toJSON {
      mcpServers = {
        auvp = {
          url = "https://financas-api.auvp.com.br/mcp";
          headers."x-api-key" = "!${pkgs.coreutils}/bin/cat ${osConfig.sops.secrets.auvpApiKey.path}";
          exposure = "codemode";
          description = "AUVP financial data and investment research.";
        };
        rea = {
          command = "${rea}/bin/rea";
          args = ["mcp"];
          exposure = "codemode";
          description = "Reverse-engineer shipped binaries, JavaScript/Electron applications, and artifacts with evidence-backed inspection.";
          timeout = 360;
          # REA 6.8 only supports full/off; avoid its oversized output-schema catalog.
          env.REA_MCP_OUTPUT_SCHEMA_PROFILE = "off";
        };
        obsidian = {
          command = "npx";
          args = [
            "-y"
            "obsidian-mcp"
            "/home/rakki/sync/geral/Obsidian/Ciel"
          ];
          lifecycle = "lazy";
        };
      };
    };

    # Keybindings (Helix-style)
    ".pi/agent/keybindings.json".text = builtins.toJSON {
      "app.editor.external" = "alt+e";
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
  };
}
