---
name: pi-tools
description: Use when Lucky asks about Pi runtime tools, extensions, packages, prompt templates, model providers, custom agents, or when updating skills/agents so they know which Pi tools to use.
---

# Pi Tools & Extension Inventory

This repo manages Pi from `~/Projects/NixConfig/hosts/sora/home-manager/modules/pi/`.
Runtime files under `~/.pi/agent/` are Home Manager outputs or package installs;
read/edit the NixConfig sources instead.

## Source-of-truth paths

| Thing | Source path |
|---|---|
| Pi settings/packages/models | `hosts/sora/home-manager/modules/pi/pi.nix` |
| Ciel context | `hosts/sora/home-manager/modules/pi/context.md` |
| User skills | `hosts/sora/home-manager/modules/pi/skills/<name>/SKILL.md` |
| Custom agents | `hosts/sora/home-manager/modules/pi/agents/**.md` |
| Custom extensions | `hosts/sora/home-manager/modules/pi/extensions/*.ts` |
| Prompt templates | `hosts/sora/home-manager/modules/pi/prompts/*.md` |
| Themes | `hosts/sora/home-manager/modules/pi/themes/*.json` |
| Runtime package install dir | `~/.pi/agent/npm/` (read-only for source changes) |

When creating a new Nix-managed skill, register it in `pi.nix` under `home.file`,
add a routing line in `context.md` if it needs proactive loading, and update
`INDEX.md` when the module surface changes.

## Installed Pi packages

Declared in `pi.nix -> programs.pi-coding-agent.settings.packages`:

| Package | Provides / use when |
|---|---|
| `pi-drawio` | `drawio` skill for native draw.io diagrams and exports. |
| `pi-intercom` | `intercom` tool + skill for coordinating multiple local Pi sessions. |
| `pi-lean-ctx` | `ctx_*`, `lean_ctx`, graph/knowledge/session/search helpers; token-efficient reads/searches/build output. |
| `pi-lens` | LSP diagnostics/navigation plus `ast_grep_*` and `lens_diagnostics`. Primary code-intelligence layer. |
| `pi-chrome` | Browser profile bridge package. The local `browser` skill currently uses its own Playwright helper, so verify the active browser path before assuming profile sharing. |
| `pi-simplify` | Extension that reviews recently changed code for clarity/maintainability. |
| `pi-namespace` | Namespaces tools/skills and may prefix tools by extension. |
| `pi-ask-user` | `ask_user` tool and `ask-user` skill for one focused decision handshake. |
| `pi-web-access` | `web_search`, `code_search`, `fetch_content`, `get_search_content`, and `librarian` skill. |
| `pi-mcp-adapter` | `mcp` gateway for MCP servers/tools. |
| `pi-markdown-preview` | `preview_export` for Markdown/LaTeX/file -> PDF/HTML/PNG artifacts. |
| `pi-powerline-footer` | Powerline footer/status UI. Preset is `nerd`. |
| `pi-hermes-memory` | `memory`, `memory_search`, `session_search`, `skill_manage`; durable memory and procedural skills. |
| `pi-invisible-continue` | Invisible continuation extension; resumes agent loops without visible prompt pollution. |
| `pi-subagents` | `subagent` tool, `/run`/chains/parallel workflows, packaged role agents/prompts. |
| `@ogulcancelik/pi-sketch` | Browser sketch pad package for visual sketching when available. |
| `@tintinweb/pi-subagents` | Additional Claude-style autonomous subagent extension. Prefer the active `subagent` tool and documented project agents. |
| `@juicesharp/rpiv-pi` | `discover/research/design/plan/implement/validate/code-review/...` skills and workflow agents. |
| `@juicesharp/rpiv-todo` | `todo` tool, live overlay task list. Use for multi-step task tracking. |
| `@juicesharp/rpiv-args` | Skill argument interpolation (`$1`, `$ARGUMENTS`, shell substitutions) for slash-invoked skills. |
| `@juicesharp/rpiv-btw` | `/btw` side-question command that avoids polluting the main thread. |
| `@juicesharp/rpiv-i18n` | Locale registry, `/languages`, and `--locale` support for rpiv skills. |
| `@juicesharp/rpiv-advisor` | `advisor` tool for stronger-model second opinions before major work/done. |
| `@juicesharp/rpiv-workflow` | Typed multi-stage workflow DSL. Read rpiv-workflow docs before authoring workflows. |
| `@juicesharp/rpiv-ask-user-question` | `ask_user_question` structured questionnaire tool (2-4 options, 1-4 questions). |
| `@vigolium/piolium` | Security audit/review skills: Semgrep, CodeQL, vuln reports, threat models, etc. |

