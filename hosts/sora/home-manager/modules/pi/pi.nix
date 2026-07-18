{
  pkgs,
  osConfig,
  inputs,
  ...
}: let
  piPackage = pkgs.pi-coding-agent.overrideAttrs (finalAttrs: _: {
    version = "0.80.10";
    src = pkgs.fetchFromGitHub {
      owner = "earendil-works";
      repo = "pi";
      tag = "v${finalAttrs.version}";
      hash = "sha256-Vs/ndHYzFyfN4CjPV2zMYblLXe9IuM13UrPJI1VsZEQ=";
    };
    npmDeps = pkgs.fetchNpmDeps {
      name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
      inherit (finalAttrs) src;
      hash = "sha256-XGvDNH+eilsgc0Z7ITqbitB/9RVc+WuDfCcr1pibNqk=";
    };
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
      ".pi-lens"
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
  systemd.user.services.codex-rate-limits-cache = {
    Unit.Description = "Refresh Codex rate-limit cache for Pi powerline";
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/codex-rate-limits-cache";
      Environment = [
        "PATH=%h/.local/bin:%h/.nix-profile/bin:/etc/profiles/per-user/rakki/bin:/run/current-system/sw/bin"
      ];
    };
  };
  systemd.user.timers.codex-rate-limits-cache = {
    Unit.Description = "Refresh Codex rate-limit cache for Pi powerline";
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
      Unit = "codex-rate-limits-cache.service";
    };
    Install.WantedBy = ["timers.target"];
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
  # Keep ~/.pi/agent/agents mutable: rpiv-pi writes bundled agents and its manifest there.
  # Custom agents remain Nix-sourced, but activation copies them into the writable directory.
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
    # Node is needed for npm-based pi package installs.
    # nodejs includes npm in recent nixpkgs versions.
    # Some Pi packages ship native npm deps (e.g. node-pty), so keep the
    # minimal node-gyp toolchain on PATH for Pi package install/reload.
    # agent-browser is the upstream binary used by pi-agent-browser-native;
    # Chromium is the isolated automation browser it drives via CDP.
    # jujutsu backs automatic working-copy snapshots from jj-snapshot.ts.
    extraPackages = with pkgs; [
      nodejs
      gnumake
      gcc
      jujutsu
      agent-browser
      chromium
      inputs.llm-agents.packages.${pkgs.system}.lean-ctx
    ];
    settings = {
      enableInstallTelemtry = false;
      enableAnalytics = false;
      defaultProvider = "deepseek";
      defaultModel = "deepseek-v4-flash";
      defaultThinkingLevel = "high";
      theme = "piolium-srcery";
      enabledModels = [
        "gpt-5.5"
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
    ".pi/agent/extensions".source = ./extensions;
    ".pi/agent/package-inventory.json".source = ./packages/inventory.json;
    ".pi/agent/skills".source = ./skills;
    ".pi/agent/prompts".source = ./prompts;
    ".pi/agent/themes".source = ./themes;

    ".local/bin/codex-rate-limits-cache" = {
      executable = true;
      text = ''
        #!${pkgs.python3}/bin/python3
        import json
        import os
        import select
        import subprocess
        import sys
        import time
        from pathlib import Path

        request_init = {
            "jsonrpc": "2.0",
            "id": "init-1",
            "method": "initialize",
            "params": {
                "clientInfo": {
                    "name": "ciel-quota-harvester",
                    "title": "Ciel quota harvester",
                    "version": "0",
                },
                "capabilities": {
                    "experimentalApi": True,
                    "requestAttestation": False,
                    "optOutNotificationMethods": [],
                },
            },
        }
        request_limits = {
            "jsonrpc": "2.0",
            "id": "rl-1",
            "method": "account/rateLimits/read",
            "params": None,
        }

        def convert(window):
            if not window:
                return None
            return {
                "usedPercent": window.get("usedPercent"),
                "windowDurationMins": window.get("windowDurationMins"),
                "resetsAt": window.get("resetsAt"),
            }

        def main():
            payload = json.dumps(request_init) + "\n" + json.dumps(request_limits) + "\n"
            proc = subprocess.Popen(
                [os.environ.get("CODEX_BIN", "codex"), "app-server", "--stdio"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

            assert proc.stdin is not None
            assert proc.stdout is not None
            proc.stdin.write(payload)
            proc.stdin.flush()

            poller = select.poll()
            poller.register(proc.stdout, select.POLLIN)
            deadline = time.time() + 45
            result = None
            while time.time() < deadline:
                if not poller.poll(250):
                    if proc.poll() is not None:
                        break
                    continue
                line = proc.stdout.readline()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if msg.get("id") == "rl-1":
                    if "error" in msg:
                        raise RuntimeError(json.dumps(msg["error"]))
                    result = msg.get("result")
                    break

            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()

            if result is None:
                stderr = proc.stderr.read() if proc.stderr is not None else ""
                raise RuntimeError("Codex rate-limit response timed out. " + stderr[-1000:])

            snapshot = (result.get("rateLimitsByLimitId") or {}).get("codex") or result.get("rateLimits") or {}
            primary = snapshot.get("primary")
            secondary = snapshot.get("secondary")
            cache = {
                "updatedAt": int(time.time() * 1000),
                "planType": snapshot.get("planType"),
                "fiveHour": convert(primary),
                "weekly": convert(secondary),
                "rateLimits": {
                    "primary": convert(primary),
                    "secondary": convert(secondary),
                },
                "rateLimitsByLimitId": result.get("rateLimitsByLimitId"),
            }

            out = Path(os.environ.get("CODEX_RATE_LIMIT_CACHE", str(Path.home() / ".cache/codex-rate-limits.json")))
            out.parent.mkdir(parents=True, exist_ok=True)
            tmp = out.with_suffix(out.suffix + ".tmp")
            tmp.write_text(json.dumps(cache, indent=2) + "\n")
            tmp.replace(out)

        if __name__ == "__main__":
            try:
                main()
            except Exception as exc:
                print("codex-rate-limits-cache: " + str(exc), file=sys.stderr)
                sys.exit(1)
      '';
    };
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
