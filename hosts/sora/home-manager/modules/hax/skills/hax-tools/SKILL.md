---
name: hax-tools
description: HAX pilot capability inventory, Nix-owned configuration, sessions, native tasks, and migration boundaries.
---

# HAX pilot

Source: `/home/rakki/Projects/NixConfig/hosts/sora/home-manager/modules/hax/`.
Package: `inputs.llm-agents.packages.<system>.hax`, pinned by `flake.lock`;
initial version 0.5.0. Check `hax --version` and `hax --help` for the installed
interface. Matching upstream docs are available from the package's `src/docs`
through Nix evaluation; do not read deployed config as source.

## Available capabilities

- Native HAX read/edit/write/bash and managed background tasks; inspect current
  tool schemas rather than copying Pi calls. Images require a capable model.
- `agent-browser` + Chromium through the browser skill, launched only when used.
- Jujutsu through its skill. Nix evaluation/build/activation through `nix`.
- Existing desktop tools; do not launch browsers, brokers or MCP at startup.

No web-search CLI, MCP configuration, image-generation CLI, suggestion writer,
intercom transport, custom specialist roles, council runner or workspace launcher
is installed by this module yet. Existing Pi functionality is not HAX parity.
Do not call Pi tool names or run Pi to fill a missing HAX capability silently.

## Configuration and credentials

`settings.nix` generates immutable config. `context.md` generates global AGENTS.md;
`default.nix` deploys an explicit skill map. Add new skills there, not by editing
runtime outputs. Read source and referenced files before making changes.
`/preset-save` tries to write config and is not the declarative workflow.

Default provider is `codex`; use native `/login` for HAX-owned auth. No credentials
are copied from Pi, decrypted, exported or embedded by this module. Anthropic and
Hyper runtime-secret integration is deferred. Do not switch to separately billed
API access without permission. Offline smoke tests use a mock, not real accounts.

## Sessions and context

Use `hax -p` for one-shot text; `hax --json` for one-shot JSONL ending in a result
record. Check both exit status and terminal outcome; missing results are not
success. Use explicit `--resume=ID` for concurrent automation, never “latest”.
`-c` resumes the latest session for the current cwd. `/undo` and `/fork` do not
restore files. Retention is disabled for the pilot; state persists across boots.
Ctrl-T opens model-facing context; Ctrl-O opens the conversation; Ctrl-G uses
`$EDITOR`. No Pi injection inspector or custom keybinding schema is carried over.

Project skill discovery is Git-root-based and can shadow global skills. Test
instruction discovery in jj workspaces before relying on inherited context.

## Delegation

Only explicitly authorized tasks should use subprocess agents. No named custom
roles are advertised yet. Native tasks own cancellation/result delivery; do not
create another scheduler. Children do not automatically receive the parent chat.
Pass bounded context and explicit cwd/provider/model; collect results before the
parent final answer in one-shot mode. Background tasks stop on conversation exit.

`--bare` excludes AGENTS.md, skills and delegation guidance but keeps tools;
`--raw` removes tools as well. Neither restricts filesystem or network access.
A described preset advertises a role but does not implement Pi inheritance flags
or tool allowlists. Do not claim read-only enforcement from role prose alone.

## Validation

Run `nix flake check --no-build`, then build Sora with the nix skill workflow.
Package install checks run `tests/smoke.py` against isolated HOME/XDG directories,
mock tool calls, JSON outcomes, skill discovery and clean-context behavior. They
never use live model credentials. A passing mock test verifies integration, not
model quality, account access, or startup-speed claims. Activation is separate.
