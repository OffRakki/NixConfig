# Pi Module Index — On-Demand Reference

---

## Entry Points

| File | Imports |
|------|---------|
| `default.nix` | `./pi.nix` |
| `pi.nix` | `programs.pi-coding-agent`, `home.file` (extensions, skills, prompts, themes), `xdg.configFile` (SOPS skill private data) |

---

## File Index

| File | Keywords |
|------|----------|
| `pi.nix` | pi-coding-agent, deepseek-provider, openai, settings, models, compaction, retry, theme(ciel-cursor), packages(pi-web-access,pi-mcp-adapter,pi-subagents), persistence(.pi), sops-secrets, home.file(symlinked-skills), home.file(individual-resource-files), APPEND_SYSTEM.md |
| `AGENTS.md` | Ciel-personality, pi-specific tool-discipline(read,bash,edit,write,grep,find,ls), skill-routing, nix-managed, sops-refs |
| `extensions/notify.ts` | pi-extension, desktop-notifications, notify-send, agent-end-event, /notify-command |
| `extensions/deepseek-provider.ts` | (unused — reference only; providers defined in `pi.nix` → `models.providers`) |
| `prompts/archive.md` | pi-prompt, session-summary, obsidian-save, frontmatter |
| `prompts/free-roam.md` | pi-prompt, ciel-free-roam, autonomous-exploration, ~/sync/geral/Ciel/ |
| `prompts/nix-rebuild.md` | pi-prompt, nixos-rebuild, jj-sync, nh-os-switch |
| `themes/ciel-cursor.json` | pi-theme, catppuccin-mocha, cursor-theme-colors, 51-tokens |
| `skills/nix-auditor/SKILL.md` | pi-skill, nix-config-audit, dead-code, redundancy, read-only, structured-report |

---

## SOPS Secrets Used

| Secret | Source | Consumer |
|--------|--------|----------|
| `deepseekApiKey` | `secrets.yaml` | `pi.nix` → `models.providers.deepseek.apiKey` |
| `openaiApiKey` | `secrets.yaml` | `pi.nix` → `models.providers.openai.apiKey` |
| `lucky-info` | `pi/private.yaml` | `pi.nix` → `APPEND_SYSTEM.md` |
| `skillFireflyPrivate` | `pi/private.yaml` | `pi.nix` → `xdg.configFile pi/skills/firefly/resources/private.md` |
| `skillLumisPrivate` | `pi/private.yaml` | `pi.nix` → `xdg.configFile pi/skills/lumis/resources/private.md` |

---

## Skills Available (symlinked from opencode)

| Skill | Source |
|-------|--------|
| jujutsu | `modules/opencode/skills/jujutsu/` |
| nix | `modules/opencode/skills/nix/` |
| nix-refactor | `modules/opencode/skills/nix-refactor/` |
| linux | `modules/opencode/skills/linux/` |
| invest | `modules/opencode/skills/invest/` |
| personal-tools | `modules/opencode/skills/personal-tools/` |
| screenshot | `modules/opencode/skills/screenshot/` |
| firefly | `modules/opencode/skills/firefly/` |
| lumis | `modules/opencode/skills/lumis/` |
| browser | `modules/opencode/skills/browser/` |
| seo | `modules/opencode/skills/seo/` |
| context-curation | `modules/opencode/skills/context-curation/` |

**Pi-specific skills:**
| Skill | Source |
|-------|--------|
| nix-auditor | `modules/pi/skills/nix-auditor/` |

---

## Quick-Find Cheat Sheet

| What you're looking for | Look in |
|-------------------------|---------|
| Pi settings/providers | `pi.nix` → `programs.pi-coding-agent.settings` + `.models` |
| Pi extensions (deepseek, notify) | `pi/extensions/*.ts` |
| Pi prompt templates | `pi/prompts/*.md` |
| Pi theme definitions | `pi/themes/*.json` |
| Pi skill definitions | `pi/skills/*/SKILL.md` |
| Pi Ciel personality/context | `pi/AGENTS.md` |
| Shared skills (jujutsu, nix, etc.) | `opencode/skills/*/` (symlinked via pi.nix) |
| SOPS secrets used by pi | `secrets.yaml`, `pi/private.yaml` |

---

*Last updated: 2026-06-17 by Ciel.*
