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
| `pi.nix` | pi-coding-agent, deepseek-provider, openai, settings, models, compaction, retry, theme(ciel-cursor), packages(pi-web-access,pi-mcp-adapter,pi-subagents), persistence(.pi), sops-secrets, home.file(symlinked-skills), home.file(individual-resource-files), APPEND_SYSTEM.md |
| `context.md` | Ciel-personality, pi-specific tool-discipline(read,bash,edit,write,grep,find,ls), skill-routing, nix-managed, sops-refs |
| `extensions/notify.ts` | pi-extension, desktop-notifications, notify-send, agent-end-event, /notify-command |
| `prompts/archive.md` | pi-prompt, session-summary, obsidian-save, frontmatter |
| `prompts/free-roam.md` | pi-prompt, ciel-free-roam, autonomous-exploration, ~/sync/geral/Ciel/ |
| `prompts/nix-rebuild.md` | pi-prompt, nixos-rebuild, jj-sync, nh-os-switch |
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
| `deepseekApiKey` | `secrets.yaml` | `pi.nix` → `models.providers.deepseek.apiKey` |
| `openaiApiKey` | `secrets.yaml` | `pi.nix` → `models.providers.openai.apiKey` |
| `lucky-info` | `pi/private.yaml` | `pi.nix` → `APPEND_SYSTEM.md` |
| `skillFireflyPrivate` | `pi/private.yaml` | `pi.nix` → `xdg.configFile pi/skills/firefly/resources/private.md` |
| `skillLumisPrivate` | `pi/private.yaml` | `pi.nix` → `xdg.configFile pi/skills/lumis/resources/private.md` |
| `webSearchJson` | `pi/private.yaml` | `pi.nix` → `home.file web-search.json` |

---

## Quick-Find Cheat Sheet

| What you're looking for | Look in |
|-------------------------|---------|
| Pi settings/providers | `pi.nix` → `programs.pi-coding-agent.settings` |
| Pi extensions | `pi/extensions/*.ts` |
| Pi prompt templates | `pi/prompts/*.md` |
| Pi theme definitions | `pi/themes/*.json` |
| Pi skill definitions | `pi/skills/*/SKILL.md` |
| Pi Ciel personality/context | `pi/context.md` |
| Shared skills (jujutsu, nix, etc.) | `opencode/skills/*/` (symlinked via pi.nix) |
| SOPS secrets used by pi | `secrets.yaml`, `pi/private.yaml` |

---

*Last updated: 2026-06-18 by Ciel.*
