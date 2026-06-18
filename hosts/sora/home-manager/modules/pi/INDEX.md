# Pi Module Index — On-Demand Reference

---

## Entry Points

| File | Imports |
|------|---------|
| `default.nix` | `./pi.nix` |
| `pi.nix` | `programs.pi-coding-agent`, `home.file` (extensions, skills, prompts, themes, agents), `xdg.desktopEntries`, `xdg.configFile` (SOPS skill private data) |

---

## File Index

| File | Keywords |
|------|----------|
| `pi.nix` | pi-coding-agent, deepseek-provider, openai, settings, models, compaction, retry, theme(ciel-cursor), packages(pi-web-access,pi-mcp-adapter,pi-subagents,pi-intercom), persistence(.pi), sops-secrets, home.file(symlinked-skills), home.file(agents), home.file(individual-resource-files), APPEND_SYSTEM.md, xdg.desktopEntries |
| `pi.nix` | pi-coding-agent, deepseek-provider, openai, settings, models, compaction, retry, branchSummary, treeFilterMode, terminal, images, theme(ciel-cursor), packages(pi-web-access,pi-mcp-adapter,pi-subagents,pi-intercom,pi-hermes-memory,pi-lean-ctx,pi-powerline-footer,pi-lens,rpiv-args,rpiv-btw,pi-markdown-preview,pi-chrome), persistence(.pi), sops-secrets, home.file(symlinked-skills), home.file(agents), home.file(keybindings), home.file(individual-resource-files), APPEND_SYSTEM.md, xdg.desktopEntries |
| `models.json (generated in pi.nix)` | custom-provider, hyper-charm-land, openai-completions, 18-models, deepseek-v4-flash, deepseek-v4-pro, qwen3.6, qwen3.7, kimi-k2.5, kimi-k2.6, glm-5, glm-5.1, gemma-4, llama-3.3, llama-4, minimax-m2.7, gpt-oss-120b, qwen3-coder, qwen3-next |
| `context.md` | Ciel-personality, pi-specific tool-discipline(read,bash,edit,write,grep,find,ls), skill-routing, nix-managed, sops-refs, speak-up-rule, read-before-write, keep-index-in-sync, subagents-list |
| `extensions/notify.ts` | pi-extension, desktop-notifications, notify-send, agent-end-event, /notify-command |
| `prompts/archive.md` | pi-prompt, session-summary, obsidian-save, frontmatter |
| `prompts/nix-rebuild.md` | pi-prompt, nixos-rebuild, jj-sync, nh-os-switch |
| `prompts/nix-audit.md` | pi-prompt, nix-auditor, flake-audit, dead-code, redundancy |
| `prompts/commit.md` | pi-prompt, jj-commit, describe, commit-message |
| `themes/ciel-cursor.json` | pi-theme, catppuccin-mocha, cursor-theme-colors, 51-tokens |

### Agents

| File | Keywords |
|------|----------|
| `agents/nix-auditor.md` | pi-agent, nix-config-audit, read-only, structured-report, dead-code, redundancy |
| `agents/image-analyzer/image-analyzer.md` | pi-agent, image-analysis, vision, layout, text-extraction, UI-description |
| `agents/audio-analyzer/audio-analyzer.md` | pi-agent, audio-analysis, ffprobe, whisper-cli, transcription, en-pt |
| `agents/pdf-reader/pdf-reader.md` | pi-agent, pdf-analysis, pdftoppm, pdftotext, image-analyzer-delegate, structured-output |

### Skills

| Skill | Source |
|-------|--------|
| jujutsu | `pi/skills/jujutsu/` |
| nix | `pi/skills/nix/` |
| nix-refactor | `pi/skills/nix-refactor/` |
| linux | `pi/skills/linux/` |
| invest | `pi/skills/invest/` |
| personal-tools | `pi/skills/personal-tools/` |
| screenshot | `pi/skills/screenshot/` |
| firefly | `pi/skills/firefly/` |
| lumis | `pi/skills/lumis/` |
| browser | `pi/skills/browser/` |
| seo | `pi/skills/seo/` |
| context-curation | `pi/skills/context-curation/` |
| opencode-edit | `pi/skills/opencode-edit/` |
| opencode-session | `pi/skills/opencode-session/` |
| nix-auditor | `pi/skills/nix-auditor/` (pi-specific) |

---

## SOPS Secrets Used

| Secret | Source | Consumer |
|--------|--------|----------|
| `hyperApiKey` | `pi/private.yaml` | `pi.nix` → `models.json` (hyper provider apiKey via `!cat`) |
| `lucky-info` | `pi/private.yaml` | `pi.nix` → `APPEND_SYSTEM.md` |
| `skillFireflyPrivate` | `pi/private.yaml` | `pi.nix` → `xdg.configFile pi/skills/firefly/resources/private.md` |
| `skillLumisPrivate` | `pi/private.yaml` | `pi.nix` → `xdg.configFile pi/skills/lumis/resources/private.md` |
| `webSearchJson` | `pi/private.yaml` | `pi.nix` → `home.file web-search.json` |

---

## Quick-Find Cheat Sheet

| What you're looking for | Look in |
|-------------------------|---------|
| Pi settings/providers | `pi.nix` → `programs.pi-coding-agent.settings` |
| Pi custom model providers | `pi.nix` → `home.file models.json` (generated inline) |
| Pi extensions | `pi/extensions/*.ts` |
| Pi custom keybindings | `pi.nix` → `home.file keybindings.json` (generated inline) |
| Pi prompt templates | `pi/prompts/*.md` |
| Pi theme definitions | `pi/themes/*.json` |
| Pi skill definitions | `pi/skills/*/SKILL.md` |
| Pi Ciel personality/context | `pi/context.md` |
| Shared skills (jujutsu, nix, etc.) | `opencode/skills/*/` (symlinked via pi.nix) |
| SOPS secrets used by pi | `secrets.yaml`, `pi/private.yaml` |

---

*Last updated: 2026-06-18 by Ciel. Added retry, branchSummary, treeFilterMode, terminal/images settings, 8 new packages, keybindings.json, and 2 new prompts (nix-audit, commit).*
