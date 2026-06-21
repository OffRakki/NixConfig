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

  programs.pi-coding-agent = {
    enable = true;
    context = ./context.md;

    # Node is needed for npm-based pi package installs.
    # nodejs includes npm in recent nixpkgs versions.
    # Some Pi packages ship native npm deps (e.g. node-pty), so keep the
    # minimal node-gyp toolchain on PATH for Pi package install/reload.
    extraPackages = with pkgs; [
      nodejs
      gnumake
      gcc
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

      packages = [
        "npm:@vigolium/piolium"
        "npm:pi-drawio"
        "npm:pi-intercom"
        "npm:pi-lean-ctx"
        "npm:pi-lens"
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
        "npm:pi-agent-browser-native"
        "npm:@plannotator/pi-extension"
        "npm:pi-tally"
        "npm:@juicesharp/rpiv-pi"
        "npm:@juicesharp/rpiv-todo"
        "npm:@juicesharp/rpiv-args"
        "npm:@juicesharp/rpiv-ask-user-question"
        # Maybe not the needed as already have browser skill.
        # "npm:pi-chrome"
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
    "${piDir}/skills/ciel-brain/SKILL.md".source = ./skills/ciel-brain/SKILL.md;
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
            "/home/rakki/sync/geral/Obsidian/Ciel"
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
    "${piDir}/prompts/ponder.md".source = ./prompts/ponder.md;

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

  # Patch pi-lens to exclude Onedrive FUSE mount (prevents freeze when starting pi from ~/)
  # Onedrive is a FUSE mount via rclone; pi-lens walks into it during startup scans
  # and blocks on __fuse_simple_request, freezing the entire process.
  home.activation.patchPowerlineCostDisplay = ''
        FOOTER_DIR="$HOME/.pi/agent/npm/node_modules/pi-powerline-footer"
        export SEG_FILE="$FOOTER_DIR/segments.ts"
        export TYPES_FILE="$FOOTER_DIR/types.ts"
        export PRESETS_FILE="$FOOTER_DIR/presets.ts"

        if [ -f "$SEG_FILE" ] || [ -f "$TYPES_FILE" ] || [ -f "$PRESETS_FILE" ]; then
          ${pkgs.python3}/bin/python3 <<'PY'
    from pathlib import Path
    import os

    seg = Path(os.environ["SEG_FILE"])
    types = Path(os.environ["TYPES_FILE"])
    presets = Path(os.environ["PRESETS_FILE"])

    if seg.exists():
        text = seg.read_text()
        text = text.replace("cost.toFixed(2)", "cost.toFixed(4)")
        text = text.replace('return renderCustomSegment(id, ctx);', 'return renderCustomSegment(id as `custom:''${string}`, ctx);')
        text = text.replace('const segment = SEGMENTS[id];', 'const segment = SEGMENTS[id as BuiltinStatusLineSegmentId];')
        if "formatContextTokens" not in text:
            text = text.replace(
                """function formatDuration(ms: number): string {""",
                """function formatContextTokens(n: number): string {
      if (n < 1000) return n.toString();
      if (n < 1000000) {
        const value = n / 1000;
        return `''${Number.isInteger(value) ? value.toFixed(0) : value.toFixed(1)}k`;
      }
      const value = n / 1000000;
      return `''${Number.isInteger(value) ? value.toFixed(0) : value.toFixed(1)}M`;
    }

    function formatDuration(ms: number): string {""",
            )
        text = text.replace(
            '    const text = `''${pct.toFixed(1)}%/''${formatTokens(window)}''${autoIcon}`;',
            '    const used = Math.round((pct / 100) * window);\n    const text = `''${formatContextTokens(used)}/''${formatContextTokens(window)}''${autoIcon}`;',
        )
        if "codexLimitsSegment" not in text:
            text = text.replace(
                'import { hostname as osHostname } from "node:os";',
                'import { readFileSync, statSync } from "node:fs";\nimport { hostname as osHostname } from "node:os";',
            )
            marker = "// ═══════════════════════════════════════════════════════════════════════════\n// Segment Implementations"
            helper = """

    type CodexLimitWindow = { usedPercent?: number; resetsAt?: number | null; windowDurationMins?: number | null };
    type CodexRateLimitCache = {
      fiveHour?: CodexLimitWindow | null;
      weekly?: CodexLimitWindow | null;
      rateLimits?: { primary?: CodexLimitWindow | null; secondary?: CodexLimitWindow | null } | null;
      rateLimitsByLimitId?: Record<string, { primary?: CodexLimitWindow | null; secondary?: CodexLimitWindow | null } | null> | null;
    };

    function normalizeCodexTimestamp(value: number | null | undefined): number | null {
      if (!Number.isFinite(value ?? NaN)) return null;
      return (value as number) < 100000000000 ? (value as number) * 1000 : (value as number);
    }

    function readCodexRateLimitCache(): CodexRateLimitCache | null {
      const home = process.env.HOME || process.env.USERPROFILE;
      if (!home) return null;

      const files = [
        home + "/.cache/codex-rate-limits.json",
        home + "/.codex/rate-limits.json",
        home + "/.codex/rate_limits.json",
      ];

      for (const file of files) {
        try {
          const stat = statSync(file);
          if (Date.now() - stat.mtimeMs > 15 * 60 * 1000) continue;
          return JSON.parse(readFileSync(file, "utf8")) as CodexRateLimitCache;
        } catch {
          // Missing or malformed cache: hide the segment. The footer render path must stay cheap.
        }
      }

      return null;
    }

    function findCodexWindow(cache: CodexRateLimitCache, minutes: number): CodexLimitWindow | null {
      const candidates: Array<CodexLimitWindow | null | undefined> = [
        minutes === 300 ? cache.fiveHour : cache.weekly,
        cache.rateLimits?.primary,
        cache.rateLimits?.secondary,
      ];

      for (const limits of Object.values(cache.rateLimitsByLimitId ?? {})) {
        candidates.push(limits?.primary, limits?.secondary);
      }

      return candidates.find((window) => window?.windowDurationMins === minutes && Number.isFinite(window.usedPercent ?? NaN)) ?? null;
    }

    function formatCodexWindow(label: string, window: CodexLimitWindow | null): string | null {
      if (!window || !Number.isFinite(window.usedPercent ?? NaN)) return null;

      const used = Math.max(0, Math.min(999, window.usedPercent as number));
      const resetAt = normalizeCodexTimestamp(window.resetsAt);
      const reset = resetAt && resetAt > Date.now() ? "/" + formatDuration(resetAt - Date.now()) : "";
      return label + used.toFixed(0) + "%" + reset;
    }
    """
            text = text.replace(marker, helper + "\n" + marker)
            codex_segment = """
    const codexLimitsSegment: StatusLineSegment = {
      id: "codex_limits",
      render(ctx) {
        if (ctx.model?.id && !ctx.model.id.startsWith("gpt")) {
          return { content: "", visible: false };
        }

        const cache = readCodexRateLimitCache();
        if (!cache) return { content: "", visible: false };

        const fiveHour = findCodexWindow(cache, 300) ?? cache.fiveHour ?? null;
        const weekly = findCodexWindow(cache, 10080) ?? cache.weekly ?? null;
        const parts = [formatCodexWindow("5h ", fiveHour), formatCodexWindow("7d ", weekly)].filter(Boolean);
        if (parts.length === 0) return { content: "", visible: false };

        return { content: color(ctx, "quota", "codex " + parts.join(" ")), visible: true };
      },
    };

    """
            text = text.replace('const contextPctSegment: StatusLineSegment = {', codex_segment + 'const contextPctSegment: StatusLineSegment = {')
            text = text.replace("  cost: costSegment,\n", "  cost: costSegment,\n  codex_limits: codexLimitsSegment,\n")
        seg.write_text(text)

    if types.exists():
        text = types.read_text()
        text = text.replace('  | "cost"\n  | "codex_limits"\n  | "tokens"', '  | "cost"\n  | "tokens"')
        if '| "quota"' not in text:
            text = text.replace('  | "tokens"\n', '  | "tokens"\n  | "quota"\n')
        if '  | "codex_limits"\n  | "context_pct"' not in text:
            text = text.replace('  | "cost"\n  | "context_pct"', '  | "cost"\n  | "codex_limits"\n  | "context_pct"')
        types.write_text(text)

    if presets.exists():
        text = presets.read_text()
        if 'quota: "warning"' not in text:
            text = text.replace('  cost: "warning",\n', '  cost: "warning",\n  quota: "warning",\n')
        if '"codex_limits"' not in text:
            text = text.replace('"cache_write", "cost", "context_pct"', '"cache_write", "cost", "codex_limits", "context_pct"')
        presets.write_text(text)
    PY
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