## Tool routing cheat sheet

Use the most specific tool available; don't shell out when Pi has a tool built
for the job.

| Need | Preferred tool(s) | Notes |
|---|---|---|
| Read known file | `read` for native Pi/LSP hooks; `ctx_read` for cached/token-efficient reads | For Nix LSP warmup, use native `read` on a `.nix` file first. |
| Search files/text | `ctx_find`, `ctx_grep`, `ctx_search` | Use `ctx_*` instead of raw `find/rg` for compact output unless a skill requires bash. |
| Semantic/code pattern search | `ast_grep_search`, `ctx_semantic_search`, `lsp_navigation` | Use AST/LSP for code intelligence; grep is fallback. |
| Code diagnostics | `lsp_diagnostics`, `lens_diagnostics` | Check edited files before builds; `lens_diagnostics mode=all` before done. |
| Build/test/side effects | `ctx_shell` or `shell` | Use `ctx_shell` for verbose Nix/build output. |
| Web research/docs | `web_search`, `code_search`, `fetch_content` | Use `queries:[...]` for broad web research; use `code_search` for API usage. |
| URL/page/PDF/video content | `fetch_content`, then `get_search_content` if needed | For YouTube/video, pass the user question as `prompt`. |
| Logged-in/browser UI | `browser` skill (`pi-chrome`) | Use only when JS/session/cookies/UI interaction matter. |
| User decision | `ask_user` or `ask_user_question` | Use `ask_user` for one focused question; `ask_user_question` for structured 1-4 question forms. |
| Persistent memory/procedures | `memory`, `memory_search`, `session_search`, `skill_manage` | Save durable preferences/conventions; don't save temporary task state. |
| Task list | `todo` | Exactly one in-progress task; mark completion immediately. |
| Subagents | `subagent` / `Agent` | Prefer async/read-only fanout; keep writes single-threaded. |
| MCP servers | `mcp` | Discover/list/describe before calling unfamiliar MCP tools. |
| Markdown/LaTeX previews | `preview_export` | Export same-turn content by passing `markdown`, not `last_assistant`. |
| Cross-session coordination | `intercom` | Use for local Pi sessions and subagent bridge coordination. |
| Diagrams | `drawio` skill | Load the skill; produce real `.drawio` when asked for diagrams. |
| Security audit | piolium skills (`audit`, `semgrep`, `codeql`, etc.) | Load matching security skill before scanning/reviewing. |

## Editing skills and agents to use tools

When updating a skill/agent:

1. Keep domain skills focused; add only the tool guidance that changes behavior.
2. Prefer a short `## Pi tool usage` or `## Tooling` section over duplicating the full inventory.
3. Replace old harness names (`opencode`, `task(...)`, `webfetch`) with Pi-native names:
   - `~/.config/opencode/skills/...` -> `~/.pi/agent/skills/...` for runtime paths, or NixConfig source paths for edits.
   - `task(...)` -> `Agent(...)` or `subagent(...)`, depending on the agent system being used.
   - `webfetch` -> `fetch_content` or a deliberate CLI fetch.
   - `/tmp/opencode/...` -> `/tmp/pi/...`.
4. For file-mutating tools or workflows, mention validation with `lsp_diagnostics`, `lens_diagnostics`, tests, or the specific domain command.
5. Do not add secrets, decrypted private data, or generated reports to NixConfig. Use `~/sync/geral/Ciel/` for artifacts.

## Custom extension: notify

Source: `extensions/notify.ts`.

Behavior:

- On every `agent_end`, sends a desktop notification with the current session id.
- Registers `/notify <summary>` to send a manual desktop notification and an in-TUI notification.

For explicit notification commands in normal chat, Ciel should still use the
project's standard `notify-send --app-name="Pi" ...` snippet from `context.md`
unless the user specifically asks for the slash command.

## Validation after Pi config changes

Minimal checks after source edits:

```bash
nix flake check --no-build
```

For changes to `pi.nix` package lists, models, skills, agents, prompts, themes,
or extensions, build/apply via the `nix` skill's rebuild workflow. A Home Manager
activation is needed before `~/.pi/agent/` reflects the new source symlinks.
