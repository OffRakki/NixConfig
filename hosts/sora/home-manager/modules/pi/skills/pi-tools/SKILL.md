---
name: pi-tools
description: Use when Lucky asks about Pi runtime tools, extensions, packages, prompts, models, custom agents, or package/skill configuration.
---

# Pi Tools & Packages

Pi is managed from `~/Projects/NixConfig/hosts/sora/home-manager/modules/pi/`.
Runtime files under `~/.pi/agent/` are outputs, not sources; never edit them.

## Source of truth

| Thing | Source |
|---|---|
| Pi settings/models | `pi.nix` |
| Nix-built packages | `packages/` |
| Trust/capabilities | `packages/inventory.json` |
| Context | `context.md` |
| Skills | `skills/<name>/SKILL.md` |
| Agents/extensions/prompts/themes | matching directory under the module |

`packages/default.nix` defines the active package roots and asserts parity with
`package.json` and `inventory.json`.

## Active Pi packages

| Package | Provides |
|---|---|
| `@dietrichgebert/ponytail` | YAGNI implementation/review skills |
| `@juicesharp/rpiv-ask-user-question` | `ask_user_question` |
| `pi-agent-browser-native` | `agent_browser` and browser automation |
| `pi-codex-image-gen` | `codex_generate_image` and `imagegen` |
| `pi-intercom` | `intercom` and cross-session coordination |
| `pi-invisible-continue` | automatic agent-loop continuation |
| `pi-powerline-footer` | powerline status UI |
| `pi-subagents` | `subagent`, `wait`, and packaged agents |
| `pi-web-access` | `web_search`, `fetch_content`, `get_search_content`, and `librarian` |

`lean-ctx` is installed as a companion CLI package on `PATH`; it is not an
active Pi extension and does not provide `ctx_*` tools in this configuration.

## Tool routing

| Need | Use |
|---|---|
| Read/edit files | `read`, `edit`, `write` |
| Search or run commands | `bash` |
| Browser UI/JS/downloads | `agent_browser` via the `browser` skill |
| Public web research/content | `web_search`, `fetch_content`, `get_search_content` |
| Image generation/editing | `codex_generate_image` via `imagegen` |
| User decision | `ask_user_question` |
| Subagents | `subagent`, then `wait` only when blocking is required |
| Cross-session coordination | `intercom` |

Do not route work to removed APIs such as `ctx_*`, `lsp_*`, `lens_*`,
`ast_grep_*`, `todo`, `preview_export`, `memory`, or `skill_manage`.

## Updating a package pin

1. Update the exact version in `packages/package.json`.
2. Run `npm install --package-lock-only --ignore-scripts --legacy-peer-deps` in `packages/`.
3. Update `inventory.json` when version or capabilities changed.
4. Set `npmDepsHash = pkgs.lib.fakeHash`, build, and replace it with Nix's reported hash.
5. Build the Sora configuration before applying it. Do not use `pi update --extensions`; Nix owns the closure.

## Validation

After Pi source changes, run `nix flake check --no-build`. Package, model,
skill, agent, prompt, theme, and extension changes need Home Manager activation
before runtime paths update.
