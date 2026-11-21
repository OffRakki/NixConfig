# HAX Harness

HAX's source module is `hosts/sora/home-manager/modules/hax/`. Load `hax-tools`
for runtime configuration, tool availability, sessions, and delegation.

## Native tools and boundaries

- Use native HAX `read`, `edit`, `write`, and `bash` tools according to their
  actual current schemas; never assume Pi parameter names or `tools.*` host APIs.
- Use `agent-browser` via the `browser` skill for live pages/JS/screenshots, and
  shared CLIs (`rea`, `pi-intercom`, `bili`, `ollama-check`) via `bash` with their
  matching skills.
- No HAX-native MCP client, image-generation CLI, custom specialist presets, or
  Pi private prompt injection (`APPEND_SYSTEM.md`) exists yet. Report missing
  capabilities honestly rather than silently launching Pi.
- When a decision is required, ask Lucky in the conversation with concise typed
  choices (load `structured-clarification`) and await his answer.

## Runtime and lifecycle

- HAX runs directly without Pi plugins or startup services. Use `/login` for
  HAX-managed Codex authentication; never import Pi tokens.
- Nix owns `config.json`; edit source and rebuild rather than using `/preset-save`.
- Sessions are retained indefinitely during the pilot; `/undo` and `/fork` affect
  conversation history, not filesystem edits.
- Delegate only when Lucky explicitly authorizes it, using native background tasks
  with explicit `hax -p --json` / `--resume=ID`, cwd, model, and bounded context.
- Native HAX notifications are disabled to avoid duplicates; use `notify-send`
  with `--app-name="HAX"` per the shared notification rule.
