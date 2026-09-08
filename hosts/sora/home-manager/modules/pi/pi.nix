{
  pkgs,
  osConfig,
  inputs,
  ...
}: let
  piPackage = pkgs.pi-coding-agent.overrideAttrs (finalAttrs: _: {
    version = "0.85.1";
    src = pkgs.fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${finalAttrs.version}/pi-${finalAttrs.version}-source.tar.gz";
      hash = "sha256-9+yS7U97dTaRmDmKNCFzLq5AUYOXFFC8dMuFRPQtAso=";
    };
    npmDeps = pkgs.fetchNpmDeps {
      name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
      inherit (finalAttrs) src;
      hash = "sha256-jzlsZIQzfl1FCZZ5//dHFWwMfBZQ4nRD6KB4HHifPqE=";
    };
    buildPhase = ''
      runHook preBuild
      npm run build:offline
      runHook postBuild
    '';
    postInstall = ''
      local nm="$out/lib/node_modules/pi-monorepo/node_modules"
      for ws in @earendil-works/chord:packages/chord \
                @earendil-works/pi-ai:packages/ai \
                @earendil-works/pi-agent-core:packages/agent \
                @earendil-works/pi-client:packages/client \
                @earendil-works/pi-protocol:packages/protocol \
                @earendil-works/pi-telemetry:packages/telemetry \
                @earendil-works/pi-tui:packages/tui; do
        IFS=: read -r pkg src <<< "$ws"
        rm "$nm/$pkg"
        cp -r "$src" "$nm/$pkg"
      done
      find "$nm" -type l -lname '*/packages/*' -delete
      find "$nm/.bin" -xtype l -delete
    '';
  });
  piPackages = import ./packages {inherit piPackage pkgs;};
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
  home = {
    sessionVariables = {
      PI_SKIP_VERSION_CHECK = true;
      PI_TELEMETRY = 0;
      PI_CACHE_RETENTION = "long";
    };
    packages = [
      inputs.llm-agents.packages.${pkgs.system}.lean-ctx
      piw
    ];
    persistence."/persist".directories = [
      ".pi"
      ".local/share/pi"
      ".config/lean-ctx"
      ".local/share/lean-ctx"
      ".codex"
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
    powerbar="$HOME/.pi/agent/settings-extensions.json"
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
    update_pi_widget "$powerbar" '(.powerbar //= {}) | .powerbar.placement = "belowEditor"'
  '';
  # Keep custom agents Nix-sourced while leaving the runtime directory writable
  # for Pi's agent-management commands.
  home.activation.syncPiCustomAgents = ''
    src=${./agents}
    dst="$HOME/.pi/agent/agents"
    manifest="$dst/.nix-managed-custom-agents"

    if [ -L "$dst" ]; then
      rm -f "$dst"
    fi
    mkdir -p "$dst"

    tmp="$(${pkgs.coreutils}/bin/mktemp)"
    (cd "$src" && ${pkgs.findutils}/bin/find . -type f | ${pkgs.gnused}/bin/sed 's#^\./##' | ${pkgs.coreutils}/bin/sort) > "$tmp"

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
    context = ./context.md;
    # Node provides npx for the Obsidian MCP server.
    # agent-browser is the upstream binary used by pi-agent-browser-native;
    # Chromium is the isolated automation browser it drives via CDP.
    # jujutsu backs automatic working-copy snapshots from jj-snapshot.ts.
    extraPackages = with pkgs; [
      nodejs
      jujutsu
      agent-browser
      chromium
      inputs.llm-agents.packages.${pkgs.system}.lean-ctx
    ];
    settings = {
      enableInstallTelemtry = false;
      enableAnalytics = false;
      defaultProvider = "openai-codex";
      defaultModel = "gpt-5.6-sol";
      defaultThinkingLevel = "medium";
      theme = "sakura-macaron";
      enabledModels = [
        "gpt-6*"
        "gpt-5.6*"
        "deepseek*"
      ];
      quietStartup = true;
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
      subagents.agentOverrides = {
        oracle.thinking = "medium";
        planner.thinking = "medium";
        reviewer.thinking = "medium";
        worker.thinking = "medium";
      };
      # Empty jump bindings suppress powerline's scroll-away navigation card.
      powerlineShortcuts = {
        jumpChatBottom = null;
        jumpPreviousUserMessage = null;
        jumpNextUserMessage = null;
        jumpPreviousLlmMessage = null;
        jumpNextLlmMessage = null;
      };
      packages = piPackages.paths;
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
  home.file = {
    ".pi/agent/package-inventory.json".source = ./packages/inventory.json;
    ".pi/agent/skills".source = ./skills;
    ".pi/agent/prompts".source = ./prompts;
    ".pi/agent/themes".source = ./themes;
    # Browser automation config (pi-agent-browser-native)
    ".pi/config/pi-agent-browser-native/config.json".text = builtins.toJSON {
      version = 1;
      browser.executablePath = "${pkgs.chromium}/bin/chromium";
    };

    # MCP servers (Pi-owned global override)
    ".pi/agent/mcp.json".text = builtins.toJSON {
      mcpServers = {
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
