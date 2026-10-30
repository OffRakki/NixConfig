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
| `@apat183/pi-buddy` | animated Pi header, state widget, and spinner |
| `@groeponline/pi-agent-orchestrator` | `Agent`, `get_subagent_result`, `steer_subagent`, `/agents`, scheduling, and orchestra workflows |
| `@juanibiapina/pi-extension-settings` | shared extension settings UI |
| `@juanibiapina/pi-powerbar` | persistent powerline status UI and usage segments |
| `@juicesharp/rpiv-ask-user-question` | `ask_user_question` |
| `@jamesjfoong/pi-ollama` | discovers downloaded Ollama chat models; `/ollama-refresh` refreshes them |
| `@wishx127/pi-tokyo-night` | Tokyo Night themes, rain panel, and status UI |
| `pi-agent-browser-native` | `agent_browser`, `agent_browser_code`, `agent_browser_tools`, and advanced browser tools |
| `pi-codex-image-gen` | `codex_generate_image` and `imagegen` |
| `pi-context-view` | `/context` usage map and `/context injections` inspector |
| `pi-intercom` | `intercom` and cross-session coordination |
| `pi-invisible-continue` | automatic agent-loop continuation |
| `pi-subagents` | `subagents_enable`, `subagent`, `bg_wait`, and packaged agents |
| `pi-web-access` | `web_enable`, `web_search`, `source_check`, `fetch_content`, and `get_search_content` |
| `rinco-pi-sakura` | Sakura Macaron theme and animated header |

Agent Orchestrator complements `pi-subagents`; existing delegation routing remains unchanged.
Use its `/agents` dashboard or `/orchestra-audit` and `/orchestra-plan` workflows
when explicitly requested. Its Git-worktree isolation is not suitable for this
jj-managed workspace; do not enable it here. Multi-agent dispatch still requires
authorization, regardless of which extension provides it.

`lean-ctx` is installed as a companion CLI package on `PATH`; it is not an
active Pi extension and does not provide `ctx_*` tools in this configuration.

## Restricted mail runs

`pi-mail <hexadecimal-session-id>` reads a rendered email prompt from stdin and
runs in `/home/rakki/sync/geral/Ciel/Mailbox`. It loads only `extensions/notify.ts`
and enables only `desktop_notify`; no shell, filesystem, subagent, or MCP tools.
It preserves normal Pi defaults outside this launcher. Attachments must be
extracted upstream until a separately scoped attachment reader is implemented.

`desktop_notify` passes bounded, markup-escaped text to `notify-send` as literal
arguments with `shell: false` and `--`. It permits one attempt per request,
propagates cancellation, and reports failures. Use this tool in mail prompts,
not instructions to invoke `notify-send` through bash. The launcher supplies
the desktop D-Bus address for SSH sessions.

Keep prompts base64-encoded across the SSH command boundary. Validate the
session ID and base64 alphabet in n8n before shell interpolation; checks inside
the launcher happen too late to protect the enclosing SSH shell. This prevents
shell injection through these arguments, not prompt injection or misleading replies.

## Local Ollama models

`pi.nix` declares `pi-ollama.json` and the `ollama/*` model scope.
Discovery runs on startup; after pulling a model in an existing session, use
`/ollama-refresh`, then `/model`. Embedding models are excluded from chat.
The endpoint is Nix-managed; do not use `/ollama-setup` to rewrite it.

Ollama discovery reports a model's trained context maximum, not its allocated
runtime window. `hosts/modules/ai.nix` sets `OLLAMA_CONTEXT_LENGTH`; `pi.nix`
derives discovery's `globalModelDefaults.contextWindow` from that same value.
Set `globalModelDefaults.compat.supportsDeveloperRole = false` so Pi sends
instructions as `system`, not `developer`; this Ollama path ignores the latter.
Set `maxTokensField = "max_tokens"` there too. Provider-level compatibility alone
was insufficient with this discovery extension on Pi 1.0.
Qwen3.5 9B and Qwen3.8 27B Q4_K_M have smaller per-model compaction budgets;
cloud defaults stay intact. The 27B model needs CPU offloading on the RTX 5070;
benchmark both prompt processing and generation before promising usable speed.
When adding local models, check their compaction budgets against this window.
Verify `/api/ps` context allocation and test a long prompt for truncation; merely
registering a model or testing a short greeting does not validate context.

## Tool routing

| Need | Use |
|---|---|
| Read/edit files | `read`, `edit`, `write` |
| Search or run commands | `bash` |
| Browser UI/JS/downloads | `agent_browser` via the `browser` skill |
| Public web research/content | `web_search`, `fetch_content`, `get_search_content` |
| Image generation/editing | `codex_generate_image` via `imagegen` |
| User decision | `ask_user_question` |
| Subagents | Enable with `subagents_enable` if needed; use `subagent`, then `bg_wait` only when blocking is required |
| Cross-session coordination | `intercom` |

Do not route work to removed APIs such as `ctx_*`, `lsp_*`, `lens_*`,
`ast_grep_*`, `todo`, `preview_export`, `memory`, or `skill_manage`.

## Updating a package pin

Always update all Nix-managed Pi packages when updating Pi itself; choose the
latest compatible releases rather than ignoring Node/Pi support floors.
Browser-native 0.8 requires Node >=24.21.0; the current Node 24.19.0 supports 0.7.1.

1. Review release/source changes and update the exact version in `packages/package.json`.
2. Run `npm install --package-lock-only --ignore-scripts --legacy-peer-deps` in `packages/`.
3. Update `inventory.json` when version or capabilities changed.
4. Set `npmDepsHash = pkgs.lib.fakeHash`, build, and replace it with Nix's reported hash.
5. Build the Sora configuration before applying it. Do not use `pi update --extensions`; Nix owns the closure.

## Validation

After Pi source changes, run `nix flake check --no-build`. Package, model,
skill, agent, prompt, theme, and extension changes need Home Manager activation
before runtime paths update. `--list-models` alone does not exercise extension
loading: also smoke-test `DefaultResourceLoader.reload()` and session binding
with an isolated HOME, checking errors and registered tools without a model call.
Pi 1.0's Nix postInstall must preserve the `pi-codemode` and `pi-mcp` workspaces
alongside the existing host libraries so unbundled SDK imports can resolve.
The Nix package patch removes pi-subagents 0.74's unused legacy
`pi-agent-core/node` alias requirement, absent in Pi 1.0. The package install check
must also validate `resolveHostPeerAliases()`; extension/session loading alone
misses detached-child startup failures. Revisit the patch when updating pi-subagents.
Fresh SDK hosts outside Pi's CLI also need the supported
`PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT` environment override pointing to Pi's
installed package root before loading the extension; CLI argv discovery supplies
that root in normal interactive sessions.
